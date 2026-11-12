"""Payroll, recomputed independently.

This is the acceptance criterion of the payroll proposal made executable: an implementation written
from the statutory profile ROWS and the design, not translated from the Motoko, that recomputes
every payslip of a run from the log alone and agrees with the contract to the minor unit - every
earning, every deduction, the employer cost, the net, and the residue.

It uses Python's `decimal` at a precision that cannot round intermediate values, which is a
genuinely different arithmetic from the kernel's `Dec`: if the two agree on every payslip of a run
whose salaries were chosen to land in five different brackets, the agreement is evidence.

THE RULES, stated before they are implemented:

  base for the period   monthly × 12 ÷ periods-per-year, exact integer (all four frequencies divide
                        a year evenly, which is why the stored basis is monthly)
  overtime              minutes ÷ 60 × hourly rate × multiplier, quantised once
  social contribution   the rate applied to gross, clamped between the profile's floor and ceiling
  income tax            gross × periods − personal allowance, walked through the brackets in order,
                        then divided back by the period count
  net                   gross − deductions, exactly
  residue               the sum of what every quantisation discarded, as an exact decimal, quantised
                        ONCE at the end - never per-quantisation, which would be zero every time

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from decimal import Decimal, getcontext, ROUND_HALF_EVEN

getcontext().prec = 60

RATE_SCALE = Decimal(1_000_000)
PERIODS = {"Weekly": 52, "BiWeekly": 26, "SemiMonthly": 24, "Monthly": 12}
# There is no overtime multiplier here. It is read from the statutory profile the compensation row
# names, at the category the APPROVED claim carries - the contract writes it onto the claim when
# somebody other than the claimant approves it, and this recomputes the same figure from the log.


def minor(units, exponent):
    """A count of minor units as an exact major-unit decimal."""
    return Decimal(units) / (Decimal(10) ** exponent)


def quantise(value, exponent):
    """To a whole number of minor units, half-even, with what was discarded - exactly.

    The discard is a DECIMAL, not an integer: it is smaller than one minor unit by construction, so
    an integer would be zero every time and a residue built from integers would account for nothing.
    """
    scaled = value * (Decimal(10) ** exponent)
    units = int(scaled.to_integral_value(rounding=ROUND_HALF_EVEN))
    if units < 0:
        units = 0
    back = minor(units, exponent)
    return units, value - back


def income_tax(annual_taxable, brackets, exponent):
    """Walk the brackets in order. The table must be contiguous from 1 and each bracket must run
    forwards - a gap taxes somebody at the wrong rate and nothing in the arithmetic notices."""
    expected = 1
    for b in brackets:
        if b["ordinal"] != expected:
            raise ValueError("bracket %d is missing; found %d" % (expected, b["ordinal"]))
        if b["toAmount"] != 0 and b["toAmount"] <= b["fromAmount"]:
            raise ValueError("bracket %d runs backwards" % b["ordinal"])
        expected += 1

    total = Decimal(0)
    for b in brackets:
        if annual_taxable > b["fromAmount"]:
            upper = annual_taxable if b["toAmount"] == 0 else min(annual_taxable, b["toAmount"])
            if upper > b["fromAmount"]:
                slice_units = upper - b["fromAmount"]
                total += minor(slice_units, exponent) * Decimal(b["rate"]) / RATE_SCALE
    return quantise(total, exponent)


def compute(comp, profile, brackets, overtime_claims, bonus, exponent=2):
    """One payslip. Returns the same fields the contract stores."""
    lines = []
    residue = Decimal(0)

    periods = PERIODS[comp["frequency"]]
    base = (comp["baseMonthly"] * 12) // periods

    gross = 0
    if base > 0:
        lines.append(("earning", "BASE", base))
        gross += base

    # Each approved claim at ITS OWN premium, quantised on its own so the per-claim figures sum
    # exactly to the one OVERTIME line. A Saturday and a public holiday are not the same money and
    # one multiplier can only be right for one of them.
    overtime_total = 0
    for minutes, multiplier in overtime_claims:
        if minutes > 0 and comp["hourlyRate"] > 0:
            hours = Decimal(minutes) / Decimal(60)
            at_rate = hours * minor(comp["hourlyRate"], exponent)
            with_multiplier = at_rate * Decimal(multiplier) / RATE_SCALE
            units, discarded = quantise(with_multiplier, exponent)
            residue += discarded
            overtime_total += units
    if overtime_total > 0:
        lines.append(("earning", "OVERTIME", overtime_total))
        gross += overtime_total

    if bonus > 0:
        lines.append(("earning", "BONUS", bonus))
        gross += bonus

    floor_, ceiling = profile["socialFloor"], profile["socialCeiling"]
    social_base = floor_ if gross < floor_ else (ceiling if ceiling > 0 and gross > ceiling else gross)

    deductions = 0
    if profile["socialEmployeeRate"] > 0:
        units, discarded = quantise(minor(social_base, exponent) * Decimal(profile["socialEmployeeRate"]) / RATE_SCALE, exponent)
        residue += discarded
        if units > 0:
            lines.append(("deduction", "SOCIAL", units))
            deductions += units

    employer = 0
    if profile["socialEmployerRate"] > 0:
        units, discarded = quantise(minor(social_base, exponent) * Decimal(profile["socialEmployerRate"]) / RATE_SCALE, exponent)
        residue += discarded
        if units > 0:
            lines.append(("employer", "SOCIAL_ER", units))
            employer += units

    annual_gross = gross * periods
    allowance = profile["personalAllowance"]
    annual_taxable = annual_gross - allowance if annual_gross > allowance else 0
    annual_units, annual_discarded = income_tax(annual_taxable, brackets, exponent)
    residue += annual_discarded
    if annual_units > 0:
        per_period = minor(annual_units, exponent) / Decimal(periods)
        units, discarded = quantise(per_period, exponent)
        residue += discarded
        if units > 0:
            lines.append(("deduction", "INCOME_TAX", units))
            deductions += units

    if deductions > gross:
        raise ValueError("deductions of %d exceed gross of %d" % (deductions, gross))
    net = gross - deductions

    residue_units, _fraction = quantise(residue, exponent) if residue >= 0 else (
        -quantise(-residue, exponent)[0], Decimal(0))

    return {
        "lines": lines, "gross": gross, "deductions": deductions, "net": net,
        "employerCost": employer, "residueUnits": residue_units,
    }


class Payroll:
    """The payroll half of the fold: profiles, brackets, compensation, runs and payslips."""

    def __init__(self):
        self.profiles = {}
        self.next_profile = 1
        self.brackets = {}       # profileId -> [bracket]
        self.comp = {}           # (company, subject) -> compensation
        self.runs = {}
        self.next_run = 1
        self.payslips = {}       # (runId, subject) -> computed
        self.premiums = {}       # profileId -> {category -> multiplier}
        self.claims = {}         # overtime id -> claim
        self.next_claim = 1
        self.faults = []

    def apply(self, block):
        c = block["command"]
        f = c["family"]

        if f == "declareStatutoryProfile":
            self.profiles[self.next_profile] = c["facts"]
            self.brackets[self.next_profile] = []
            self.next_profile += 1
        elif f == "declareTaxBracket":
            b = c["facts"]
            table = self.brackets.setdefault(b["profileId"], [])
            if b["ordinal"] != len(table) + 1:
                self.faults.append("block %d declared bracket %d when %d was next"
                                   % (block["index"], b["ordinal"], len(table) + 1))
            table.append(b)
        elif f == "declareOvertimePremiums":
            k = c["facts"]
            self.premiums[k["profileId"]] = {
                "regular": k["regular"], "weekend": k["weekend"],
                "holiday": k["holiday"], "emergencyCallIn": k["callIn"],
            }
        elif f == "claimOvertime":
            k = c["facts"]
            self.claims[self.next_claim] = {**k, "state": "draft", "multiplier": 0,
                                            "subject": block["caller"]}
            self.next_claim += 1
        elif f == "submitOvertime":
            claim = self.claims.get(c["overtimeId"])
            if claim is not None and claim["state"] == "draft":
                claim["state"] = "submitted"
        elif f == "cancelOvertime":
            claim = self.claims.get(c["overtimeId"])
            if claim is not None and claim["state"] in ("draft", "submitted"):
                claim["state"] = "cancelled"
        elif f == "decideOvertime":
            claim = self.claims.get(c["overtimeId"])
            if claim is None or claim["state"] != "submitted":
                pass
            elif not c["approve"]:
                claim["state"] = "rejected"
            else:
                comp = self.comp.get((claim["companyId"], claim["subject"]))
                if comp is None:
                    self.faults.append("block %d approved overtime for somebody with no compensation" % block["index"])
                else:
                    prem = self.premiums.get(comp["profileId"])
                    if prem is None or prem.get(claim["category"], 0) == 0:
                        self.faults.append("block %d approved overtime under a profile with no premium" % block["index"])
                    else:
                        claim["multiplier"] = prem[claim["category"]]
                        claim["state"] = "approved"
        elif f == "setCompensation":
            k = c["facts"]
            self.comp[(k["companyId"], k["subject"])] = k
        elif f == "openPayrollRun":
            rid = self.next_run
            self.next_run += 1
            self.runs[rid] = {**c, "state": "Running", "paid": 0}
        elif f == "runPayrollSlice":
            s = c["facts"]
            run = self.runs.get(s["runId"])
            if run is None:
                self.faults.append("block %d ran a slice of a run that does not exist" % block["index"])
                return
            if run["planHash"] != s["planHash"]:
                self.faults.append("block %d ran a slice whose plan hash is not the run's" % block["index"])
                return
            if not (len(s["subjects"]) == len(s["overtimeMinutes"]) == len(s["bonuses"])):
                self.faults.append("block %d ran a slice whose arrays do not line up" % block["index"])
                return
            for i, subject in enumerate(s["subjects"]):
                if (s["runId"], subject) in self.payslips:
                    self.faults.append("block %d paid someone twice in one run" % block["index"])
                    continue
                comp = self.comp.get((s["companyId"], subject))
                if comp is None:
                    self.faults.append("block %d paid someone with no compensation" % block["index"])
                    continue
                profile = self.profiles.get(comp["profileId"])
                if profile is None:
                    self.faults.append("block %d used a profile that does not exist" % block["index"])
                    continue
                # THE OVERTIME COMES FROM THE APPROVED CLAIMS, in id order, and the slice's own
                # figure is only a claim ABOUT them. The contract refuses a disagreement; so does
                # this, because a run built on a different belief about the overtime is a fault.
                mine = [(cid, cl) for cid, cl in sorted(self.claims.items())
                        if cl["companyId"] == s["companyId"] and cl["subject"] == subject
                        and cl["state"] == "approved" and cl["payout"] == "cash"
                        and cl["businessDay"] <= run["periodDay"]]
                if sum(cl["minutes"] for _, cl in mine) != s["overtimeMinutes"][i]:
                    self.faults.append("block %d ran a slice whose overtime is not what was approved" % block["index"])
                    continue
                slip = compute(comp, profile, self.brackets.get(comp["profileId"], []),
                               [(cl["minutes"], cl["multiplier"]) for _, cl in mine], s["bonuses"][i])
                for cid, cl in mine:
                    cl["state"] = "paid"
                self.payslips[(s["runId"], subject)] = slip
                run["paid"] += 1
            if run["paid"] > run["headcount"]:
                self.faults.append("block %d paid more people than the plan's headcount" % block["index"])
        elif f == "closePayrollRun":
            run = self.runs.get(c["runId"])
            if run is not None:
                run["state"] = "Computed"
        elif f == "approvePayrollRun":
            run = self.runs.get(c["runId"])
            if run is None:
                return
            if any(k[0] == c["runId"] and k[1] == block["caller"] for k in self.payslips):
                self.faults.append("block %d let someone approve a run their own payslip is in" % block["index"])
            run["state"] = "Approved"
        elif f == "postPayrollJournal":
            d = sum(a for _c, a in c["debits"])
            cr = sum(a for _c, a in c["credits"])
            if d != cr:
                self.faults.append("block %d posted an unbalanced journal entry" % block["index"])
            expected = sum(s["residueUnits"] for (rid, _s), s in self.payslips.items() if rid == c["runId"])
            if expected != c["differenceAmount"]:
                self.faults.append("block %d posted a difference of %d when the run produced %d"
                                   % (block["index"], c["differenceAmount"], expected))
        elif f == "abandonPayrollRun":
            run = self.runs.get(c["runId"])
            if run is not None:
                run["state"] = "Abandoned"

    def summary(self):
        return {
            "profiles": len(self.profiles),
            "brackets": sum(len(b) for b in self.brackets.values()),
            "compensations": len(self.comp),
            "runs": len(self.runs),
            "payslips": len(self.payslips),
            "faults": len(self.faults),
        }

    def compare(self, reported):
        """`reported` is the contract's own figures: subject-hex -> (gross, ded, net, employer,
        residue-zigzag). Every one must match, to the minor unit."""
        mismatches = []
        for key, slip in self.payslips.items():
            _rid, subject = key
            h = subject.hex()
            if h not in reported:
                mismatches.append("the contract reported no payslip for %s" % h[:16])
                continue
            g, d, n, e, rz = reported[h]
            r = rz // 2 if rz % 2 == 0 else -((rz + 1) // 2)
            if (g, d, n, e, r) != (slip["gross"], slip["deductions"], slip["net"],
                                   slip["employerCost"], slip["residueUnits"]):
                mismatches.append(
                    "%s: contract (gross %d ded %d net %d er %d res %d) oracle (gross %d ded %d net %d er %d res %d)"
                    % (h[:16], g, d, n, e, r, slip["gross"], slip["deductions"], slip["net"],
                       slip["employerCost"], slip["residueUnits"]))
        for h in reported:
            if not any(s.hex() == h for _r, s in self.payslips):
                mismatches.append("the contract reported a payslip for %s that the log does not produce" % h[:16])
        return mismatches
