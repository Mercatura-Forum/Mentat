"""The controls families (599 to 605), decoded from their canonical bytes, re-encoded so the command hash can be
re-derived, and folded by rules written from the design (Solari's journal screening over this system's own journal,
the duplicate-bill and split-order tests, procedures concluded under four eyes):

  * EVERY POSTING IS RECORDED by this reader as it happens, from the ledger reader's own moves: a move this reader
    did not see posted before a block and sees posted after it was posted in that block, on that block's day, by
    hand when the block is a `postMove` and generated otherwise, reversing the closing move or the revaluation whose
    reversal it is. Every order this reader sees leave its draft in a block without being cancelled from it was
    confirmed in that block. The contract's own records of both are compared with these row by row.
  * A PROFILE is a version recorded by an administrator or a director in standing: criteria 1 to 28, each once,
    OUT-OF-HOURS (8) and TOP-SIDE (17) never; the parameters of every criterion applied within their bounds, and
    those of a criterion not applied recorded as zero; each list at most 64 long, each item once; at least one
    screening role, each once; a currency of one to four bytes.
  * A RUN is opened by a screener of the profile in force over a period, one at a time per company. Its POPULATION
    is the company's moves dated in the period that are posted, and were posted before the run's block; its bills
    those recorded before it, its orders those confirmed before it. Its slices walk FACTS (the counts), SCREEN (the
    criteria), BILLS, ORDERS and the SPLIT windows, each a page of at most the slice's limit; this reader walks the
    same pages over its own rows, so it knows which slice ends each phase and which seals the run.
  * A FINDING is concluded by a screener of the profile in force who neither prepared nor posted its subject (nor,
    for a bill, matched it), on a done run; a PROCEDURE is defined by an officer under a code once per company; a
    CONCLUSION is prepared by a member in standing who is not an employee - a screening procedure's on a done run
    of exactly its period, effective only with every finding concluded and none confirmed - and reviewed by an
    officer who did not prepare it.

The fingerprints are this reader's own (SHA-256 over the sorted lines, as the design states); the digit test is
computed in exact fractions against Solari's published ten-place table, which this reader holds to log10 itself.
Every row the contract holds is printed by the export and compared here, figure by figure.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import hashlib
from decimal import Decimal, getcontext
from fractions import Fraction

from canonical import write_nat, write_text

ROLES = {1: "CompanyAdmin", 2: "HR", 3: "Director", 4: "Manager", 5: "Employee", 6: "Auditor", 7: "Drafter"}
# the roles that hold no act: the auditor reads, the drafter only proposes drafts
NO_ACT = {"Auditor", "Drafter"}
ROLE_BYTE = {v: k for k, v in ROLES.items()}
ROLE_BIT = {"CompanyAdmin": 1, "HR": 2, "Director": 4, "Manager": 8, "Employee": 16, "Auditor": 32, "Drafter": 64}
COMPONENTS = {1: "controlEnvironment", 2: "riskAssessment", 3: "controlActivities", 4: "information", 5: "monitoring"}
RESULTS = {1: "effective", 2: "deficient", 3: "notApplicable"}
PHASE_BYTE = {"facts": 1, "screen": 2, "bills": 3, "orders": 4, "split": 5, "done": 6}
LIST_BYTE = {"holiday": 1, "keyword": 2, "account": 3, "user": 4, "approver": 5, "leaver": 6, "pair": 7}
FACT_BYTE = {"account": 1, "fingerprint": 2, "flow": 3, "preparer": 4, "digits": 5}
MARK_BYTE = {"billReference": 1, "billTotal": 2, "orderSupplier": 3}
SUBJECT_BYTE = {"move": 1, "bill": 2, "order": 3}
FINDING_STATE_BYTE = {"open": 1, "cleared": 2, "confirmed": 3}
CONCLUSION_STATE_BYTE = {"prepared": 1, "reviewed": 2}

CRITERIA = 28
(PERIOD_END, POST_CLOSE, ROUND_AMOUNT, LARGE_AMOUNT, UNUSUAL_ACCOUNT, SELF_APPROVED, WEEKEND_HOLIDAY, OUT_OF_HOURS,
 MANUAL, UNUSUAL_USER, NO_DESCRIPTION, KEYWORD, REVERSAL_AFTER_PERIOD, SELDOM_USED_ACCOUNT, DUPLICATE, BELOW_THRESHOLD,
 TOP_SIDE, LEAVER, UNAUTHORISED_APPROVER, UNUSUAL_FLOW, ACCOUNT_PAIR, BACKDATED, SEQUENCE_GAP, HIGH_VOLUME_USER,
 MANY_LINES, NO_REFERENCE, DUPLICATE_BILL, SPLIT_ORDER) = range(1, 29)
NOT_OFFERED = (OUT_OF_HOURS, TOP_SIDE)

ID, COMPANY, DAY, BLOCK, SEQUENCE, MONEY, HASH, PRINCIPAL, CODE, CURRENCY = 6, 6, 3, 6, 4, 8, 32, 30, 16, 4
LIST_MAX = 64
MAX_LIMIT = 1_000
MAX_TEXT = 4_000
DAY_MAX = 256 ** DAY - 1
MONEY_MAX = 256 ** MONEY - 1
COUNT_MAX = 256 ** SEQUENCE - 1
NOBODY = b"\x04"
SPACES = " \t\n\r\x0b\x0c"
FINGERPRINT_TAG = b"mentat/controls/fingerprint/1"
FLOW_TAG = b"mentat/controls/flow/1"
RUN_TAG = b"mentat/controls/run/1"
ZERO32 = bytes(32)

# Solari's published first-two-digits table, log10(1 + 1/d) x 10^10 for d = 10..99, verbatim; this reader holds
# every entry to its own log10 within the last place before it uses one
FIRST_TWO_E10 = (
    413926852, 377885609, 347621063, 321846834, 299632234, 280287236, 263289387, 248235837, 234810958, 222763947,
    211892991, 202033861, 193051552, 184834057, 177287670, 170333393, 163904162, 157942672, 152399666, 147232568,
    142404391, 137882845, 133639616, 129649772, 125891273, 122344564, 118992233, 115818725, 112810104, 109953843,
    107238654, 104654337, 102191652, 99842209, 97598373, 95453179, 93400263, 91433794, 89548427, 87739243,
    86001718, 84331675, 82725260, 81178902, 79689297, 78253375, 76868287, 75531379, 74240181, 72992387,
    71785846, 70618545, 69488600, 68394245, 67333827, 66305789, 65308672, 64341100, 63401780, 62489493,
    61603087, 60741477, 59903637, 59088596, 58295437, 57523289, 56771329, 56038775, 55324886, 54628957,
    53950319, 53288335, 52642400, 52011937, 51396397, 50795255, 50208014, 49634195, 49073345, 48525028,
    47988829, 47464350, 46951212, 46449050, 45957517, 45476278, 45005012, 44543414, 44091189, 43648054,
)


def table_holds():
    """Every entry of the table within one in its last place of log10(1 + 1/d) x 10^10, by this reader's own
    forty-digit logarithm."""
    getcontext().prec = 40
    return all(abs((1 + Decimal(1) / d).log10() * 10 ** 10 - e) <= 1 for d, e in zip(range(10, 100), FIRST_TWO_E10))


# -- the bytes --

def nat_bytes(n, width):
    return n.to_bytes(width, "big")


def principal_field(p):
    return bytes([len(p)]) + p + bytes(PRINCIPAL - 1 - len(p))


def principal_key(p):
    return principal_field(p) + bytes(HASH - PRINCIPAL)


def nat_key(n):
    return nat_bytes(n, HASH)


def text_field(t, width):
    b = t.encode("utf-8")
    return None if len(b) > width else b + bytes(width - len(b))


def text_of_field(b):
    return b.rstrip(b"\x00").decode("utf-8")


def write_bool(b):
    return b"\x01" if b else b"\x00"


def write_len16(n):
    return n.to_bytes(2, "big")


def write_nats(xs):
    return write_len16(len(xs)) + b"".join(write_nat(x) for x in xs)


def write_texts(xs):
    return write_len16(len(xs)) + b"".join(write_text(x) for x in xs)


def write_principal(p):
    return bytes([len(p)]) + p


def write_principals(xs):
    return write_len16(len(xs)) + b"".join(write_principal(x) for x in xs)


def read_list(r, fn):
    return [fn() for _ in range(r.len16())]


def read_profile(r):
    f = {"companyId": r.nat(), "criteria": read_list(r, r.nat)}
    for k in ("periodEndDays", "roundBase", "roundMinimum", "largeThreshold", "approvalThreshold", "bandPercent"):
        f[k] = r.nat()
    f["weekendDays"] = read_list(r, r.nat)
    f["holidays"] = read_list(r, r.nat)
    f["minDescription"] = r.nat()
    f["keywords"] = read_list(r, r.text)
    f["accounts"] = read_list(r, r.nat)
    f["users"] = read_list(r, lambda: bytes(r.principal()))
    f["approvers"] = read_list(r, lambda: bytes(r.principal()))
    f["leavers"] = read_list(r, lambda: (bytes(r.principal()), r.nat()))
    f["pairs"] = read_list(r, lambda: (r.text(), r.text()))
    for k in ("seldomMax", "flowMax", "highVolumeMax", "manyLinesMax", "backdatedDays", "duplicateWindowDays",
              "splitWindowDays", "benfordMinimum"):
        f[k] = r.nat()
    f["screeners"] = read_list(r, r.nat8)
    f["currency"] = r.text()
    return f


def write_profile(f):
    out = write_nat(f["companyId"]) + write_nats(f["criteria"])
    for k in ("periodEndDays", "roundBase", "roundMinimum", "largeThreshold", "approvalThreshold", "bandPercent"):
        out += write_nat(f[k])
    out += write_nats(f["weekendDays"]) + write_nats(f["holidays"]) + write_nat(f["minDescription"])
    out += write_texts(f["keywords"]) + write_nats(f["accounts"])
    out += write_principals(f["users"]) + write_principals(f["approvers"])
    out += write_len16(len(f["leavers"])) + b"".join(write_principal(p) + write_nat(d) for p, d in f["leavers"])
    out += write_len16(len(f["pairs"])) + b"".join(write_text(a) + write_text(b) for a, b in f["pairs"])
    for k in ("seldomMax", "flowMax", "highVolumeMax", "manyLinesMax", "backdatedDays", "duplicateWindowDays",
              "splitWindowDays", "benfordMinimum"):
        out += write_nat(f[k])
    out += write_len16(len(f["screeners"])) + bytes(f["screeners"])
    return out + write_text(f["currency"])


def read_procedure(r):
    return {"companyId": r.nat(), "code": r.text(), "title": r.text(), "component": r.nat8(), "screening": r.bool()}


def write_procedure(f):
    return (write_nat(f["companyId"]) + write_text(f["code"]) + write_text(f["title"]) + bytes([f["component"]])
            + write_bool(f["screening"]))


def read_conclusion(r):
    return {"companyId": r.nat(), "procedureId": r.nat(), "fromDay": r.nat(), "throughDay": r.nat(), "runId": r.nat(),
            "result": r.nat8(), "note": r.text()}


def write_conclusion(f):
    return (write_nat(f["companyId"]) + write_nat(f["procedureId"]) + write_nat(f["fromDay"]) + write_nat(f["throughDay"])
            + write_nat(f["runId"]) + bytes([f["result"]]) + write_text(f["note"]))


READERS = {
    599: ("setControlProfile", lambda r: {"facts": read_profile(r)}),
    600: ("openScreening", lambda r: {"facts": {"companyId": r.nat(), "fromDay": r.nat(), "throughDay": r.nat()}}),
    601: ("screenSlice", lambda r: {"companyId": r.nat(), "runId": r.nat(), "limit": r.nat()}),
    602: ("concludeFinding", lambda r: {"companyId": r.nat(), "findingId": r.nat(), "confirmed": r.bool(), "note": r.text()}),
    603: ("defineControlProcedure", lambda r: {"facts": read_procedure(r)}),
    604: ("prepareControlConclusion", lambda r: {"facts": read_conclusion(r)}),
    605: ("reviewControlConclusion", lambda r: {"companyId": r.nat(), "conclusionId": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_controls_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "setControlProfile": (599, lambda c: write_profile(c["facts"])),
    "openScreening": (600, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["fromDay"]) + write_nat(c["facts"]["throughDay"])),
    "screenSlice": (601, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_nat(c["limit"])),
    "concludeFinding": (602, lambda c: write_nat(c["companyId"]) + write_nat(c["findingId"]) + write_bool(c["confirmed"]) + write_text(c["note"])),
    "defineControlProcedure": (603, lambda c: write_procedure(c["facts"])),
    "prepareControlConclusion": (604, lambda c: write_conclusion(c["facts"])),
    "reviewControlConclusion": (605, lambda c: write_nat(c["companyId"]) + write_nat(c["conclusionId"])),
}


def controls_command_bytes(cmd):
    tag, enc = ENCODERS[cmd["family"]]
    return put_tag(tag) + enc(cmd)


# -- the texts, as the criteria read them --

def stripped(t):
    return t.strip(SPACES)


def ascii_lower(t):
    return "".join(chr(ord(ch) + 32) if "A" <= ch <= "Z" else ch for ch in t)


def normalised_reference(t):
    return "".join(ch.upper() for ch in t if ("a" <= ch <= "z") or ("A" <= ch <= "Z") or ("0" <= ch <= "9"))


def ascii_word(t):
    b = t.encode("utf-8")
    return 1 <= len(b) <= CODE and all(0x21 <= x <= 0x7E for x in b)


def crm_normalise(t):
    return ascii_lower(t).strip(" \t\n\r")


def leading_two(v):
    s = str(v)
    return int(s[:2]) if len(s) >= 2 else int(s) * 10


def day_fits(d):
    return 1 <= d <= DAY_MAX


def bit(k):
    return 1 << (k - 1)


def has(mask, k):
    return bool(mask & bit(k))


def popcount(mask):
    return bin(mask).count("1")


def round_half_up(num, den):
    """num/den to the nearest whole number, a half rounded up - as exact fractions, not by the contract's formula."""
    q = Fraction(num, den)
    return int(q + Fraction(1, 2)) if q >= 0 else -int(-q + Fraction(1, 2))


def fingerprint_of(lines):
    rows = sorted((l["accountId"], l["debit"], l["credit"]) for l in lines)
    return hashlib.sha256(FINGERPRINT_TAG + b"".join(nat_bytes(a, ID) + nat_bytes(d, MONEY) + nat_bytes(c, MONEY) for a, d, c in rows)).digest()


def flow_of(lines):
    def side(l):
        return 0x44 if l["debit"] > 0 else (0x43 if l["credit"] > 0 else 0x5A)
    rows = sorted((side(l), l["accountId"]) for l in lines)
    return hashlib.sha256(FLOW_TAG + b"".join(bytes([s]) + nat_bytes(a, ID) for s, a in rows)).digest()


def bill_total_key(partner, currency, total):
    return nat_bytes(partner, ID) + currency + nat_bytes(total, MONEY) + bytes(HASH - ID - CURRENCY - MONEY)


def bill_reference_key(partner, reference):
    return hashlib.sha256(nat_bytes(partner, ID) + reference.encode("utf-8")).digest()


def order_key(partner, currency):
    return nat_bytes(partner, ID) + currency + bytes(HASH - ID - CURRENCY)


def benford(counts, total):
    """MAD x 10^10, Nigrini's band and chi-square x 100, each from exact fractions over the published table."""
    if total == 0:
        return 0, 0, 0
    mad = sum(abs(Fraction(c, total) - Fraction(e, 10 ** 10)) for c, e in zip(counts, FIRST_TWO_E10)) / 90
    band = 1 if mad <= Fraction(12, 10_000) else 2 if mad <= Fraction(18, 10_000) else 3 if mad <= Fraction(22, 10_000) else 4
    chi = sum(Fraction((c * 10 ** 10 - total * e) ** 2, 10 ** 10 * total * e) for c, e in zip(counts, FIRST_TWO_E10))
    return round_half_up(mad.numerator * 10 ** 10, mad.denominator), band, round_half_up(chi.numerator * 100, chi.denominator)


class Controls:
    def __init__(self):
        # what the reader records itself, from the ledger and order readers
        self.postings = {}           # move id -> row
        self.confirmations = {}      # order id -> row
        self._seen_moves = 0
        self._unposted = set()
        self._seen_orders = 0
        self._drafts = set()
        # the controls rows
        self.standings = {}          # company -> row
        self.profiles = {}
        self.items = {}
        self.runs = {}
        self.counts = {}             # id -> row
        self.count_of = {}           # (run, kind, key) -> id
        self.marks = {}
        self.findings = {}
        self.finding_of = {}         # (run, kind, subject) -> id
        self.procedures = {}
        self.conclusions = {}
        self.next = {"profile": 1, "item": 1, "run": 1, "count": 1, "mark": 1, "finding": 1, "procedure": 1, "conclusion": 1}
        self.slices = 0
        self.criteria_restated = 0
        self.faults = []
        self.table_holds = table_holds()

    # -- the records this reader keeps of what the other readers folded --

    def after_block(self, block, store):
        """Every move first seen posted, and every order first seen past its draft, in the block just folded."""
        ledger, credit = store.ledger, store.credit
        idx, day = block["index"], block["day"]
        newly = []
        for mid in range(self._seen_moves + 1, ledger.next_move):
            m = ledger.moves.get(mid)
            if m is None:
                self.faults.append("block %d: the ledger reader holds no move %d below its next" % (idx, mid))
            elif m["state"] == "posted":
                newly.append(mid)
            elif m["state"] == "proposed":
                self._unposted.add(mid)
        self._seen_moves = ledger.next_move - 1
        for mid in sorted(self._unposted):
            st = ledger.moves[mid]["state"]
            if st == "posted":
                newly.append(mid)
            if st != "proposed":
                self._unposted.discard(mid)
        if newly:
            reversal_of = {}
            for rows in ledger.close_moves.values():
                for _ordinal, original, reversal in rows:
                    if reversal:
                        reversal_of[reversal] = original
            for x in ledger.revaluations.values():
                if x.get("reversalMoveId"):
                    reversal_of[x["reversalMoveId"]] = x["moveId"]
            manual = block["command"]["family"] == "postMove"
            for mid in sorted(newly):
                if mid in self.postings:
                    self.faults.append("block %d posted move %d a second time" % (idx, mid))
                    continue
                self.postings[mid] = {"companyId": ledger.moves[mid]["companyId"], "postedDay": day, "manual": manual,
                                      "reverses": reversal_of.get(mid, 0), "lastBlock": idx}
        for oid in range(self._seen_orders + 1, credit.next_order):
            self._drafts.add(oid)
        self._seen_orders = credit.next_order - 1
        for oid in sorted(self._drafts):
            o = credit.orders.get(oid)
            if o is None or o["state"] == "draft":
                continue
            self._drafts.discard(oid)
            if o["state"] == "cancelled" and block["command"]["family"] != "confirmOrder":
                continue
            fc = o["facts"]
            self.confirmations[oid] = {"companyId": fc["companyId"], "confirmedDay": day, "lastBlock": idx,
                                       "confirmedBy": bytes(block["caller"]), "amount": credit.order_total(o)}

    # -- the rules, restated --

    @staticmethod
    def role_in_standing(store, co, caller):
        d = store.discuss
        if co not in store.companies or not d.is_member(co, caller) or (co, caller) in d.suspended:
            return None
        return d.roles.get((co, caller))

    def profile_in_force(self, co):
        s = self.standings.get(co)
        return (s["profileId"], self.profiles[s["profileId"]]) if s else (None, None)

    def listed(self, profile_id, lst, key):
        return any(x["profileId"] == profile_id and x["list"] == lst and x["key"] == key for x in self.items.values())

    def items_of(self, profile_id, lst):
        return [x for _i, x in sorted(self.items.items()) if x["profileId"] == profile_id and x["list"] == lst]

    def profile_valid(self, store, f):
        ks = f["criteria"]
        if not ks or len(set(ks)) != len(ks) or any(k < 1 or k > CRITERIA or k in NOT_OFFERED for k in ks):
            return None
        mask = sum(bit(k) for k in ks)
        bounds = ((PERIOD_END, f["periodEndDays"], 0, DAY_MAX), (ROUND_AMOUNT, f["roundBase"], 1, MONEY_MAX),
                  (ROUND_AMOUNT, f["roundMinimum"], 0, MONEY_MAX), (LARGE_AMOUNT, f["largeThreshold"], 1, MONEY_MAX),
                  (BELOW_THRESHOLD, f["approvalThreshold"], 1, MONEY_MAX), (BELOW_THRESHOLD, f["bandPercent"], 1, 100),
                  (NO_DESCRIPTION, f["minDescription"], 1, 255), (SELDOM_USED_ACCOUNT, f["seldomMax"], 0, COUNT_MAX),
                  (UNUSUAL_FLOW, f["flowMax"], 0, COUNT_MAX), (HIGH_VOLUME_USER, f["highVolumeMax"], 0, COUNT_MAX),
                  (MANY_LINES, f["manyLinesMax"], 0, 255), (BACKDATED, f["backdatedDays"], 0, DAY_MAX),
                  (DUPLICATE_BILL, f["duplicateWindowDays"], 0, DAY_MAX), (SPLIT_ORDER, f["approvalThreshold"], 1, MONEY_MAX),
                  (SPLIT_ORDER, f["splitWindowDays"], 1, DAY_MAX))
        if any(has(mask, k) and not lo <= v <= hi for k, v, lo, hi in bounds):
            return None
        if not 1 <= f["benfordMinimum"] <= MONEY_MAX:
            return None
        if any(len(f[k]) > LIST_MAX for k in ("weekendDays", "holidays", "keywords", "accounts", "users", "approvers", "leavers", "pairs")):
            return None
        wd = f["weekendDays"]
        if any(d > 6 for d in wd) or len(set(wd)) != len(wd):
            return None
        items = []
        hs = f["holidays"]
        if any(not day_fits(d) for d in hs) or len(set(hs)) != len(hs):
            return None
        items += [("holiday", d, NOBODY, bytes(CODE), bytes(CODE), nat_key(d)) for d in hs]
        kws = [ascii_lower(stripped(k)) for k in f["keywords"]]
        if any(not ascii_word(k) for k in kws) or len(set(kws)) != len(kws):
            return None
        items += [("keyword", 0, NOBODY, text_field(k, CODE), bytes(CODE), text_field(k, CODE) + bytes(CODE)) for k in kws]
        accts = f["accounts"]
        if any(a not in store.ledger.accounts or store.ledger.accounts[a]["companyId"] != f["companyId"] for a in accts) or len(set(accts)) != len(accts):
            return None
        items += [("account", a, NOBODY, bytes(CODE), bytes(CODE), nat_key(a)) for a in accts]
        for lst, ps in (("user", f["users"]), ("approver", f["approvers"])):
            if len(set(ps)) != len(ps):
                return None
            items += [(lst, 0, p, bytes(CODE), bytes(CODE), principal_key(p)) for p in ps]
        lv = f["leavers"]
        if any(not day_fits(d) for _p, d in lv) or len({p for p, _d in lv}) != len(lv):
            return None
        items += [("leaver", d, p, bytes(CODE), bytes(CODE), principal_key(p)) for p, d in lv]
        prs = f["pairs"]
        if any(not ascii_word(a) or not ascii_word(b) for a, b in prs) or len(set(prs)) != len(prs):
            return None
        items += [("pair", 0, NOBODY, text_field(a, CODE), text_field(b, CODE), text_field(a, CODE) + text_field(b, CODE)) for a, b in prs]
        sc = f["screeners"]
        # the auditor holds no act, so it never screens
        if not sc or len(set(sc)) != len(sc) or any(r not in ROLES or ROLES[r] in NO_ACT for r in sc):
            return None
        cur = f["currency"].strip(" ")
        if not cur or len(cur.encode("utf-8")) > CURRENCY or cur.encode("utf-8").endswith(b"\x00"):
            return None
        return mask, sum(1 << d for d in wd), items, sum(ROLE_BIT[ROLES[r]] for r in sc), text_field(cur, CURRENCY)

    # -- the fold --

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx, day = block["index"], block["day"]
        caller = bytes(block["caller"])

        def fault(what):
            self.faults.append("block %d %s" % (idx, what))

        def officer(co):
            return self.role_in_standing(store, co, caller) in ("CompanyAdmin", "Director")

        if f == "setControlProfile":
            fc = c["facts"]
            co = fc["companyId"]
            got = self.profile_valid(store, fc) if officer(co) else None
            if got is None:
                fault("recorded a screening profile it could not")
                return
            mask, weekend, items, screeners, currency = got
            used = lambda k, v: v if has(mask, k) else 0  # noqa: E731
            s = self.standings.get(co)
            version = s["version"] + 1 if s else 1
            pid = self.next["profile"]
            self.next["profile"] += 1
            sizes = {lst: sum(1 for x in items if x[0] == lst) for lst in LIST_BYTE}
            self.profiles[pid] = {
                "companyId": co, "version": version, "criteria": mask, "periodEndDays": used(PERIOD_END, fc["periodEndDays"]),
                "roundBase": used(ROUND_AMOUNT, fc["roundBase"]), "roundMinimum": used(ROUND_AMOUNT, fc["roundMinimum"]),
                "largeThreshold": used(LARGE_AMOUNT, fc["largeThreshold"]),
                "approvalThreshold": fc["approvalThreshold"] if has(mask, BELOW_THRESHOLD) or has(mask, SPLIT_ORDER) else 0,
                "bandPercent": used(BELOW_THRESHOLD, fc["bandPercent"]), "weekend": used(WEEKEND_HOLIDAY, weekend),
                "minDescription": used(NO_DESCRIPTION, fc["minDescription"]), "seldomMax": used(SELDOM_USED_ACCOUNT, fc["seldomMax"]),
                "flowMax": used(UNUSUAL_FLOW, fc["flowMax"]), "highVolumeMax": used(HIGH_VOLUME_USER, fc["highVolumeMax"]),
                "manyLinesMax": used(MANY_LINES, fc["manyLinesMax"]), "backdatedDays": used(BACKDATED, fc["backdatedDays"]),
                "duplicateWindowDays": used(DUPLICATE_BILL, fc["duplicateWindowDays"]),
                "splitWindowDays": used(SPLIT_ORDER, fc["splitWindowDays"]), "benfordMinimum": fc["benfordMinimum"],
                "screeners": screeners, "holidays": sizes["holiday"], "keywords": sizes["keyword"], "accounts": sizes["account"],
                "users": sizes["user"], "approvers": sizes["approver"], "leavers": sizes["leaver"], "pairs": sizes["pair"],
                "currency": currency, "setBy": caller, "day": day, "lastBlock": idx}
            ordinals = {}
            for lst, nat, principal, first, second, key in items:
                ordinals[lst] = ordinals.get(lst, 0) + 1
                self.items[self.next["item"]] = {"profileId": pid, "list": lst, "ordinal": ordinals[lst], "nat": nat,
                                                 "principal": principal, "first": first, "second": second, "key": key, "lastBlock": idx}
                self.next["item"] += 1
            self.standings[co] = {"profileId": pid, "version": version, "openRunId": s["openRunId"] if s else 0, "lastBlock": idx}
            return

        if f == "openScreening":
            fc = c["facts"]
            co = fc["companyId"]
            pid, prof = self.profile_in_force(co)
            role = self.role_in_standing(store, co, caller)
            if (prof is None or role is None or not prof["screeners"] & ROLE_BIT[role] or not day_fits(fc["fromDay"])
                    or not day_fits(fc["throughDay"]) or fc["fromDay"] > fc["throughDay"] or self.standings[co]["openRunId"] != 0):
                fault("opened a screening run it could not")
                return
            rid = self.next["run"]
            self.next["run"] += 1
            self.runs[rid] = {"companyId": co, "profileId": pid, "fromDay": fc["fromDay"], "throughDay": fc["throughDay"],
                              "phase": "facts", "cursorDay": fc["fromDay"], "cursorId": 0, "openedBlock": idx,
                              "billBound": store.payments.next_bill, "orderBound": store.credit.next_order,
                              "moves": 0, "lines": 0, "unrecorded": 0, "flagged": 0, "byCriterion": [0] * CRITERIA,
                              "bills": 0, "orders": 0, "foreign": 0, "findings": 0, "open": 0, "confirmed": 0, "benfordCount": 0,
                              "madE10": 0, "band": 0, "chiE2": 0, "openedBy": caller, "openedDay": day, "sealedBlock": 0,
                              "tip": ZERO32, "hash": ZERO32, "chain": ZERO32, "lastBlock": idx}
            self.standings[co].update(openRunId=rid, lastBlock=idx)
            return

        if f == "screenSlice":
            co, rid, limit = c["companyId"], c["runId"], c["limit"]
            run = self.runs.get(rid)
            role = self.role_in_standing(store, co, caller)
            if (not 1 <= limit <= MAX_LIMIT or role is None or run is None or run["companyId"] != co or run["phase"] == "done"
                    or not self.profiles[run["profileId"]]["screeners"] & ROLE_BIT[role]):
                fault("took a slice of a run it could not")
                return
            self.slices += 1
            self._slice(block, store, rid, run, limit)
            return

        if f == "concludeFinding":
            co = c["companyId"]
            _pid, prof = self.profile_in_force(co)
            role = self.role_in_standing(store, co, caller)
            x = self.findings.get(c["findingId"])
            run = self.runs.get(x["runId"]) if x else None
            matcher = None
            if x is not None and x["kind"] == "bill":
                b = store.payments.bills.get(x["subjectId"])
                matcher = b.get("matchedBy") if b and b["state"] == "matched" else None
            if (prof is None or role is None or not prof["screeners"] & ROLE_BIT[role] or x is None or x["companyId"] != co
                    or run["phase"] != "done" or x["state"] != "open" or caller in (x["preparer"], x["poster"], matcher)
                    or not stripped(c["note"]) or len(c["note"]) > MAX_TEXT):
                fault("concluded a finding it could not")
                return
            x.update(state="confirmed" if c["confirmed"] else "cleared", concludedBy=caller, note=c["note"], concludedDay=day, lastBlock=idx)
            run["open"] -= 1
            run["confirmed"] += 1 if c["confirmed"] else 0
            run["lastBlock"] = idx
            return

        if f == "defineControlProcedure":
            fc = c["facts"]
            co = fc["companyId"]
            code = crm_normalise(fc["code"])
            field = text_field(code, CODE) if code else None
            if (not officer(co) or field is None or code.encode("utf-8").endswith(b"\x00")
                    or any(p["companyId"] == co and p["code"] == field for p in self.procedures.values())
                    or not stripped(fc["title"]) or len(fc["title"]) > MAX_TEXT or fc["component"] not in COMPONENTS):
                fault("defined a control procedure it could not")
                return
            self.procedures[self.next["procedure"]] = {"companyId": co, "code": field, "title": fc["title"], "component": fc["component"],
                                                       "screening": fc["screening"], "conclusions": 0, "definedBy": caller,
                                                       "day": day, "lastBlock": idx}
            self.next["procedure"] += 1
            return

        if f == "prepareControlConclusion":
            fc = c["facts"]
            co = fc["companyId"]
            role = self.role_in_standing(store, co, caller)
            proc = self.procedures.get(fc["procedureId"])
            ok = (role is not None and role != "Employee" and proc is not None and proc["companyId"] == co
                  and day_fits(fc["fromDay"]) and day_fits(fc["throughDay"]) and fc["fromDay"] <= fc["throughDay"]
                  and fc["result"] in RESULTS and stripped(fc["note"]) and len(fc["note"]) <= MAX_TEXT
                  and not any(k["procedureId"] == fc["procedureId"] and (k["fromDay"], k["throughDay"]) == (fc["fromDay"], fc["throughDay"])
                              for k in self.conclusions.values()))
            if ok and proc["screening"]:
                run = self.runs.get(fc["runId"])
                ok = (run is not None and run["companyId"] == co and run["phase"] == "done"
                      and (run["fromDay"], run["throughDay"]) == (fc["fromDay"], fc["throughDay"])
                      and (RESULTS[fc["result"]] != "effective" or (run["open"] == 0 and run["confirmed"] == 0)))
            elif ok:
                ok = fc["runId"] == 0
            if not ok:
                fault("prepared a control conclusion it could not")
                return
            self.conclusions[self.next["conclusion"]] = {"companyId": co, "procedureId": fc["procedureId"], "fromDay": fc["fromDay"],
                                                         "throughDay": fc["throughDay"], "runId": fc["runId"], "result": fc["result"],
                                                         "note": fc["note"], "state": "prepared", "preparedBy": caller, "reviewedBy": caller,
                                                         "preparedDay": day, "reviewedDay": 0, "lastBlock": idx}
            self.next["conclusion"] += 1
            proc["conclusions"] += 1
            proc["lastBlock"] = idx
            return

        if f == "reviewControlConclusion":
            k = self.conclusions.get(c["conclusionId"])
            if not officer(c["companyId"]) or k is None or k["companyId"] != c["companyId"] or k["state"] != "prepared" or k["preparedBy"] == caller:
                fault("reviewed a control conclusion it could not")
                return
            k.update(state="reviewed", reviewedBy=caller, reviewedDay=day, lastBlock=idx)
            return

    # -- the slice --

    def _bump(self, rid, kind, key, idx):
        ck = (rid, kind, key)
        cid = self.count_of.get(ck)
        if cid is None:
            cid = self.count_of[ck] = self.next["count"]
            self.next["count"] += 1
            self.counts[cid] = {"runId": rid, "kind": kind, "key": key, "count": 0}
        self.counts[cid]["count"] += 1
        self.counts[cid]["lastBlock"] = idx

    def _count(self, rid, kind, key):
        cid = self.count_of.get((rid, kind, key))
        return self.counts[cid]["count"] if cid else 0

    def _finding(self, run, rid, kind, subject, criteria, amount, posting_day, preparer, poster, idx):
        self.findings[self.next["finding"]] = {"companyId": run["companyId"], "runId": rid, "kind": kind, "subjectId": subject,
                                               "criteria": criteria, "met": popcount(criteria), "amount": amount,
                                               "postingDay": posting_day, "preparer": preparer, "poster": poster, "state": "open",
                                               "concludedBy": preparer, "note": "", "concludedDay": 0, "lastBlock": idx}
        self.finding_of[(rid, kind, subject)] = self.next["finding"]
        self.next["finding"] += 1
        run["findings"] += 1
        run["open"] += 1
        for k in range(1, CRITERIA + 1):
            if has(criteria, k):
                run["byCriterion"][k - 1] += 1
        run["chain"] = hashlib.sha256(run["chain"] + bytes([SUBJECT_BYTE[kind]]) + nat_bytes(subject, ID) + nat_bytes(criteria, SEQUENCE)
                                      + nat_bytes(amount, MONEY) + nat_bytes(posting_day, DAY) + principal_field(preparer)
                                      + principal_field(poster)).digest()

    def _mark(self, rid, kind, key, day, subject, amount, idx):
        self.marks[self.next["mark"]] = {"runId": rid, "kind": kind, "key": key, "day": day, "subjectId": subject, "amount": amount, "lastBlock": idx}
        self.next["mark"] += 1

    def _marks(self, rid, kind, key, lo, hi):
        """Every mark of the run under a key with a day in [lo, hi], by day then subject."""
        return sorted((x for x in self.marks.values() if x["runId"] == rid and x["kind"] == kind and x["key"] == key and lo <= x["day"] <= hi),
                      key=lambda x: (x["day"], x["subjectId"]))

    def _criteria(self, store, rid, run, prof, mid, m, lines, posting, series):
        """The mask of the criteria a move meets, each restated from the design."""
        accounts = store.ledger.accounts
        pid = run["profileId"]
        on = lambda k: has(prof["criteria"], k)  # noqa: E731
        amounts = [v for l in lines for v in (l["debit"], l["credit"])]
        met = set()
        if posting is not None:
            pd = posting["postedDay"]
            through = run["throughDay"]
            met |= {k for k, b in ((PERIOD_END, abs(pd - through) <= prof["periodEndDays"]), (POST_CLOSE, pd > through),
                                   (SELF_APPROVED, posting["manual"] and m["postedBy"] == m["proposedBy"]),
                                   (WEEKEND_HOLIDAY, bool(prof["weekend"] & (1 << ((pd + 3) % 7))) or self.listed(pid, "holiday", nat_key(pd))),
                                   (MANUAL, posting["manual"]), (REVERSAL_AFTER_PERIOD, posting["reverses"] != 0 and pd > through),
                                   (BACKDATED, pd - m["businessDay"] > prof["backdatedDays"])) if b}
            leavers = {x["principal"]: x["nat"] for x in self.items_of(pid, "leaver")}
            if any(p in leavers and pd > leavers[p] for p in (m["proposedBy"], m["postedBy"])):
                met.add(LEAVER)
        if on(ROUND_AMOUNT) and any(v > 0 and v >= prof["roundMinimum"] and v % prof["roundBase"] == 0 for v in amounts):
            met.add(ROUND_AMOUNT)
        if on(LARGE_AMOUNT) and any(v >= prof["largeThreshold"] for v in amounts):
            met.add(LARGE_AMOUNT)
        if any(self.listed(pid, "account", nat_key(l["accountId"])) for l in lines):
            met.add(UNUSUAL_ACCOUNT)
        if self.listed(pid, "user", principal_key(m["proposedBy"])):
            met.add(UNUSUAL_USER)
        if on(NO_DESCRIPTION) and any(len(stripped(l.get("name", ""))) < prof["minDescription"] for l in lines):
            met.add(NO_DESCRIPTION)
        keywords = [text_of_field(x["first"]) for x in self.items_of(pid, "keyword")]
        if any(k in ascii_lower(l.get("name", "")) for l in lines for k in keywords):
            met.add(KEYWORD)
        if any(self._count(rid, "account", nat_key(l["accountId"])) <= prof["seldomMax"] for l in lines):
            met.add(SELDOM_USED_ACCOUNT)
        if self._count(rid, "fingerprint", fingerprint_of(lines)) >= 2:
            met.add(DUPLICATE)
        if self._count(rid, "flow", flow_of(lines)) <= prof["flowMax"]:
            met.add(UNUSUAL_FLOW)
        t = prof["approvalThreshold"]
        if any(0 < v < t and v * 100 >= t * (100 - prof["bandPercent"]) for v in amounts):
            met.add(BELOW_THRESHOLD)
        if not self.listed(pid, "approver", principal_key(m["postedBy"])):
            met.add(UNAUTHORISED_APPROVER)
        code = lambda l: accounts[l["accountId"]]["code"] if l["accountId"] in accounts else ""  # noqa: E731
        for x in self.items_of(pid, "pair"):
            dp, cp = text_of_field(x["first"]), text_of_field(x["second"])
            if any(l["debit"] > 0 and code(l).startswith(dp) for l in lines) and any(l["credit"] > 0 and code(l).startswith(cp) for l in lines):
                met.add(ACCOUNT_PAIR)
        if m["sequence"] > 1 and (m["journalId"], m["fiscalYear"], m["sequence"] - 1) not in series:
            met.add(SEQUENCE_GAP)
        if self._count(rid, "preparer", principal_key(m["proposedBy"])) > prof["highVolumeMax"]:
            met.add(HIGH_VOLUME_USER)
        if len(lines) > prof["manyLinesMax"]:
            met.add(MANY_LINES)
        if not stripped(m.get("ref", "")):
            met.add(NO_REFERENCE)
        self.criteria_restated += 1
        return sum(bit(k) for k in met if on(k))

    def _slice(self, block, store, rid, run, limit):
        idx = block["index"]
        ledger, payments, credit = store.ledger, store.payments, store.credit
        prof = self.profiles[run["profileId"]]
        co = run["companyId"]
        phase = run["phase"]
        if phase in ("facts", "screen"):
            lo = (run["cursorDay"], run["cursorId"])
            page = sorted((m["businessDay"], mid) for mid, m in ledger.moves.items()
                          if m["companyId"] == co and lo <= (m["businessDay"], mid) and m["businessDay"] <= run["throughDay"])[:limit]
            series = {(m["journalId"], m["fiscalYear"], m["sequence"]) for m in ledger.moves.values() if m["state"] == "posted"}
            for day, mid in page:
                run["cursorDay"], run["cursorId"] = day, mid + 1
                m = ledger.moves[mid]
                posting = self.postings.get(mid)
                if m["state"] != "posted" or (posting is not None and posting["lastBlock"] >= run["openedBlock"]):
                    continue
                lines = ledger.lines[mid]
                if phase == "facts":
                    run["moves"] += 1
                    run["lines"] += len(lines)
                    seen = []
                    for l in lines:
                        if l["accountId"] not in seen:
                            seen.append(l["accountId"])
                        for v in (l["debit"], l["credit"]):
                            if v > 0 and v >= prof["benfordMinimum"]:
                                self._bump(rid, "digits", nat_key(leading_two(v)), idx)
                                run["benfordCount"] += 1
                    for a in seen:
                        self._bump(rid, "account", nat_key(a), idx)
                    self._bump(rid, "fingerprint", fingerprint_of(lines), idx)
                    self._bump(rid, "flow", flow_of(lines), idx)
                    self._bump(rid, "preparer", principal_key(m["proposedBy"]), idx)
                    if posting is None:
                        run["unrecorded"] += 1
                else:
                    mask = self._criteria(store, rid, run, prof, mid, m, lines, posting, series)
                    if mask:
                        self._finding(run, rid, "move", mid, mask, sum(l["debit"] for l in lines), posting["postedDay"] if posting else 0,
                                      m["proposedBy"], m["postedBy"], idx)
                        run["flagged"] += 1
            if len(page) < limit:
                run["phase"] = "screen" if phase == "facts" else ("bills" if has(prof["criteria"], DUPLICATE_BILL) else
                                                                  "orders" if has(prof["criteria"], SPLIT_ORDER) else "done")
                run["cursorDay"] = run["fromDay"] if run["phase"] == "screen" else 0
                run["cursorId"] = 0
        elif phase == "bills":
            ids = [b for b in sorted(payments.bills) if max(run["cursorId"], 1) <= b <= run["billBound"] - 1]
            for bid in ids[:limit]:
                run["cursorId"] = bid + 1
                b = payments.bills[bid]
                if b["companyId"] == co and run["fromDay"] <= b["billDay"] <= run["throughDay"]:
                    self._bill(store, rid, run, prof, bid, b, idx)
            if len(ids) <= limit:
                run["phase"] = "orders" if has(prof["criteria"], SPLIT_ORDER) else "done"
                run["cursorDay"] = run["cursorId"] = 0
        elif phase == "orders":
            ids = [o for o in sorted(self.confirmations) if max(run["cursorId"], 1) <= o <= run["orderBound"] - 1]
            for oid in ids[:limit]:
                run["cursorId"] = oid + 1
                x = self.confirmations[oid]
                fc = credit.orders[oid]["facts"]
                if (x["companyId"] == co and x["lastBlock"] < run["openedBlock"] and fc["direction"] == "purchase"
                        and run["fromDay"] <= fc["orderDay"] <= run["throughDay"]):
                    key = order_key(fc["partnerId"], text_field(fc["currency"], CURRENCY))
                    if not any(m["runId"] == rid and m["kind"] == "orderSupplier" and m["subjectId"] == oid for m in self.marks.values()):
                        run["orders"] += 1
                        if text_field(fc["currency"], CURRENCY) != prof["currency"]:
                            run["foreign"] += 1
                        self._mark(rid, "orderSupplier", key, fc["orderDay"], oid, x["amount"], idx)
            if len(ids) <= limit:
                run["phase"] = "split"
                run["cursorDay"] = run["cursorId"] = 0
        elif phase == "split":
            ids = [i for i in sorted(self.marks) if self.marks[i]["runId"] == rid and i >= run["cursorId"]][:limit]
            t = prof["approvalThreshold"]

            def eligible(x):
                return x["kind"] == "orderSupplier" and 0 < x["amount"] < t and x["key"][ID:ID + CURRENCY] == prof["currency"]
            for i in ids:
                run["cursorId"] = i + 1
                x = self.marks[i]
                if not eligible(x):
                    continue
                window = [w for w in self._marks(rid, "orderSupplier", x["key"], max(x["day"] + 1 - prof["splitWindowDays"], 0), x["day"]) if eligible(w)]
                if len(window) < 2 or sum(w["amount"] for w in window) < t:
                    continue
                for w in window:
                    if (rid, "order", w["subjectId"]) not in self.finding_of:
                        o = credit.orders[w["subjectId"]]
                        conf = self.confirmations[w["subjectId"]]
                        self._finding(run, rid, "order", w["subjectId"], bit(SPLIT_ORDER), conf["amount"], o["facts"]["orderDay"],
                                      conf["confirmedBy"], conf["confirmedBy"], idx)
            if len(ids) < limit:
                run["phase"] = "done"
                run["cursorId"] = 0
        run["lastBlock"] = idx
        if run["phase"] == "done":
            counts = [self._count(rid, "digits", nat_key(d)) for d in range(10, 100)]
            run["madE10"], run["band"], run["chiE2"] = benford(counts, run["benfordCount"])
            run["sealedBlock"] = idx
            run["tip"] = bytes(block["parent"]) if block["parent"] is not None else ZERO32
            run["hash"] = self.run_hash(run)
            self.standings[co].update(openRunId=0, lastBlock=idx)

    def _bill(self, store, rid, run, prof, bid, b, idx):
        currency = text_field(b["currency"], CURRENCY)
        tkey = bill_total_key(b["partnerId"], currency, b["total"])
        if any(m["runId"] == rid and m["kind"] == "billTotal" and m["subjectId"] == bid for m in self.marks.values()):
            return
        run["bills"] += 1
        self._mark(rid, "billTotal", tkey, b["billDay"], bid, b["total"], idx)
        hits = []
        reference = normalised_reference(b["supplierRef"])
        if reference:
            rkey = bill_reference_key(b["partnerId"], reference)
            self._mark(rid, "billReference", rkey, b["billDay"], bid, b["total"], idx)
            hits += [x["subjectId"] for x in self._marks(rid, "billReference", rkey, 0, DAY_MAX)]
        w = prof["duplicateWindowDays"]
        hits += [x["subjectId"] for x in self._marks(rid, "billTotal", tkey, max(b["billDay"] - w, 0), min(b["billDay"] + w, DAY_MAX))]
        others = []
        for h in hits:
            if h != bid and h not in others:
                others.append(h)
        if not others:
            return
        for x in [bid] + others:
            if (rid, "bill", x) not in self.finding_of:
                y = store.payments.bills[x]
                self._finding(run, rid, "bill", x, bit(DUPLICATE_BILL), y["total"], y["billDay"], y["recordedBy"], y["recordedBy"], idx)

    @staticmethod
    def run_hash(r):
        body = (RUN_TAG + nat_bytes(r["companyId"], COMPANY) + nat_bytes(r["profileId"], ID) + nat_bytes(r["fromDay"], DAY)
                + nat_bytes(r["throughDay"], DAY) + nat_bytes(r["openedBlock"], BLOCK) + nat_bytes(r["billBound"], ID)
                + nat_bytes(r["orderBound"], ID)
                + b"".join(nat_bytes(r[k], SEQUENCE) for k in ("moves", "lines", "unrecorded", "flagged"))
                + b"".join(nat_bytes(x, SEQUENCE) for x in r["byCriterion"])
                + b"".join(nat_bytes(r[k], SEQUENCE) for k in ("bills", "orders", "foreign", "findings", "benfordCount"))
                + nat_bytes(r["madE10"], MONEY) + nat_bytes(r["band"], 1) + nat_bytes(r["chiE2"], MONEY)
                + nat_bytes(r["sealedBlock"], BLOCK) + r["tip"] + r["chain"])
        return hashlib.sha256(body).digest()

    # -- what the contract prints, restated --

    def lines(self):
        """Every row this reader holds, each as the export prints the contract's, by table and id."""
        n, h = str, lambda b: b.hex()  # noqa: E731
        flag = lambda b: "1" if b else "0"  # noqa: E731
        out = {k: {} for k in ("move_posting", "order_confirmation", "ctl_standing", "ctl_profile", "ctl_item", "ctl_run",
                               "ctl_count", "ctl_mark", "ctl_finding", "ctl_procedure", "ctl_conclusion")}

        def put(kind, i, *xs):
            out[kind][i] = "%s: %d %s" % (kind, i, " ".join(xs))
        for i, x in self.postings.items():
            put("move_posting", i, n(x["companyId"]), n(x["postedDay"]), flag(x["manual"]), n(x["reverses"]), n(x["lastBlock"]))
        for i, x in self.confirmations.items():
            put("order_confirmation", i, n(x["companyId"]), n(x["confirmedDay"]), n(x["lastBlock"]))
        for i, x in self.standings.items():
            put("ctl_standing", i, n(x["profileId"]), n(x["version"]), n(x["openRunId"]), n(x["lastBlock"]))
        for i, x in self.profiles.items():
            put("ctl_profile", i, *[n(x[k]) for k in ("companyId", "version", "criteria", "periodEndDays", "roundBase", "roundMinimum",
                                                      "largeThreshold", "approvalThreshold", "bandPercent", "weekend", "minDescription",
                                                      "seldomMax", "flowMax", "highVolumeMax", "manyLinesMax", "backdatedDays",
                                                      "duplicateWindowDays", "splitWindowDays", "benfordMinimum", "screeners", "holidays",
                                                      "keywords", "accounts", "users", "approvers", "leavers", "pairs")],
                h(x["currency"]), h(x["setBy"]), n(x["day"]), n(x["lastBlock"]))
        for i, x in self.items.items():
            put("ctl_item", i, n(x["profileId"]), n(LIST_BYTE[x["list"]]), n(x["ordinal"]), n(x["nat"]), h(x["principal"]),
                h(x["first"]), h(x["second"]), h(x["key"]), n(x["lastBlock"]))
        for i, x in self.runs.items():
            put("ctl_run", i, *[n(x[k]) for k in ("companyId", "profileId", "fromDay", "throughDay")], n(PHASE_BYTE[x["phase"]]),
                *[n(x[k]) for k in ("cursorDay", "cursorId", "openedBlock", "billBound", "orderBound", "moves", "lines", "unrecorded", "flagged")],
                ",".join(n(v) for v in x["byCriterion"]),
                *[n(x[k]) for k in ("bills", "orders", "foreign", "findings", "open", "confirmed", "benfordCount", "madE10", "band", "chiE2")],
                h(x["openedBy"]), n(x["openedDay"]), n(x["sealedBlock"]), h(x["tip"]), h(x["hash"]), h(x["chain"]), n(x["lastBlock"]))
        for i, x in self.counts.items():
            put("ctl_count", i, n(x["runId"]), n(FACT_BYTE[x["kind"]]), h(x["key"]), n(x["count"]), n(x["lastBlock"]))
        for i, x in self.marks.items():
            put("ctl_mark", i, n(x["runId"]), n(MARK_BYTE[x["kind"]]), h(x["key"]), n(x["day"]), n(x["subjectId"]), n(x["amount"]), n(x["lastBlock"]))
        for i, x in self.findings.items():
            put("ctl_finding", i, n(x["companyId"]), n(x["runId"]), n(SUBJECT_BYTE[x["kind"]]), n(x["subjectId"]), n(x["criteria"]), n(x["met"]),
                n(x["amount"]), n(x["postingDay"]), h(x["preparer"]), h(x["poster"]), n(FINDING_STATE_BYTE[x["state"]]), h(x["concludedBy"]),
                h(x["note"].encode("utf-8")), n(x["concludedDay"]), n(x["lastBlock"]))
        for i, x in self.procedures.items():
            put("ctl_procedure", i, n(x["companyId"]), h(x["code"]), h(x["title"].encode("utf-8")), n(x["component"]), flag(x["screening"]),
                n(x["conclusions"]), h(x["definedBy"]), n(x["day"]), n(x["lastBlock"]))
        for i, x in self.conclusions.items():
            put("ctl_conclusion", i, n(x["companyId"]), n(x["procedureId"]), n(x["fromDay"]), n(x["throughDay"]), n(x["runId"]), n(x["result"]),
                h(x["note"].encode("utf-8")), n(CONCLUSION_STATE_BYTE[x["state"]]), h(x["preparedBy"]), h(x["reviewedBy"]),
                n(x["preparedDay"]), n(x["reviewedDay"]), n(x["lastBlock"]))
        return out

    def summary(self):
        return {"postings": len(self.postings), "confirmations": len(self.confirmations), "profiles": len(self.profiles),
                "runs": len(self.runs), "sealed": sum(1 for r in self.runs.values() if r["phase"] == "done"),
                "slices": self.slices, "findings": len(self.findings), "criteria restated": self.criteria_restated,
                "procedures": len(self.procedures), "conclusions": len(self.conclusions), "faults": len(self.faults)}
