"""The HR core's decoders and its two computed answers, written independently.

The reader in `log_reader.py` proves the LOG is sound: every hash, every link, every tip. This
module proves the two HR facts that are *computed* rather than merely stored, from the log alone:

  * **every leave balance** - accrued, taken, adjusted, and what remains;
  * **every person's day** - the punches, paired, with the minutes the contract recorded and the
    corrections that superseded them.

Those two are chosen because they are the ones a person is paid on, and because they are the ones a
scan-based implementation gets subtly wrong: the received tree recomputes a balance by walking the
requests each time, and it pairs punches by guessing, because nothing stops a person having two
open ones.

The rules below are written from the design, not translated from the Motoko. Where they disagree
with the contract, one of the two is wrong and the gate says so.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import Reader

# ── the enumeration codes, from the design ──────────────────────────────────────

COMPANY_ROLE = {1: "CompanyAdmin", 2: "HR", 3: "Director", 4: "Manager", 5: "Employee", 6: "Auditor", 7: "Drafter"}
PLATFORM_ROLE = {1: "PlatformAdmin", 2: "PlatformSupport", 3: "Auditor", 4: "None"}
SENIORITY = {
    1: "Intern", 2: "Junior", 3: "Associate", 4: "Mid", 5: "Senior", 6: "Lead", 7: "Principal",
    8: "Staff", 9: "Manager", 10: "SeniorManager", 11: "Director", 12: "SeniorDirector",
    13: "VP", 14: "SVP", 15: "EVP", 16: "Head", 17: "Chief", 18: "Unrecorded",
}
ATTENDANCE = {1: "Present", 2: "Absent", 3: "Late", 4: "OnLeave", 5: "Remote"}
PUNCH_SOURCE = {1: "self", 2: "device", 3: "tablet", 4: "correction", 5: "import"}
LEAVE_TYPE = {1: "Annual", 2: "Sick", 3: "Unpaid", 4: "Personal", 5: "Maternity",
              6: "Paternity", 7: "Emergency", 8: "WorkFromHome"}
LEAVE_STATE = {1: "Pending", 2: "Approved", 3: "Rejected", 4: "Cancelled", 5: "Withdrawn"}

MINUTES_IN_DAY = 1440


def named(table, b, what):
    if b not in table:
        raise ValueError("unknown %s code %d" % (what, b))
    return table[b]


def zag(n):
    return n // 2 if n % 2 == 0 else -((n + 1) // 2)


# ── the payload decoders ────────────────────────────────────────────────────────

def read_self(r):
    return {
        "phone": r.text(), "location": r.text(), "address": r.text(), "city": r.text(),
        "country": r.text(), "emergencyContact": r.text(), "emergencyPhone": r.text(),
        "language": r.text(), "timezone": r.text(), "avatarUrl": r.text(),
        "emailNotifications": read_opt_bool(r), "pushNotifications": read_opt_bool(r),
        "weeklyDigest": read_opt_bool(r),
    }


def read_opt_bool(r):
    tag = r.byte()
    if tag == 0:
        return None
    if tag != 1:
        raise ValueError("an option tag that is neither 0 nor 1: %d" % tag)
    return r.bool()


def read_standing(r):
    return {
        "departmentId": r.nat(), "jobTitleId": r.nat(), "managerId": r.nat(),
        "seniority": named(SENIORITY, r.nat8(), "seniority"), "isActive": r.bool(),
    }


def read_amendment(r):
    return {"name": r.text(), "orgCode": r.text(),
            "geoLat": read_opt_zig(r), "geoLon": read_opt_zig(r),
            "geoRadiusMetres": r.nat(), "geoRequireLocation": r.bool()}


def read_opt_zig(r):
    tag = r.byte()
    if tag == 0:
        return None
    if tag != 1:
        raise ValueError("an option tag that is neither 0 nor 1: %d" % tag)
    return zag(r.nat())


def read_branch(r):
    return {"companyId": r.nat(), "name": r.text(), "code": r.text(), "address": r.text(),
            "geoLat": read_opt_zig(r), "geoLon": read_opt_zig(r), "geoRadiusMetres": r.nat()}


def read_dept(r):
    return {"companyId": r.nat(), "parentId": r.nat(), "name": r.text(), "code": r.text()}


def read_title(r):
    return {"companyId": r.nat(), "name": r.text(), "code": r.text(),
            "seniority": named(SENIORITY, r.nat8(), "seniority")}


def read_person(r):
    return {"companyId": r.nat(), "subject": r.principal(), "name": r.text(), "email": r.text(),
            "startDay": r.nat(), "standing": read_standing(r), "details": read_self(r)}


# ── tag → (family, reader) ──────────────────────────────────────────────────────

READERS = {
    1:  ("amendCompany",           lambda r: {"companyId": r.nat(), "amendment": read_amendment(r)}),
    2:  ("createBranch",           lambda r: {"facts": read_branch(r)}),
    3:  ("amendBranch",            lambda r: {"branchId": r.nat(), "facts": read_branch(r)}),
    4:  ("closeBranch",            lambda r: {"branchId": r.nat(), "reason": r.text()}),
    5:  ("createDepartment",       lambda r: {"facts": read_dept(r)}),
    6:  ("amendDepartment",        lambda r: {"departmentId": r.nat(), "facts": read_dept(r)}),
    7:  ("closeDepartment",        lambda r: {"departmentId": r.nat(), "reason": r.text()}),
    8:  ("declareJobTitle",        lambda r: {"facts": read_title(r)}),
    9:  ("amendJobTitle",          lambda r: {"jobTitleId": r.nat(), "facts": read_title(r)}),
    10: ("retireJobTitle",         lambda r: {"jobTitleId": r.nat(), "reason": r.text()}),
    11: ("admitMember",            lambda r: {"companyId": r.nat(), "subject": r.principal(),
                                              "companyRole": named(COMPANY_ROLE, r.nat8(), "company role"),
                                              "platformRole": named(PLATFORM_ROLE, r.nat8(), "platform role"),
                                              "managerId": r.nat()}),
    12: ("setMemberRole",          lambda r: {"companyId": r.nat(), "subject": r.principal(),
                                              "companyRole": named(COMPANY_ROLE, r.nat8(), "company role")}),
    13: ("setManagers",            lambda r: {"companyId": r.nat(), "subject": r.principal(), "managerId": r.nat()}),
    14: ("suspendMember",          lambda r: {"companyId": r.nat(), "subject": r.principal(), "reason": r.text()}),
    15: ("reinstateMember",        lambda r: {"companyId": r.nat(), "subject": r.principal(), "reason": r.text()}),
    16: ("registerEmployee",       lambda r: {"facts": read_person(r)}),
    17: ("amendEmployeeDetails",   lambda r: {"companyId": r.nat(), "subject": r.principal(), "details": read_self(r)}),
    18: ("amendEmployeeStanding",  lambda r: {"companyId": r.nat(), "subject": r.principal(),
                                              "standing": read_standing(r), "reason": r.text()}),
    19: ("punchIn",                lambda r: {"companyId": r.nat(), "subject": r.principal(), "branchId": r.nat(),
                                              "source": named(PUNCH_SOURCE, r.nat8(), "punch source"), "note": r.text()}),
    20: ("punchOut",               lambda r: {"companyId": r.nat(), "subject": r.principal(), "note": r.text()}),
    21: ("requestPunchCorrection", lambda r: {"companyId": r.nat(), "subject": r.principal(), "punchId": r.nat(),
                                              "inMinute": r.nat(), "outMinute": r.nat(),
                                              "status": named(ATTENDANCE, r.nat8(), "attendance status"),
                                              "reason": r.text()}),
    22: ("decidePunchCorrection",  lambda r: {"companyId": r.nat(), "correctionId": r.nat(),
                                              "approve": r.bool(), "reason": r.text()}),
    23: ("requestLeave",           lambda r: {"companyId": r.nat(), "subject": r.principal(),
                                              "leaveType": named(LEAVE_TYPE, r.nat8(), "leave type"),
                                              "fromDay": r.nat(), "toDay": r.nat(), "quantity": r.nat(),
                                              "reason": r.text()}),
    24: ("decideLeave",            lambda r: {"companyId": r.nat(), "requestId": r.nat(),
                                              "approve": r.bool(), "reason": r.text()}),
    25: ("withdrawLeave",          lambda r: {"companyId": r.nat(), "requestId": r.nat()}),
    26: ("adjustLeaveBalance",     lambda r: {"companyId": r.nat(), "subject": r.principal(),
                                              "leaveType": named(LEAVE_TYPE, r.nat8(), "leave type"),
                                              "delta": zag(r.nat()), "reason": r.text()}),
    27: ("accrueLeave",            lambda r: {"companyId": r.nat(),
                                              "leaveType": named(LEAVE_TYPE, r.nat8(), "leave type"),
                                              "planHash": r.blob(), "asOfDay": r.nat(),
                                              "quantity": r.nat(), "subjects": read_principals(r)}),
}


PAY_FREQUENCY = {1: "Weekly", 2: "BiWeekly", 3: "SemiMonthly", 4: "Monthly"}


def read_profile(r):
    return {"jurisdiction": r.text(), "effectiveDay": r.nat(), "currency": r.text(),
            "socialEmployeeRate": r.nat(), "socialEmployerRate": r.nat(),
            "socialCeiling": r.nat(), "socialFloor": r.nat(), "personalAllowance": r.nat()}


def read_bracket(r):
    return {"profileId": r.nat(), "ordinal": r.nat(), "fromAmount": r.nat(),
            "toAmount": r.nat(), "rate": r.nat()}


def read_comp(r):
    return {"companyId": r.nat(), "subject": r.principal(), "currency": r.text(),
            "baseMonthly": r.nat(), "hourlyRate": r.nat(),
            "frequency": named(PAY_FREQUENCY, r.nat8(), "pay frequency"),
            "profileId": r.nat(), "effectiveDay": r.nat()}


def read_slice(r):
    return {"companyId": r.nat(), "runId": r.nat(), "planHash": r.blob(),
            "subjects": read_principals(r), "overtimeMinutes": read_nats(r), "bonuses": read_nats(r)}


def read_nats(r):
    n = r.len16()
    return [r.nat() for _ in range(n)]


def read_postings(r):
    n = r.len16()
    return [(r.text(), r.nat()) for _ in range(n)]


def read_principals(r):
    n = r.len16()
    return [r.principal() for _ in range(n)]


# The payroll families. They are registered after their helpers rather than inside the literal above
# because the helpers are defined below it; `READERS` is one table either way, and the tag numbers
# are what matter.
READERS.update({
    28: ("declareStatutoryProfile", lambda r: {"facts": read_profile(r)}),
    29: ("declareTaxBracket",       lambda r: {"facts": read_bracket(r)}),
    30: ("retireStatutoryProfile",  lambda r: {"profileId": r.nat(), "reason": r.text()}),
    31: ("setCompensation",         lambda r: {"facts": read_comp(r)}),
    32: ("openPayrollRun",          lambda r: {"companyId": r.nat(), "periodDay": r.nat(),
                                               "planHash": r.blob(), "headcount": r.nat()}),
    33: ("runPayrollSlice",         lambda r: {"facts": read_slice(r)}),
    34: ("closePayrollRun",         lambda r: {"companyId": r.nat(), "runId": r.nat()}),
    35: ("approvePayrollRun",       lambda r: {"companyId": r.nat(), "runId": r.nat(), "reason": r.text()}),
    36: ("postPayrollJournal",      lambda r: {"companyId": r.nat(), "runId": r.nat(),
                                               "debits": read_postings(r), "credits": read_postings(r),
                                               "differenceAccount": r.text(),
                                               "differenceAmount": zag(r.nat())}),
    37: ("abandonPayrollRun",       lambda r: {"companyId": r.nat(), "runId": r.nat(), "reason": r.text()}),
})

ACCOUNT_TYPE = {1: "asset", 2: "liability", 3: "equity", 4: "income", 5: "expense",
                6: "receivable", 7: "payable", 8: "roundingDifference"}
JOURNAL_TYPE = {1: "sale", 2: "purchase", 3: "cash", 4: "bank", 5: "general", 6: "payroll"}
MOVE_TYPE = {1: "entry", 2: "outInvoice", 3: "inInvoice", 4: "outRefund", 5: "inRefund", 6: "closing"}


def read_account_facts(r):
    return {"companyId": r.nat(), "code": r.text(), "name": r.text(),
            "accountType": named(ACCOUNT_TYPE, r.nat8(), "account type"),
            "parentId": r.nat(), "reconcilable": r.bool(), "currency": r.text()}


def read_journal_facts(r):
    return {"companyId": r.nat(), "code": r.text(), "name": r.text(),
            "journalType": named(JOURNAL_TYPE, r.nat8(), "journal type"),
            "defaultAccountId": r.nat()}


def read_move_facts(r):
    companyId = r.nat()
    journalId = r.nat()
    businessDay = r.nat()
    moveType = named(MOVE_TYPE, r.nat8(), "move type")
    currency = r.text()
    partnerId = r.nat()
    ref = r.text()
    n = r.len16()
    lines = []
    for _ in range(n):
        lines.append({"accountId": r.nat(), "partnerId": r.nat(), "name": r.text(),
                      "debit": r.nat(), "credit": r.nat(),
                      "amountCurrency": r.nat(), "taxId": r.nat()})
    return {"companyId": companyId, "journalId": journalId, "businessDay": businessDay,
            "moveType": moveType, "currency": currency, "partnerId": partnerId,
            "ref": ref, "lines": lines}


READERS.update({
    38: ("createAccount",     lambda r: {"facts": read_account_facts(r)}),
    39: ("amendAccount",      lambda r: {"accountId": r.nat(), "facts": read_account_facts(r)}),
    40: ("deprecateAccount",  lambda r: {"accountId": r.nat(), "reason": r.text()}),
    41: ("createJournal",     lambda r: {"facts": read_journal_facts(r)}),
    42: ("amendJournal",      lambda r: {"journalId": r.nat(), "facts": read_journal_facts(r)}),
    43: ("closeJournal",      lambda r: {"journalId": r.nat(), "reason": r.text()}),
    44: ("proposeMove",       lambda r: {"facts": read_move_facts(r)}),
    45: ("postMove",          lambda r: {"companyId": r.nat(), "moveId": r.nat(), "reason": r.text()}),
    46: ("cancelMove",        lambda r: {"companyId": r.nat(), "moveId": r.nat(), "reason": r.text()}),
    47: ("lockPeriod",        lambda r: {"companyId": r.nat(), "lockedThroughDay": r.nat()}),
})

# ── the close, families 308 to 313 ─────────────────────────────────────────────

def read_close_facts(r):
    """`CloseFacts`: companyId, fromDay, throughDay, journalId, retainedEarningsAccountId."""
    return {"companyId": r.nat(), "fromDay": r.nat(), "throughDay": r.nat(),
            "journalId": r.nat(), "retainedEarningsAccountId": r.nat()}


READERS.update({
    308: ("beginClose",        lambda r: {"facts": read_close_facts(r)}),
    309: ("planCloseSlice",    lambda r: {"companyId": r.nat(), "runId": r.nat(), "limit": r.nat()}),
    310: ("cancelClose",       lambda r: {"companyId": r.nat(), "runId": r.nat(), "reason": r.text()}),
    311: ("closePeriod",       lambda r: {"companyId": r.nat(), "runId": r.nat(), "planHash": r.blob()}),
    312: ("reopenClose",       lambda r: {"companyId": r.nat(), "runId": r.nat(), "reason": r.text()}),
    313: ("reverseCloseSlice", lambda r: {"companyId": r.nat(), "runId": r.nat(), "limit": r.nat()}),
})

# ── statements, families 314 to 316 ───────────────────────────────────────────

STATEMENT_KIND = {1: "trialBalance", 2: "balanceSheet", 3: "incomeStatement"}


def read_statement_facts(r):
    """`StatementFacts`: companyId, the kind byte, fromDay, throughDay."""
    return {"companyId": r.nat(), "kind": named(STATEMENT_KIND, r.nat8(), "statement kind"),
            "fromDay": r.nat(), "throughDay": r.nat()}


READERS.update({
    314: ("openStatement",   lambda r: {"facts": read_statement_facts(r)}),
    315: ("statementSlice",  lambda r: {"companyId": r.nat(), "statementId": r.nat(), "limit": r.nat()}),
    316: ("cancelStatement", lambda r: {"companyId": r.nat(), "statementId": r.nat(), "reason": r.text()}),
})

# ── deferrals, families 317 to 320 ────────────────────────────────────────────

DEFERRAL_KIND = {1: "prepaid", 2: "unearned"}


def read_deferral_facts(r):
    """`DeferralFacts`: companyId, the kind byte, deferredAccountId, targetAccountId, journalId,
    sourceMoveId, amount, firstDay, months."""
    return {"companyId": r.nat(), "kind": named(DEFERRAL_KIND, r.nat8(), "deferral kind"),
            "deferredAccountId": r.nat(), "targetAccountId": r.nat(), "journalId": r.nat(),
            "sourceMoveId": r.nat(), "amount": r.nat(), "firstDay": r.nat(), "months": r.nat()}


READERS.update({
    317: ("declareDeferral",  lambda r: {"facts": read_deferral_facts(r)}),
    318: ("cancelDeferral",   lambda r: {"companyId": r.nat(), "deferralId": r.nat(), "reason": r.text()}),
    319: ("openDeferralRun",  lambda r: {"companyId": r.nat(), "throughDay": r.nat()}),
    320: ("deferralRunSlice", lambda r: {"companyId": r.nat(), "runId": r.nat(), "limit": r.nat()}),
})

# ── currencies and rates (136 to 139), and the revaluation (321 and 322) ──────
#
# The currency and rate families are finance's, but it is the ledger that revalues under them, so
# they are read here and handed to the ledger beside the accounting families.


def read_currency_facts(r):
    """`CurrencyFacts`: companyId, code, name, symbol, exponent, rounding."""
    return {"companyId": r.nat(), "code": r.text(), "name": r.text(), "symbol": r.text(), "exponent": r.nat(), "rounding": r.nat()}


READERS.update({
    136: ("createCurrency",       lambda r: {"facts": read_currency_facts(r)}),
    137: ("amendCurrency",        lambda r: {"currencyId": r.nat(), "facts": read_currency_facts(r)}),
    138: ("retireCurrency",       lambda r: {"companyId": r.nat(), "currencyId": r.nat(), "reason": r.text()}),
    139: ("recordRate",           lambda r: {"facts": {"companyId": r.nat(), "code": r.text(), "effectiveDay": r.nat(), "rate": r.nat()}}),
    321: ("setRevaluationPolicy", lambda r: {"facts": {"companyId": r.nat(), "functionalCurrency": r.text(), "gainAccountId": r.nat(), "lossAccountId": r.nat()}}),
    322: ("revalueCloseSlice",    lambda r: {"companyId": r.nat(), "runId": r.nat(), "limit": r.nat()}),
})

# ── the fixed assets (323 to 329) ─────────────────────────────────────────────


def read_asset_facts(r):
    """`AssetFacts`: companyId, name, the three accounts, journalId, sourceMoveId, cost, salvage, firstDay, months."""
    return {"companyId": r.nat(), "name": r.text(), "assetAccountId": r.nat(), "accumulatedAccountId": r.nat(), "expenseAccountId": r.nat(),
            "journalId": r.nat(), "sourceMoveId": r.nat(), "cost": r.nat(), "salvage": r.nat(), "firstDay": r.nat(), "months": r.nat()}


READERS.update({
    323: ("capitaliseAsset",      lambda r: {"facts": read_asset_facts(r)}),
    324: ("impairAsset",          lambda r: {"facts": {"companyId": r.nat(), "assetId": r.nat(), "day": r.nat(), "amount": r.nat(), "lossAccountId": r.nat(), "reason": r.text()}}),
    325: ("disposeAsset",         lambda r: {"facts": {"companyId": r.nat(), "assetId": r.nat(), "day": r.nat(), "proceeds": r.nat(), "proceedsAccountId": r.nat(),
                                                       "gainAccountId": r.nat(), "lossAccountId": r.nat(), "reason": r.text()}}),
    326: ("postAssetEvent",       lambda r: {"companyId": r.nat(), "eventId": r.nat()}),
    327: ("cancelAssetEvent",     lambda r: {"companyId": r.nat(), "eventId": r.nat(), "reason": r.text()}),
    328: ("openDepreciationRun",  lambda r: {"companyId": r.nat(), "throughDay": r.nat()}),
    329: ("depreciationRunSlice", lambda r: {"companyId": r.nat(), "runId": r.nat(), "limit": r.nat()}),
})

# ── the accounting payloads, written the other way ─────────────────────────────
#
# Re-encoders for the ten accounting families, so a block holding one can be decoded, re-encoded
# and required to be the bytes the contract hashed. `canonical.write_nat` and `write_text` are the
# primitives; the layout is the reader's, read backwards.

from canonical import write_nat, write_text  # noqa: E402


def _code_of(table, name, what):
    for b, n in table.items():
        if n == name:
            return b
    raise ValueError("unknown %s name %r" % (what, name))


def _bool(b):
    return b"\x01" if b else b"\x00"


def write_account_facts(f):
    return (write_nat(f["companyId"]) + write_text(f["code"]) + write_text(f["name"])
            + bytes([_code_of(ACCOUNT_TYPE, f["accountType"], "account type")])
            + write_nat(f["parentId"]) + _bool(f["reconcilable"]) + write_text(f["currency"]))


def write_journal_facts(f):
    return (write_nat(f["companyId"]) + write_text(f["code"]) + write_text(f["name"])
            + bytes([_code_of(JOURNAL_TYPE, f["journalType"], "journal type")])
            + write_nat(f["defaultAccountId"]))


def write_move_facts(f):
    out = bytearray()
    out += write_nat(f["companyId"]) + write_nat(f["journalId"]) + write_nat(f["businessDay"])
    out += bytes([_code_of(MOVE_TYPE, f["moveType"], "move type")])
    out += write_text(f["currency"]) + write_nat(f["partnerId"]) + write_text(f["ref"])
    out += len(f["lines"]).to_bytes(2, "big")
    for l in f["lines"]:
        out += (write_nat(l["accountId"]) + write_nat(l["partnerId"]) + write_text(l["name"])
                + write_nat(l["debit"]) + write_nat(l["credit"])
                + write_nat(l["amountCurrency"]) + write_nat(l["taxId"]))
    return bytes(out)


def _on_move(c):
    return write_nat(c["companyId"]) + write_nat(c["moveId"]) + write_text(c["reason"])


ACCOUNTING_ENCODERS = {
    "createAccount":    (38, lambda c: write_account_facts(c["facts"])),
    "amendAccount":     (39, lambda c: write_nat(c["accountId"]) + write_account_facts(c["facts"])),
    "deprecateAccount": (40, lambda c: write_nat(c["accountId"]) + write_text(c["reason"])),
    "createJournal":    (41, lambda c: write_journal_facts(c["facts"])),
    "amendJournal":     (42, lambda c: write_nat(c["journalId"]) + write_journal_facts(c["facts"])),
    "closeJournal":     (43, lambda c: write_nat(c["journalId"]) + write_text(c["reason"])),
    "proposeMove":      (44, lambda c: write_move_facts(c["facts"])),
    "postMove":         (45, _on_move),
    "cancelMove":       (46, _on_move),
    "lockPeriod":       (47, lambda c: write_nat(c["companyId"]) + write_nat(c["lockedThroughDay"])),
    "beginClose":        (308, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["fromDay"]) + write_nat(c["facts"]["throughDay"])
                                        + write_nat(c["facts"]["journalId"]) + write_nat(c["facts"]["retainedEarningsAccountId"])),
    "planCloseSlice":    (309, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_nat(c["limit"])),
    "cancelClose":       (310, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_text(c["reason"])),
    "closePeriod":       (311, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + _write_blob(c["planHash"])),
    "reopenClose":       (312, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_text(c["reason"])),
    "reverseCloseSlice": (313, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_nat(c["limit"])),
    "openStatement":     (314, lambda c: write_nat(c["facts"]["companyId"]) + bytes([_code_of(STATEMENT_KIND, c["facts"]["kind"], "statement kind")])
                                        + write_nat(c["facts"]["fromDay"]) + write_nat(c["facts"]["throughDay"])),
    "statementSlice":    (315, lambda c: write_nat(c["companyId"]) + write_nat(c["statementId"]) + write_nat(c["limit"])),
    "cancelStatement":   (316, lambda c: write_nat(c["companyId"]) + write_nat(c["statementId"]) + write_text(c["reason"])),
    "declareDeferral":   (317, lambda c: write_nat(c["facts"]["companyId"]) + bytes([_code_of(DEFERRAL_KIND, c["facts"]["kind"], "deferral kind")])
                                        + write_nat(c["facts"]["deferredAccountId"]) + write_nat(c["facts"]["targetAccountId"]) + write_nat(c["facts"]["journalId"])
                                        + write_nat(c["facts"]["sourceMoveId"]) + write_nat(c["facts"]["amount"]) + write_nat(c["facts"]["firstDay"]) + write_nat(c["facts"]["months"])),
    "cancelDeferral":    (318, lambda c: write_nat(c["companyId"]) + write_nat(c["deferralId"]) + write_text(c["reason"])),
    "openDeferralRun":   (319, lambda c: write_nat(c["companyId"]) + write_nat(c["throughDay"])),
    "deferralRunSlice":  (320, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_nat(c["limit"])),
    "createCurrency":    (136, lambda c: _write_currency(c["facts"])),
    "amendCurrency":     (137, lambda c: write_nat(c["currencyId"]) + _write_currency(c["facts"])),
    "retireCurrency":    (138, lambda c: write_nat(c["companyId"]) + write_nat(c["currencyId"]) + write_text(c["reason"])),
    "recordRate":        (139, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["code"]) + write_nat(c["facts"]["effectiveDay"]) + write_nat(c["facts"]["rate"])),
    "setRevaluationPolicy": (321, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["functionalCurrency"]) + write_nat(c["facts"]["gainAccountId"]) + write_nat(c["facts"]["lossAccountId"])),
    "revalueCloseSlice": (322, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_nat(c["limit"])),
    "capitaliseAsset":   (323, lambda c: _write_asset(c["facts"])),
    "impairAsset":       (324, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["assetId"]) + write_nat(c["facts"]["day"]) + write_nat(c["facts"]["amount"])
                                         + write_nat(c["facts"]["lossAccountId"]) + write_text(c["facts"]["reason"])),
    "disposeAsset":      (325, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["assetId"]) + write_nat(c["facts"]["day"]) + write_nat(c["facts"]["proceeds"])
                                         + write_nat(c["facts"]["proceedsAccountId"]) + write_nat(c["facts"]["gainAccountId"]) + write_nat(c["facts"]["lossAccountId"]) + write_text(c["facts"]["reason"])),
    "postAssetEvent":    (326, lambda c: write_nat(c["companyId"]) + write_nat(c["eventId"])),
    "cancelAssetEvent":  (327, lambda c: write_nat(c["companyId"]) + write_nat(c["eventId"]) + write_text(c["reason"])),
    "openDepreciationRun": (328, lambda c: write_nat(c["companyId"]) + write_nat(c["throughDay"])),
    "depreciationRunSlice": (329, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_nat(c["limit"])),
}


def _write_asset(f):
    return (write_nat(f["companyId"]) + write_text(f["name"]) + write_nat(f["assetAccountId"]) + write_nat(f["accumulatedAccountId"])
            + write_nat(f["expenseAccountId"]) + write_nat(f["journalId"]) + write_nat(f["sourceMoveId"]) + write_nat(f["cost"])
            + write_nat(f["salvage"]) + write_nat(f["firstDay"]) + write_nat(f["months"]))


def _write_currency(f):
    return (write_nat(f["companyId"]) + write_text(f["code"]) + write_text(f["name"]) + write_text(f["symbol"])
            + write_nat(f["exponent"]) + write_nat(f["rounding"]))


def _write_blob(b):
    """A length-prefixed blob, as the canonical writer puts it: two bytes big-endian then the bytes."""
    return len(b).to_bytes(2, "big") + bytes(b)


def _put_tag(tag):
    """The family tag as `Encoding.putTag` writes it: one byte below 255; 0xFF then the offset past
    255 up to 509; 0xFF 0xFF then two bytes of the offset past 510 above that."""
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def accounting_command_bytes(cmd):
    tag, fn = ACCOUNTING_ENCODERS[cmd["family"]]
    return _put_tag(tag) + fn(cmd)


OVERTIME_CATEGORY = {1: "regular", 2: "weekend", 3: "holiday", 4: "emergencyCallIn"}
OVERTIME_PAYOUT = {1: "cash", 2: "compTime"}


def read_overtime_facts(r):
    return {"companyId": r.nat(), "businessDay": r.nat(), "minutes": r.nat(),
            "category": named(OVERTIME_CATEGORY, r.nat8(), "overtime category"),
            "payout": named(OVERTIME_PAYOUT, r.nat8(), "overtime payout"),
            "description": r.text()}


def read_premium_facts(r):
    return {"profileId": r.nat(), "regular": r.nat(), "weekend": r.nat(),
            "holiday": r.nat(), "callIn": r.nat()}


# The overtime path. An overtime line on a payslip now exists only because somebody claimed the
# minutes and somebody ELSE approved them at a premium the statutory profile declares, so the
# payroll oracle has to read those blocks to recompute a payslip at all.
READERS.update({
    214: ("claimOvertime",           lambda r: {"facts": read_overtime_facts(r)}),
    215: ("submitOvertime",          lambda r: {"companyId": r.nat(), "overtimeId": r.nat()}),
    216: ("cancelOvertime",          lambda r: {"companyId": r.nat(), "overtimeId": r.nat()}),
    217: ("decideOvertime",          lambda r: {"companyId": r.nat(), "overtimeId": r.nat(),
                                                "approve": r.bool(), "note": r.text()}),
    239: ("declareOvertimePremiums", lambda r: {"facts": read_premium_facts(r)}),
})

PAYROLL_FAMILIES = ({name for tag, (name, _fn) in READERS.items() if 28 <= tag <= 37}
                    | {name for tag, (name, _fn) in READERS.items() if 214 <= tag <= 239})
ACCOUNTING_FAMILIES = {name for tag, (name, _fn) in READERS.items() if 38 <= tag <= 47 or 136 <= tag <= 139 or 308 <= tag <= 329}


def read_hr_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


# ── the two computed answers ────────────────────────────────────────────────────

class Hr:
    """Leave balances and attendance days, recomputed from the log.

    Nothing here reads a row the contract wrote. A refusal the contract made is a command that is
    NOT on the log, so any command found here should apply - and a rule that refuses one is a
    disagreement worth reporting, not a line to skip.
    """

    def __init__(self):
        self.members = set()          # (company, subject)
        self.suspended = set()
        self.balances = {}            # (company, subject, leaveType) -> dict
        self.requests = {}            # request id -> dict
        self.next_request = 1
        self.punches = {}             # punch id -> dict
        self.next_punch = 1
        self.open = {}                # (company, subject) -> punch id
        self.corrections = {}         # correction id -> dict
        self.next_correction = 1
        self.faults = []

    # -- helpers --

    def bal(self, key):
        return self.balances.setdefault(key, {"accrued": 0, "taken": 0, "adjusted": 0})

    def remaining(self, company, subject, t):
        b = self.balances.get((company, subject, t))
        return 0 if b is None else b["accrued"] + b["adjusted"] - b["taken"]

    def punches_on_day(self, company, subject, day):
        return sum(1 for p in self.punches.values()
                   if p["companyId"] == company and p["subject"] == subject and p["day"] == day)

    # -- the fold --

    def apply(self, block):
        c = block["command"]
        f = c["family"]
        day = block["day"]
        caller = block["caller"]

        if f == "admitMember":
            key = (c["companyId"], c["subject"])
            if key in self.members:
                self.faults.append("block %d admitted an existing member" % block["index"])
            self.members.add(key)
        elif f == "suspendMember":
            self.suspended.add((c["companyId"], c["subject"]))
        elif f == "reinstateMember":
            self.suspended.discard((c["companyId"], c["subject"]))

        elif f == "punchIn":
            key = (c["companyId"], c["subject"])
            if key in self.open:
                self.faults.append("block %d opened a second punch for a person who already has one"
                                   % block["index"])
            pid = self.next_punch
            self.next_punch += 1
            self.punches[pid] = {
                "companyId": c["companyId"], "subject": c["subject"], "day": day,
                "seq": self.punches_on_day(c["companyId"], c["subject"], day) + 1,
                "inMinute": block["index"] % MINUTES_IN_DAY, "outMinute": None,
                "source": c["source"], "correctedFrom": None,
            }
            self.open[key] = pid

        elif f == "punchOut":
            key = (c["companyId"], c["subject"])
            pid = self.open.pop(key, None)
            if pid is None:
                self.faults.append("block %d closed a punch that was not open" % block["index"])
            else:
                self.punches[pid]["outMinute"] = block["index"] % MINUTES_IN_DAY

        elif f == "requestPunchCorrection":
            cid = self.next_correction
            self.next_correction += 1
            self.corrections[cid] = {**c, "state": "Pending"}

        elif f == "decidePunchCorrection":
            k = self.corrections.get(c["correctionId"])
            if k is None:
                self.faults.append("block %d decided a correction that does not exist" % block["index"])
            elif k["state"] != "Pending":
                self.faults.append("block %d decided a correction twice" % block["index"])
            elif k["subject"] == caller:
                self.faults.append("block %d let a person decide their own correction" % block["index"])
            else:
                k["state"] = "Approved" if c["approve"] else "Rejected"
                if c["approve"]:
                    original = self.punches.get(k["punchId"])
                    if original is None:
                        self.faults.append("block %d corrected a punch that does not exist" % block["index"])
                    else:
                        pid = self.next_punch
                        self.next_punch += 1
                        self.punches[pid] = {
                            **original,
                            "seq": self.punches_on_day(original["companyId"], original["subject"], original["day"]) + 1,
                            "inMinute": k["inMinute"], "outMinute": k["outMinute"],
                            "source": "correction", "correctedFrom": k["punchId"],
                        }
                        self.open.pop((original["companyId"], original["subject"]), None)

        elif f == "requestLeave":
            rid = self.next_request
            self.next_request += 1
            self.requests[rid] = {**c, "state": "Pending"}

        elif f == "decideLeave":
            l = self.requests.get(c["requestId"])
            if l is None:
                self.faults.append("block %d decided a leave request that does not exist" % block["index"])
            elif l["state"] != "Pending":
                self.faults.append("block %d decided a leave request twice" % block["index"])
            elif l["subject"] == caller:
                self.faults.append("block %d let a person approve their own leave" % block["index"])
            else:
                l["state"] = "Approved" if c["approve"] else "Rejected"
                if c["approve"]:
                    self.bal((l["companyId"], l["subject"], l["leaveType"]))["taken"] += l["quantity"]

        elif f == "withdrawLeave":
            l = self.requests.get(c["requestId"])
            if l is None or l["state"] != "Pending":
                self.faults.append("block %d withdrew a request that was not pending" % block["index"])
            else:
                l["state"] = "Withdrawn"

        elif f == "adjustLeaveBalance":
            key = (c["companyId"], c["subject"], c["leaveType"])
            have = self.remaining(*key)
            if have + c["delta"] < 0:
                self.faults.append("block %d adjusted a balance below zero" % block["index"])
            self.bal(key)["adjusted"] += c["delta"]

        elif f == "accrueLeave":
            for s in c["subjects"]:
                if (c["companyId"], s) not in self.members:
                    self.faults.append("block %d accrued for someone who is not a member" % block["index"])
            for s in c["subjects"]:
                self.bal((c["companyId"], s, c["leaveType"]))["accrued"] += c["quantity"]

    # -- what it arrived at --

    def summary(self):
        open_punches = len(self.open)
        paired = sum(1 for p in self.punches.values() if p["outMinute"] is not None)
        corrected = sum(1 for p in self.punches.values() if p["correctedFrom"] is not None)
        return {
            "members": len(self.members),
            "balances": len(self.balances),
            "requests": len(self.requests),
            "approved": sum(1 for l in self.requests.values() if l["state"] == "Approved"),
            "punches": len(self.punches),
            "paired_punches": paired,
            "open_punches": open_punches,
            "corrected_punches": corrected,
            "faults": len(self.faults),
        }
