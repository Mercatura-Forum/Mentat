"""The compensation and benefits families (508 to 536), decoded from their canonical bytes, re-encoded so the command
hash can be re-derived, and folded by rules written from the design:

  * a PAY BAND is one per grade, minimum, midpoint, maximum in order; a SALARY REVIEW is THE MANAGER'S PROPOSAL
    within the band, DECIDED BY A SECOND PERSON and IMPLEMENTED by somebody who is not the subject once its day has
    come, the new base written onto the payroll - this reader writes it onto its own payroll twin and recomputes
    every compa-ratio;
  * an EQUITY GRANT vests by A SCHEDULE THE FOLD COMPUTES from the civil months elapsed - this reader computes the
    schedule itself with Python's own calendar, at every vesting and on the day the contract names;
  * an INCENTIVE SCORE's FINAL FIGURE AND AMOUNT ARE THE FOLD'S - this reader recomputes both from the weights and
    the scores on the block and the base on its own payroll twin;
  * a PAYMENT OUTSIDE THE RUN is created by somebody who is not the payee with THE NET THE FOLD'S, approved by a
    third person and POSTED THROUGH THE LEDGER - this reader posts it through its own ledger;
  * a LOAN is the borrower's own request, decided by a second person, DISBURSED by a third THROUGH THE LEDGER, ITS
    INSTALMENTS THE FOLD'S ARITHMETIC, repaid by somebody else never past what is owed - this reader recomputes every
    schedule and what is owed from the repayments it folded;
  * a BENEFIT ENROLMENT is the employee's own WHILE A PERIOD IS OPEN ON THE CALENDAR'S DAY - this reader reads every
    period against the calendar and re-adds every employee's monthly cost over the enrolments that stand.

The employee table is the appraisal reader's, kept from the HR families; the ledger is the accounting reader's; the
payroll is the payroll reader's.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import datetime

from canonical import write_nat, write_text

MAX_DAY = 2 ** 24
MAX_MONEY = 2 ** 64
MAX_QTY = 2 ** 48
GRADE_MAX = 10
MAX_VESTING_MONTHS = 120
MAX_INCENTIVE_BPS = 20_000
MAX_METRICS = 8
WEIGHTS_WHOLE = 10_000
SCORE_MAX = 10_000
LOAN_MONTHS = 12
EPOCH_ORDINAL = datetime.date(1970, 1, 1).toordinal()

SCHEDULES = {1: "cliff", 2: "monthly", 3: "quarterly", 4: "annual"}
PERIOD_MONTHS = {"cliff": 0, "monthly": 1, "quarterly": 3, "annual": 12}
GRANT_KINDS = {1: "rsu", 2: "iso", 3: "nso", 4: "espp", 5: "sar"}
OFFCYCLE_KINDS = {1: "bonus", 2: "commission", 3: "correction", 4: "reimbursement"}
LOAN_KINDS = {1: "salary-advance", 2: "emergency", 3: "medical", 4: "training", 5: "other"}
LOAN_SCHEDULES = {1: "lump-sum", 2: "two", 3: "three", 4: "six", 5: "twelve"}
LOAN_INSTALMENTS = {"lump-sum": 1, "two": 2, "three": 3, "six": 6, "twelve": 12}
BENEFIT_CATEGORIES = {1: "health", 2: "dental", 3: "vision", 4: "retirement", 5: "life", 6: "disability", 7: "wellness", 8: "other"}
TIERS = {1: "employee", 2: "employee-spouse", 3: "employee-children", 4: "family"}
TIER_BITS = {1: 1, 2: 2, 3: 4, 4: 8}


def _bool(b):
    return b"\x01" if b else b"\x00"


def write_principal(p):
    return bytes([len(p)]) + bytes(p)


def _nats(ns):
    return len(ns).to_bytes(2, "big") + b"".join(write_nat(n) for n in ns)


def _read_nats(r):
    return [r.nat() for _ in range(r.len16())]


def _read_metrics(r):
    return [{"key": r.text(), "weightBps": r.nat()} for _ in range(r.len16())]


def _read_tiers(r):
    return [r.nat8() for _ in range(r.len16())]


READERS = {
    508: ("setCompensationPolicy", lambda r: {"facts": {"companyId": r.nat(), "journalId": r.nat(), "salaryExpenseAccountId": r.nat(), "deductionsAccountId": r.nat(),
                                                         "employeePayableAccountId": r.nat(), "loanReceivableAccountId": r.nat()}}),
    509: ("declarePayBand", lambda r: {"facts": {"companyId": r.nat(), "name": r.text(), "grade": r.nat(), "currency": r.text(), "minAmount": r.nat(), "midAmount": r.nat(), "maxAmount": r.nat()}}),
    510: ("amendPayBand", lambda r: {"facts": {"companyId": r.nat(), "bandId": r.nat(), "minAmount": r.nat(), "midAmount": r.nat(), "maxAmount": r.nat()}}),
    511: ("retirePayBand", lambda r: {"companyId": r.nat(), "bandId": r.nat()}),
    512: ("proposeSalaryReview", lambda r: {"facts": {"companyId": r.nat(), "subject": r.principal(), "bandId": r.nat(), "proposedBase": r.nat(), "effectiveDay": r.nat(), "justification": r.text()}}),
    513: ("decideSalaryReview", lambda r: {"companyId": r.nat(), "reviewId": r.nat(), "approve": r.bool(), "note": r.text()}),
    514: ("implementSalaryReview", lambda r: {"companyId": r.nat(), "reviewId": r.nat()}),
    515: ("withdrawSalaryReview", lambda r: {"companyId": r.nat(), "reviewId": r.nat()}),
    516: ("grantEquity", lambda r: {"facts": {"companyId": r.nat(), "subject": r.principal(), "kind": r.nat8(), "totalShares": r.nat(), "strikePrice": r.nat(), "currency": r.text(),
                                               "vestingStartDay": r.nat(), "cliffMonths": r.nat(), "vestingMonths": r.nat(), "schedule": r.nat8()}}),
    517: ("vestEquity", lambda r: {"companyId": r.nat(), "grantId": r.nat()}),
    518: ("exerciseEquity", lambda r: {"companyId": r.nat(), "grantId": r.nat(), "shares": r.nat()}),
    519: ("cancelEquityGrant", lambda r: {"companyId": r.nat(), "grantId": r.nat(), "reason": r.text()}),
    520: ("createIncentivePlan", lambda r: {"facts": {"companyId": r.nat(), "name": r.text(), "maxBps": r.nat(), "metrics": _read_metrics(r)}}),
    521: ("retireIncentivePlan", lambda r: {"companyId": r.nat(), "planId": r.nat()}),
    522: ("scoreIncentive", lambda r: {"facts": {"companyId": r.nat(), "planId": r.nat(), "subject": r.principal(), "periodDay": r.nat(), "scores": _read_nats(r), "note": r.text()}}),
    523: ("createOffCyclePayment", lambda r: {"facts": {"companyId": r.nat(), "subject": r.principal(), "kind": r.nat8(), "title": r.text(), "periodDay": r.nat(), "gross": r.nat(), "deductions": r.nat(), "scoreId": r.nat()}}),
    524: ("approveOffCyclePayment", lambda r: {"companyId": r.nat(), "paymentId": r.nat()}),
    525: ("rejectOffCyclePayment", lambda r: {"companyId": r.nat(), "paymentId": r.nat(), "reason": r.text()}),
    526: ("cancelOffCyclePayment", lambda r: {"companyId": r.nat(), "paymentId": r.nat()}),
    527: ("requestLoan", lambda r: {"facts": {"companyId": r.nat(), "kind": r.nat8(), "amount": r.nat(), "schedule": r.nat8(), "justification": r.text()}}),
    528: ("withdrawLoan", lambda r: {"companyId": r.nat(), "loanId": r.nat()}),
    529: ("decideLoan", lambda r: {"companyId": r.nat(), "loanId": r.nat(), "approve": r.bool(), "approvedAmount": r.nat(), "note": r.text()}),
    530: ("disburseLoan", lambda r: {"companyId": r.nat(), "loanId": r.nat(), "cashAccountId": r.nat()}),
    531: ("recordLoanRepayment", lambda r: {"facts": {"companyId": r.nat(), "loanId": r.nat(), "amount": r.nat(), "cashAccountId": r.nat(), "note": r.text()}}),
    532: ("createBenefitPlan", lambda r: {"facts": {"companyId": r.nat(), "name": r.text(), "category": r.nat8(), "provider": r.text(), "employeeCost": r.nat(), "employerCost": r.nat(), "tiers": _read_tiers(r)}}),
    533: ("toggleBenefitPlan", lambda r: {"companyId": r.nat(), "planId": r.nat(), "isActive": r.bool()}),
    534: ("openEnrolmentPeriod", lambda r: {"facts": {"companyId": r.nat(), "name": r.text(), "startDay": r.nat(), "endDay": r.nat()}}),
    535: ("enrolInBenefit", lambda r: {"facts": {"companyId": r.nat(), "planId": r.nat(), "tier": r.nat8()}}),
    536: ("waiveBenefit", lambda r: {"companyId": r.nat(), "planId": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_compensation_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def _metrics(ms):
    return len(ms).to_bytes(2, "big") + b"".join(write_text(m["key"]) + write_nat(m["weightBps"]) for m in ms)


def _tiers(ts):
    return len(ts).to_bytes(2, "big") + bytes(ts)


ENCODERS = {
    "setCompensationPolicy": (508, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["journalId"]) + write_nat(c["facts"]["salaryExpenseAccountId"]) + write_nat(c["facts"]["deductionsAccountId"])
                              + write_nat(c["facts"]["employeePayableAccountId"]) + write_nat(c["facts"]["loanReceivableAccountId"])),
    "declarePayBand": (509, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["name"]) + write_nat(c["facts"]["grade"]) + write_text(c["facts"]["currency"])
                       + write_nat(c["facts"]["minAmount"]) + write_nat(c["facts"]["midAmount"]) + write_nat(c["facts"]["maxAmount"])),
    "amendPayBand": (510, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["bandId"]) + write_nat(c["facts"]["minAmount"]) + write_nat(c["facts"]["midAmount"]) + write_nat(c["facts"]["maxAmount"])),
    "retirePayBand": (511, lambda c: write_nat(c["companyId"]) + write_nat(c["bandId"])),
    "proposeSalaryReview": (512, lambda c: write_nat(c["facts"]["companyId"]) + write_principal(c["facts"]["subject"]) + write_nat(c["facts"]["bandId"]) + write_nat(c["facts"]["proposedBase"])
                            + write_nat(c["facts"]["effectiveDay"]) + write_text(c["facts"]["justification"])),
    "decideSalaryReview": (513, lambda c: write_nat(c["companyId"]) + write_nat(c["reviewId"]) + _bool(c["approve"]) + write_text(c["note"])),
    "implementSalaryReview": (514, lambda c: write_nat(c["companyId"]) + write_nat(c["reviewId"])),
    "withdrawSalaryReview": (515, lambda c: write_nat(c["companyId"]) + write_nat(c["reviewId"])),
    "grantEquity": (516, lambda c: write_nat(c["facts"]["companyId"]) + write_principal(c["facts"]["subject"]) + bytes([c["facts"]["kind"]]) + write_nat(c["facts"]["totalShares"]) + write_nat(c["facts"]["strikePrice"])
                    + write_text(c["facts"]["currency"]) + write_nat(c["facts"]["vestingStartDay"]) + write_nat(c["facts"]["cliffMonths"]) + write_nat(c["facts"]["vestingMonths"]) + bytes([c["facts"]["schedule"]])),
    "vestEquity": (517, lambda c: write_nat(c["companyId"]) + write_nat(c["grantId"])),
    "exerciseEquity": (518, lambda c: write_nat(c["companyId"]) + write_nat(c["grantId"]) + write_nat(c["shares"])),
    "cancelEquityGrant": (519, lambda c: write_nat(c["companyId"]) + write_nat(c["grantId"]) + write_text(c["reason"])),
    "createIncentivePlan": (520, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["name"]) + write_nat(c["facts"]["maxBps"]) + _metrics(c["facts"]["metrics"])),
    "retireIncentivePlan": (521, lambda c: write_nat(c["companyId"]) + write_nat(c["planId"])),
    "scoreIncentive": (522, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["planId"]) + write_principal(c["facts"]["subject"]) + write_nat(c["facts"]["periodDay"]) + _nats(c["facts"]["scores"]) + write_text(c["facts"]["note"])),
    "createOffCyclePayment": (523, lambda c: write_nat(c["facts"]["companyId"]) + write_principal(c["facts"]["subject"]) + bytes([c["facts"]["kind"]]) + write_text(c["facts"]["title"]) + write_nat(c["facts"]["periodDay"])
                              + write_nat(c["facts"]["gross"]) + write_nat(c["facts"]["deductions"]) + write_nat(c["facts"]["scoreId"])),
    "approveOffCyclePayment": (524, lambda c: write_nat(c["companyId"]) + write_nat(c["paymentId"])),
    "rejectOffCyclePayment": (525, lambda c: write_nat(c["companyId"]) + write_nat(c["paymentId"]) + write_text(c["reason"])),
    "cancelOffCyclePayment": (526, lambda c: write_nat(c["companyId"]) + write_nat(c["paymentId"])),
    "requestLoan": (527, lambda c: write_nat(c["facts"]["companyId"]) + bytes([c["facts"]["kind"]]) + write_nat(c["facts"]["amount"]) + bytes([c["facts"]["schedule"]]) + write_text(c["facts"]["justification"])),
    "withdrawLoan": (528, lambda c: write_nat(c["companyId"]) + write_nat(c["loanId"])),
    "decideLoan": (529, lambda c: write_nat(c["companyId"]) + write_nat(c["loanId"]) + _bool(c["approve"]) + write_nat(c["approvedAmount"]) + write_text(c["note"])),
    "disburseLoan": (530, lambda c: write_nat(c["companyId"]) + write_nat(c["loanId"]) + write_nat(c["cashAccountId"])),
    "recordLoanRepayment": (531, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["loanId"]) + write_nat(c["facts"]["amount"]) + write_nat(c["facts"]["cashAccountId"]) + write_text(c["facts"]["note"])),
    "createBenefitPlan": (532, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["name"]) + bytes([c["facts"]["category"]]) + write_text(c["facts"]["provider"]) + write_nat(c["facts"]["employeeCost"])
                          + write_nat(c["facts"]["employerCost"]) + _tiers(c["facts"]["tiers"])),
    "toggleBenefitPlan": (533, lambda c: write_nat(c["companyId"]) + write_nat(c["planId"]) + _bool(c["isActive"])),
    "openEnrolmentPeriod": (534, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["name"]) + write_nat(c["facts"]["startDay"]) + write_nat(c["facts"]["endDay"])),
    "enrolInBenefit": (535, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["planId"]) + bytes([c["facts"]["tier"]])),
    "waiveBenefit": (536, lambda c: write_nat(c["companyId"]) + write_nat(c["planId"])),
}


def compensation_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


# ── the arithmetic, written again in Python ───────────────────────────────────

def civil(day):
    return datetime.date.fromordinal(day + EPOCH_ORDINAL)


def months_between(from_day, to_day):
    """Whole civil months from one day to another; none when the second is not after the first."""
    if to_day < from_day:
        return 0
    a, b = civil(from_day), civil(to_day)
    whole = (b.year * 12 + b.month) - (a.year * 12 + a.month)
    if b.day < a.day:
        whole -= 1
    return max(whole, 0)


def vested_on(g, day):
    """THE SCHEDULE: nothing before the cliff; a cliff schedule everything once the vesting months have passed;
    otherwise the tranches due, the total shared among them with the remainder on the last."""
    if g["state"] == "cancelled":
        return g["vestedShares"]
    elapsed = months_between(g["vestingStartDay"], day)
    if elapsed < g["cliffMonths"]:
        return 0
    if g["schedule"] == "cliff":
        return g["totalShares"] if elapsed >= g["vestingMonths"] else 0
    period = PERIOD_MONTHS[g["schedule"]]
    tranches = g["vestingMonths"] // period
    due = min(tranches, elapsed // period)
    return g["totalShares"] if due == tranches else g["totalShares"] * due // tranches


def final_bps(weights, scores, max_bps):
    return sum(w * s for w, s in zip(weights, scores)) * max_bps // (WEIGHTS_WHOLE * SCORE_MAX)


def instalments(schedule, amount):
    n = LOAN_INSTALMENTS[schedule]
    each = amount // n
    return [each] * (n - 1) + [amount - each * (n - 1)]


def compa_ratio(base, mid):
    return 0 if mid == 0 else base * 1000 // mid


class Compensation:
    def __init__(self):
        self.policies = {}        # companyId -> policy
        self.bands = {}
        self.reviews = {}
        self.grants = {}
        self.plans = {}
        self.metrics = {}         # planId -> [metric]
        self.scores = {}
        self.payments = {}
        self.loans = {}
        self.repayments = {}
        self.benefit_plans = {}
        self.periods = {}
        self.enrolments = {}
        self.next_band = 1
        self.next_review = 1
        self.next_grant = 1
        self.next_plan = 1
        self.next_score = 1
        self.next_payment = 1
        self.next_loan = 1
        self.next_repayment = 1
        self.next_benefit_plan = 1
        self.next_period = 1
        self.next_enrolment = 1
        self.vesting_recomputed = 0
        self.finals_recomputed = 0
        self.schedules_recomputed = 0
        self.costs_readded = 0
        self.periods_read = 0
        self.faults = []

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = bytes(block["caller"])
        hr = store.hr
        people = store.appraisals
        ledger = store.ledger
        pay = store.pay

        def member(co, p=None):
            return co in store.companies and (co, p if p is not None else caller) in hr.members

        def base_of(co, p):
            comp = pay.comp.get((co, bytes(p)))
            return None if comp is None else comp["baseMonthly"]

        def live_account(co, aid):
            a = ledger.accounts.get(aid)
            return a if a is not None and a["companyId"] == co and not a["deprecated"] else None

        def post(co, policy, proposer, lines, ref, kind):
            if day <= ledger.locks.get(co, 0):
                self.faults.append("block %d %s into a locked period" % (idx, kind))
            cur = ledger.accounts[lines[0]["accountId"]]["currency"]
            return ledger._generated({"companyId": co, "journalId": policy["journalId"], "businessDay": day, "moveType": "entry", "currency": cur, "partnerId": 0, "ref": ref, "lines": lines},
                                     proposer, caller, idx)

        if f == "setCompensationPolicy":
            fc = c["facts"]
            co = fc["companyId"]
            j = ledger.journals.get(fc["journalId"])
            exp, ded, payb, recv = (live_account(co, fc[k]) for k in ("salaryExpenseAccountId", "deductionsAccountId", "employeePayableAccountId", "loanReceivableAccountId"))
            ok = member(co) and j is not None and j["companyId"] == co and j["isActive"] \
                and exp is not None and exp["accountType"] == "expense" and ded is not None and ded["accountType"] in ("liability", "payable") \
                and payb is not None and payb["accountType"] in ("payable", "liability") and recv is not None and recv["accountType"] in ("receivable", "asset")
            if not ok:
                self.faults.append("block %d set a compensation policy it could not" % idx)
                return
            self.policies[co] = dict(fc)
            return

        if f == "declarePayBand":
            fc = c["facts"]
            co = fc["companyId"]
            order = 0 < fc["minAmount"] <= fc["midAmount"] <= fc["maxAmount"] < MAX_MONEY
            if not member(co) or not fc["name"] or not 1 <= fc["grade"] <= GRADE_MAX or len(fc["currency"].encode()) > 4 or not order:
                self.faults.append("block %d declared a pay band it could not" % idx)
                return
            same = [(i, b) for i, b in self.bands.items() if b["companyId"] == co and b["grade"] == fc["grade"]]
            if same:
                i, b = same[0]
                if b["isActive"]:
                    self.faults.append("block %d DECLARED A GRADE TWICE" % idx)
                    return
                b.update(minAmount=fc["minAmount"], midAmount=fc["midAmount"], maxAmount=fc["maxAmount"], isActive=True)
                return
            self.bands[self.next_band] = {"companyId": co, "grade": fc["grade"], "minAmount": fc["minAmount"], "midAmount": fc["midAmount"], "maxAmount": fc["maxAmount"], "isActive": True}
            self.next_band += 1
            return

        def active_band(co, bid):
            b = self.bands.get(bid)
            return b if b is not None and b["companyId"] == co and b["isActive"] else None

        if f == "amendPayBand":
            fc = c["facts"]
            b = active_band(fc["companyId"], fc["bandId"])
            if not member(fc["companyId"]) or b is None or not 0 < fc["minAmount"] <= fc["midAmount"] <= fc["maxAmount"] < MAX_MONEY:
                self.faults.append("block %d amended a pay band it could not" % idx)
                return
            b.update(minAmount=fc["minAmount"], midAmount=fc["midAmount"], maxAmount=fc["maxAmount"])
            return

        if f == "retirePayBand":
            b = active_band(c["companyId"], c["bandId"])
            if not member(c["companyId"]) or b is None:
                self.faults.append("block %d retired a pay band it could not" % idx)
                return
            b["isActive"] = False
            return

        if f == "proposeSalaryReview":
            fc = c["facts"]
            co = fc["companyId"]
            eid, e = people.employee_of(co, fc["subject"])
            mid_id, _m = people.employee_of(co, caller)
            is_manager = eid is not None and mid_id is not None and e["managerId"] != 0 and mid_id == e["managerId"]
            current = base_of(co, fc["subject"])
            band = active_band(co, fc["bandId"])
            ok = member(co) and eid is not None and e["isActive"] and is_manager and current is not None and band is not None \
                and band["minAmount"] <= fc["proposedBase"] <= band["maxAmount"] and fc["proposedBase"] != current \
                and fc["effectiveDay"] < MAX_DAY and fc["effectiveDay"] >= day and fc["justification"] \
                and not any(r["employeeId"] == eid and r["state"] in ("proposed", "approved") for r in self.reviews.values())
            if not ok:
                self.faults.append("block %d PROPOSED A SALARY REVIEW IT COULD NOT" % idx)
                return
            self.reviews[self.next_review] = {"companyId": co, "employeeId": eid, "subject": bytes(fc["subject"]), "bandId": fc["bandId"], "currentBase": current, "proposedBase": fc["proposedBase"],
                                              "effectiveDay": fc["effectiveDay"], "state": "proposed", "proposedBy": caller, "decidedBy": caller}
            self.next_review += 1
            return

        def review_of(co, rid):
            r = self.reviews.get(rid)
            return r if r is not None and r["companyId"] == co and member(co) else None

        if f == "decideSalaryReview":
            r = review_of(c["companyId"], c["reviewId"])
            if r is None or r["state"] != "proposed" or caller == r["subject"] or caller == r["proposedBy"] or (not c["approve"] and not c["note"]):
                self.faults.append("block %d DECIDED A SALARY REVIEW IT COULD NOT" % idx)
                return
            r["state"] = "approved" if c["approve"] else "rejected"
            r["decidedBy"] = caller
            return

        if f == "implementSalaryReview":
            r = review_of(c["companyId"], c["reviewId"])
            comp = pay.comp.get((c["companyId"], r["subject"])) if r is not None else None
            if r is None or r["state"] != "approved" or caller == r["subject"] or day < r["effectiveDay"] or comp is None:
                self.faults.append("block %d IMPLEMENTED A SALARY REVIEW IT COULD NOT" % idx)
                return
            # THE NEW BASE WRITTEN ONTO THE PAYROLL - this reader's own payroll twin
            comp["baseMonthly"] = r["proposedBase"]
            comp["effectiveDay"] = r["effectiveDay"]
            r["state"] = "implemented"
            return

        if f == "withdrawSalaryReview":
            r = review_of(c["companyId"], c["reviewId"])
            if r is None or r["state"] != "proposed" or caller != r["proposedBy"]:
                self.faults.append("block %d withdrew a salary review it could not" % idx)
                return
            r["state"] = "withdrawn"
            return

        if f == "grantEquity":
            fc = c["facts"]
            co = fc["companyId"]
            eid, e = people.employee_of(co, fc["subject"])
            sched = SCHEDULES.get(fc["schedule"])
            ok = member(co) and eid is not None and e["isActive"] and caller != bytes(fc["subject"]) and 0 < fc["totalShares"] < MAX_QTY and fc["strikePrice"] < MAX_MONEY \
                and len(fc["currency"].encode()) <= 4 and fc["vestingStartDay"] < MAX_DAY and 1 <= fc["vestingMonths"] <= MAX_VESTING_MONTHS and fc["cliffMonths"] <= fc["vestingMonths"] \
                and sched is not None and fc["kind"] in GRANT_KINDS
            if ok and sched == "cliff":
                ok = fc["cliffMonths"] == fc["vestingMonths"]
            elif ok:
                ok = fc["vestingMonths"] % PERIOD_MONTHS[sched] == 0
            if not ok:
                self.faults.append("block %d GRANTED EQUITY IT COULD NOT" % idx)
                return
            self.grants[self.next_grant] = {"companyId": co, "employeeId": eid, "subject": bytes(fc["subject"]), "kind": GRANT_KINDS[fc["kind"]], "totalShares": fc["totalShares"],
                                            "vestingStartDay": fc["vestingStartDay"], "cliffMonths": fc["cliffMonths"], "vestingMonths": fc["vestingMonths"], "schedule": sched,
                                            "vestedShares": 0, "exercisedShares": 0, "state": "active"}
            self.next_grant += 1
            return

        def active_grant(co, gid):
            g = self.grants.get(gid)
            return g if g is not None and g["companyId"] == co and member(co) and g["state"] == "active" else None

        if f == "vestEquity":
            g = active_grant(c["companyId"], c["grantId"])
            if g is None:
                self.faults.append("block %d vested a grant it could not" % idx)
                return
            self.vesting_recomputed += 1
            v = vested_on(g, day)
            if v <= g["vestedShares"]:
                self.faults.append("block %d VESTED WHAT THE SCHEDULE DOES NOT GIVE" % idx)
                return
            g["vestedShares"] = v
            return

        if f == "exerciseEquity":
            g = active_grant(c["companyId"], c["grantId"])
            if g is None or caller != g["subject"] or c["shares"] == 0 or c["shares"] > g["vestedShares"] - g["exercisedShares"]:
                self.faults.append("block %d EXERCISED WHAT IT COULD NOT" % idx)
                return
            g["exercisedShares"] += c["shares"]
            if g["exercisedShares"] == g["totalShares"]:
                g["state"] = "exercised"
            return

        if f == "cancelEquityGrant":
            g = active_grant(c["companyId"], c["grantId"])
            if g is None or caller == g["subject"] or not c["reason"]:
                self.faults.append("block %d cancelled a grant it could not" % idx)
                return
            self.vesting_recomputed += 1
            g["vestedShares"] = max(g["vestedShares"], vested_on(g, day))
            g["state"] = "cancelled"
            return

        if f == "createIncentivePlan":
            fc = c["facts"]
            co = fc["companyId"]
            keys = [m["key"] for m in fc["metrics"]]
            ok = member(co) and fc["name"] and 1 <= fc["maxBps"] <= MAX_INCENTIVE_BPS and 1 <= len(keys) <= MAX_METRICS and all(keys) and len(set(keys)) == len(keys) \
                and sum(m["weightBps"] for m in fc["metrics"]) == WEIGHTS_WHOLE
            if not ok:
                self.faults.append("block %d CREATED AN INCENTIVE PLAN IT COULD NOT" % idx)
                return
            self.plans[self.next_plan] = {"companyId": co, "maxBps": fc["maxBps"], "isActive": True}
            self.metrics[self.next_plan] = [dict(m) for m in fc["metrics"]]
            self.next_plan += 1
            return

        def active_plan(co, pid):
            p = self.plans.get(pid)
            return p if p is not None and p["companyId"] == co and p["isActive"] else None

        if f == "retireIncentivePlan":
            p = active_plan(c["companyId"], c["planId"])
            if not member(c["companyId"]) or p is None:
                self.faults.append("block %d retired an incentive plan it could not" % idx)
                return
            p["isActive"] = False
            return

        if f == "scoreIncentive":
            fc = c["facts"]
            co = fc["companyId"]
            p = active_plan(co, fc["planId"])
            eid, e = people.employee_of(co, fc["subject"])
            base = base_of(co, fc["subject"])
            ms = self.metrics.get(fc["planId"], [])
            ok = member(co) and p is not None and eid is not None and e["isActive"] and caller != bytes(fc["subject"]) and base is not None and fc["periodDay"] < MAX_DAY \
                and len(fc["scores"]) == len(ms) and all(s <= SCORE_MAX for s in fc["scores"]) \
                and not any(s["planId"] == fc["planId"] and s["employeeId"] == eid and s["periodDay"] == fc["periodDay"] for s in self.scores.values())
            if not ok:
                self.faults.append("block %d SCORED AN INCENTIVE IT COULD NOT" % idx)
                return
            self.finals_recomputed += 1
            fb = final_bps([m["weightBps"] for m in ms], fc["scores"], p["maxBps"])
            self.scores[self.next_score] = {"companyId": co, "planId": fc["planId"], "employeeId": eid, "subject": bytes(fc["subject"]), "periodDay": fc["periodDay"],
                                            "finalBps": fb, "baseMonthly": base, "amount": base * fb // WEIGHTS_WHOLE, "paymentId": 0}
            self.next_score += 1
            return

        if f == "createOffCyclePayment":
            fc = c["facts"]
            co = fc["companyId"]
            eid, e = people.employee_of(co, fc["subject"])
            ok = member(co) and eid is not None and e["isActive"] and caller != bytes(fc["subject"]) and fc["title"] and fc["periodDay"] < MAX_DAY \
                and 0 < fc["gross"] < MAX_MONEY and fc["deductions"] <= fc["gross"] and fc["kind"] in OFFCYCLE_KINDS
            if ok and fc["scoreId"]:
                sc = self.scores.get(fc["scoreId"])
                ok = sc is not None and sc["companyId"] == co and sc["subject"] == bytes(fc["subject"]) and sc["paymentId"] == 0 and fc["kind"] == 1 and fc["gross"] == sc["amount"]
            if not ok:
                self.faults.append("block %d CREATED A PAYMENT IT COULD NOT" % idx)
                return
            pid = self.next_payment
            self.payments[pid] = {"companyId": co, "employeeId": eid, "subject": bytes(fc["subject"]), "kind": OFFCYCLE_KINDS[fc["kind"]], "gross": fc["gross"], "deductions": fc["deductions"],
                                  "net": fc["gross"] - fc["deductions"], "scoreId": fc["scoreId"], "state": "pending", "moveId": 0, "createdBy": caller}
            self.next_payment += 1
            if fc["scoreId"]:
                self.scores[fc["scoreId"]]["paymentId"] = pid
            return

        def pending_payment(co, pid):
            p = self.payments.get(pid)
            return p if p is not None and p["companyId"] == co and member(co) and p["state"] == "pending" else None

        def free_score(sid):
            if sid and sid in self.scores:
                self.scores[sid]["paymentId"] = 0

        if f == "approveOffCyclePayment":
            co = c["companyId"]
            p = pending_payment(co, c["paymentId"])
            policy = self.policies.get(co)
            if p is None or caller == p["createdBy"] or caller == p["subject"] or policy is None \
               or live_account(co, policy["salaryExpenseAccountId"]) is None or live_account(co, policy["employeePayableAccountId"]) is None \
               or (p["deductions"] > 0 and live_account(co, policy["deductionsAccountId"]) is None):
                self.faults.append("block %d APPROVED A PAYMENT IT COULD NOT" % idx)
                return
            lines = [{"accountId": policy["salaryExpenseAccountId"], "partnerId": 0, "name": "off-cycle gross", "debit": p["gross"], "credit": 0, "amountCurrency": 0, "taxId": 0}]
            if p["deductions"] > 0:
                lines.append({"accountId": policy["deductionsAccountId"], "partnerId": 0, "name": "off-cycle deductions", "debit": 0, "credit": p["deductions"], "amountCurrency": 0, "taxId": 0})
            lines.append({"accountId": policy["employeePayableAccountId"], "partnerId": 0, "name": "off-cycle net", "debit": 0, "credit": p["net"], "amountCurrency": 0, "taxId": 0})
            p["moveId"] = post(co, policy, p["createdBy"], lines, "off-cycle payment %d" % c["paymentId"], "approved a payment")
            p["state"] = "approved"
            return

        if f == "rejectOffCyclePayment":
            p = pending_payment(c["companyId"], c["paymentId"])
            if p is None or caller == p["createdBy"] or not c["reason"]:
                self.faults.append("block %d rejected a payment it could not" % idx)
                return
            p["state"] = "rejected"
            free_score(p["scoreId"])
            return

        if f == "cancelOffCyclePayment":
            p = pending_payment(c["companyId"], c["paymentId"])
            if p is None or caller != p["createdBy"]:
                self.faults.append("block %d cancelled a payment it could not" % idx)
                return
            p["state"] = "cancelled"
            free_score(p["scoreId"])
            return

        if f == "requestLoan":
            fc = c["facts"]
            co = fc["companyId"]
            eid, e = people.employee_of(co, caller)
            base = base_of(co, caller)
            ok = member(co) and eid is not None and e["isActive"] and base is not None and 0 < fc["amount"] <= base * LOAN_MONTHS and fc["amount"] < MAX_MONEY and fc["justification"] \
                and fc["kind"] in LOAN_KINDS and fc["schedule"] in LOAN_SCHEDULES \
                and not any(l["employeeId"] == eid and l["state"] in ("requested", "approved", "disbursed") for l in self.loans.values())
            if not ok:
                self.faults.append("block %d REQUESTED A LOAN IT COULD NOT" % idx)
                return
            self.loans[self.next_loan] = {"companyId": co, "employeeId": eid, "subject": caller, "kind": LOAN_KINDS[fc["kind"]], "requestedAmount": fc["amount"], "approvedAmount": 0,
                                          "schedule": LOAN_SCHEDULES[fc["schedule"]], "repaid": 0, "state": "requested", "decidedBy": caller}
            self.next_loan += 1
            return

        def loan_of(co, lid):
            l = self.loans.get(lid)
            return l if l is not None and l["companyId"] == co and member(co) else None

        if f == "withdrawLoan":
            l = loan_of(c["companyId"], c["loanId"])
            if l is None or l["state"] != "requested" or caller != l["subject"]:
                self.faults.append("block %d withdrew a loan it could not" % idx)
                return
            l["state"] = "withdrawn"
            return

        if f == "decideLoan":
            l = loan_of(c["companyId"], c["loanId"])
            if l is None or l["state"] != "requested" or caller == l["subject"] or (c["approve"] and not 0 < c["approvedAmount"] <= l["requestedAmount"]) or (not c["approve"] and not c["note"]):
                self.faults.append("block %d DECIDED A LOAN IT COULD NOT" % idx)
                return
            l["state"] = "approved" if c["approve"] else "rejected"
            l["approvedAmount"] = c["approvedAmount"] if c["approve"] else 0
            l["decidedBy"] = caller
            return

        if f == "disburseLoan":
            co = c["companyId"]
            l = loan_of(co, c["loanId"])
            policy = self.policies.get(co)
            cash = live_account(co, c["cashAccountId"])
            if l is None or l["state"] != "approved" or caller == l["subject"] or caller == l["decidedBy"] or policy is None \
               or live_account(co, policy["loanReceivableAccountId"]) is None or cash is None or cash["accountType"] != "asset" or c["cashAccountId"] == policy["loanReceivableAccountId"]:
                self.faults.append("block %d DISBURSED A LOAN IT COULD NOT" % idx)
                return
            lines = [{"accountId": policy["loanReceivableAccountId"], "partnerId": 0, "name": "loan disbursed", "debit": l["approvedAmount"], "credit": 0, "amountCurrency": 0, "taxId": 0},
                     {"accountId": c["cashAccountId"], "partnerId": 0, "name": "loan disbursed", "debit": 0, "credit": l["approvedAmount"], "amountCurrency": 0, "taxId": 0}]
            post(co, policy, l["decidedBy"], lines, "employee loan %d disbursed" % c["loanId"], "disbursed a loan")
            l["state"] = "disbursed"
            return

        if f == "recordLoanRepayment":
            fc = c["facts"]
            co = fc["companyId"]
            l = loan_of(co, fc["loanId"])
            policy = self.policies.get(co)
            cash = live_account(co, fc["cashAccountId"])
            outstanding = (l["approvedAmount"] - l["repaid"]) if l is not None else 0
            if l is None or l["state"] != "disbursed" or caller == l["subject"] or not 0 < fc["amount"] <= outstanding or policy is None \
               or live_account(co, policy["loanReceivableAccountId"]) is None or cash is None or cash["accountType"] not in ("asset", "liability", "payable") or fc["cashAccountId"] == policy["loanReceivableAccountId"]:
                self.faults.append("block %d RECORDED A REPAYMENT IT COULD NOT" % idx)
                return
            lines = [{"accountId": fc["cashAccountId"], "partnerId": 0, "name": "loan repaid", "debit": fc["amount"], "credit": 0, "amountCurrency": 0, "taxId": 0},
                     {"accountId": policy["loanReceivableAccountId"], "partnerId": 0, "name": "loan repaid", "debit": 0, "credit": fc["amount"], "amountCurrency": 0, "taxId": 0}]
            post(co, policy, l["subject"], lines, "employee loan %d repaid" % fc["loanId"], "recorded a repayment")
            self.repayments[self.next_repayment] = {"loanId": fc["loanId"], "amount": fc["amount"], "day": day}
            self.next_repayment += 1
            l["repaid"] += fc["amount"]
            if l["repaid"] == l["approvedAmount"]:
                l["state"] = "settled"
            return

        if f == "createBenefitPlan":
            fc = c["facts"]
            co = fc["companyId"]
            tiers = fc["tiers"]
            ok = member(co) and fc["name"] and fc["provider"] and fc["employeeCost"] < MAX_MONEY and fc["employerCost"] < MAX_MONEY and tiers and len(set(tiers)) == len(tiers) \
                and all(t in TIERS for t in tiers) and fc["category"] in BENEFIT_CATEGORIES
            if not ok:
                self.faults.append("block %d created a benefit plan it could not" % idx)
                return
            self.benefit_plans[self.next_benefit_plan] = {"companyId": co, "employeeCost": fc["employeeCost"], "employerCost": fc["employerCost"], "tiers": set(tiers), "isActive": True}
            self.next_benefit_plan += 1
            return

        if f == "toggleBenefitPlan":
            p = self.benefit_plans.get(c["planId"])
            if not member(c["companyId"]) or p is None or p["companyId"] != c["companyId"] or p["isActive"] == c["isActive"]:
                self.faults.append("block %d toggled a benefit plan it could not" % idx)
                return
            p["isActive"] = c["isActive"]
            return

        if f == "openEnrolmentPeriod":
            fc = c["facts"]
            co = fc["companyId"]
            overlaps = any(p["companyId"] == co and p["startDay"] <= fc["endDay"] and fc["startDay"] <= p["endDay"] for p in self.periods.values())
            if not member(co) or not fc["name"] or fc["endDay"] >= MAX_DAY or fc["startDay"] >= MAX_DAY or fc["endDay"] < fc["startDay"] or fc["endDay"] < day or overlaps:
                self.faults.append("block %d OPENED AN ENROLMENT PERIOD IT COULD NOT" % idx)
                return
            self.periods[self.next_period] = {"companyId": co, "startDay": fc["startDay"], "endDay": fc["endDay"]}
            self.next_period += 1
            return

        def open_period(co, on_day):
            self.periods_read += 1
            for pid, p in self.periods.items():
                if p["companyId"] == co and p["startDay"] <= on_day <= p["endDay"]:
                    return pid
            return None

        if f == "enrolInBenefit":
            fc = c["facts"]
            co = fc["companyId"]
            eid, e = people.employee_of(co, caller)
            p = self.benefit_plans.get(fc["planId"])
            period = open_period(co, day)
            ok = member(co) and eid is not None and e["isActive"] and p is not None and p["companyId"] == co and p["isActive"] and fc["tier"] in p["tiers"] and period is not None
            if not ok:
                self.faults.append("block %d ENROLLED IN A BENEFIT IT COULD NOT" % idx)
                return
            mine = [(i, en) for i, en in self.enrolments.items() if en["planId"] == fc["planId"] and en["employeeId"] == eid]
            if mine:
                i, en = mine[0]
                if en["isActive"]:
                    self.faults.append("block %d ENROLLED TWICE" % idx)
                    return
                en.update(tier=TIERS[fc["tier"]], isActive=True)
                return
            self.enrolments[self.next_enrolment] = {"planId": fc["planId"], "employeeId": eid, "subject": caller, "tier": TIERS[fc["tier"]], "isActive": True}
            self.next_enrolment += 1
            return

        if f == "waiveBenefit":
            co = c["companyId"]
            eid, _e = people.employee_of(co, caller)
            p = self.benefit_plans.get(c["planId"])
            mine = [en for en in self.enrolments.values() if en["planId"] == c["planId"] and en["employeeId"] == eid] if eid is not None else []
            if not member(co) or eid is None or p is None or p["companyId"] != co or not mine or not mine[0]["isActive"] or open_period(co, day) is None:
                self.faults.append("block %d WAIVED A BENEFIT IT COULD NOT" % idx)
                return
            mine[0]["isActive"] = False
            return

    # -- what the contract prints, recomputed --

    def band_line(self, bid):
        b = self.bands[bid]
        return (b["companyId"], b["grade"], b["minAmount"], b["midAmount"], b["maxAmount"], 1 if b["isActive"] else 0)

    def review_line(self, rid):
        """employeeId bandId current proposed effectiveDay state compaRatio - the compa-ratio recomputed against the band"""
        r = self.reviews[rid]
        mid = self.bands[r["bandId"]]["midAmount"] if r["bandId"] in self.bands else 0
        return (r["employeeId"], r["bandId"], r["currentBase"], r["proposedBase"], r["effectiveDay"], r["state"], compa_ratio(r["proposedBase"], mid))

    def grant_line(self, gid, on_day):
        """employeeId kind total vested exercised state day vestedOnDay - the last the schedule computed on the day named"""
        g = self.grants[gid]
        self.vesting_recomputed += 1
        return (g["employeeId"], g["kind"], g["totalShares"], g["vestedShares"], g["exercisedShares"], g["state"], on_day, vested_on(g, on_day))

    def score_line(self, sid):
        s = self.scores[sid]
        return (s["planId"], s["employeeId"], s["periodDay"], s["finalBps"], s["baseMonthly"], s["amount"], s["paymentId"])

    def payment_line(self, pid):
        p = self.payments[pid]
        return (p["employeeId"], p["kind"], p["gross"], p["deductions"], p["net"], p["state"], 1 if p["moveId"] else 0)

    def loan_line(self, lid):
        """employeeId kind requested approved schedule repaid repayments state outstanding (instalments) - the repaid and the
        count re-added from the repayment rows, the instalments and what is owed the arithmetic again"""
        l = self.loans[lid]
        mine = [r for r in self.repayments.values() if r["loanId"] == lid]
        repaid = sum(r["amount"] for r in mine)
        self.schedules_recomputed += 1
        return (l["employeeId"], l["kind"], l["requestedAmount"], l["approvedAmount"], l["schedule"], repaid, len(mine), l["state"],
                max(l["approvedAmount"] - repaid, 0), tuple(instalments(l["schedule"], l["approvedAmount"])))

    def repayment_line(self, rid):
        r = self.repayments[rid]
        mine = sorted(i for i, x in self.repayments.items() if x["loanId"] == r["loanId"])
        return (r["loanId"], mine.index(rid) + 1, r["amount"], r["day"])

    def period_line(self, pid, on_day):
        p = self.periods[pid]
        self.periods_read += 1
        return (p["companyId"], p["startDay"], p["endDay"], on_day, 1 if p["startDay"] <= on_day <= p["endDay"] else 0)

    def enrolment_line(self, eid):
        """planId employeeId tier active employeeCost employerCost - the costs re-added over the employee's enrolments that stand"""
        en = self.enrolments[eid]
        self.costs_readded += 1
        emp = sum(self.benefit_plans[x["planId"]]["employeeCost"] for x in self.enrolments.values() if x["employeeId"] == en["employeeId"] and x["isActive"])
        er = sum(self.benefit_plans[x["planId"]]["employerCost"] for x in self.enrolments.values() if x["employeeId"] == en["employeeId"] and x["isActive"])
        return (en["planId"], en["employeeId"], en["tier"], 1 if en["isActive"] else 0, emp, er)

    def summary(self):
        return {"bands": len(self.bands), "reviews": len(self.reviews), "grants": len(self.grants), "scores": len(self.scores), "payments": len(self.payments),
                "loans": len(self.loans), "repayments": len(self.repayments), "benefit plans": len(self.benefit_plans), "enrolments": len(self.enrolments), "faults": len(self.faults)}
