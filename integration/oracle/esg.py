"""The ESG families (615 to 624), decoded from their canonical bytes, re-encoded so the command hash can be re-derived,
and folded by rules written from the design:

  * A SET OF GLOBAL WARMING POTENTIALS AND EVERY VERSION OF A FACTOR NAME THEIR SOURCE - database, edition and the
    SHA-256 of the published file - and are recorded by a member in standing who is not an employee and approved,
    once, by an administrator or a director who did not record them. A factor version is weighed by an approved set
    of its company, every gas of it in the set and named once, and copies the set's GWPs; versions of a code are
    numbered from one and approved in order, so the version in force before a block is the newest approved earlier;
  * RULES ASSIGN A FACTOR CODE, set and retired by an administrator or a director: a posted line is matched by its
    partner and account, then its partner (an expense line only), then its account; an activity by its product and
    partner, then its product, then its partner. An expense line is always weighed or counted unassigned; an asset
    line only where a rule names its account;
  * AN ACTIVITY IS RECORDED by any member in standing on a day the period lock has not closed, and cancelled, while
    its day is open, by its recorder or an officer;
  * A RUN IS OPENED over a period the lock has closed, one open run a company, and walked in slices: the period's
    moves by day and id as the close walks them, every posted line of a move that is not a closing move weighed by
    the rule and the version standing before the block the run was opened in; then the activities by day and id; the
    slice whose activity walk comes up short seals it with the log's tip, a chain over its figures in key order and
    a hash over the run. Every mass, CO2e and energy is rounded half to even once per entry, the sign kept.

This reader walks every slice over its own ledger (the accounting reader's moves and lines) and its own activities,
restates every row of the seven tables and every sealed run's chain and hash, and every disclosure the contract
printed - the scopes, the gases, the energy within the organisation by one scope-2 method, and the seven answers of
the Financial Regulatory Authority's form, text for text.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import hashlib

from canonical import write_nat, write_text

DAY_LIMIT = 256 ** 3
CODE = 16
ESG_GAS = 32
ESG_UNIT = 24
CURRENCY_CODE = 4
QUANTITY_FITS = 256 ** 12
SET_GASES = 64
FACTOR_GASES = 16
MAX_TEXT = 4_000
MAX_LIMIT = 1_000
ID_MAX = 256 ** 6 - 1
QUANTITY_MAX = 2 ** 80
ENTRY_MAX = 2 ** 90
RECORDERS_NOT = {"Employee"}
OFFICERS = {"CompanyAdmin", "Director"}

# enumeration bytes, as src/Enums.mo stores them
SCOPE1, SCOPE2L, SCOPE2M, SCOPE3 = 1, 2, 3, 4
CATEGORY_MAX = {SCOPE1: 4, SCOPE2L: 0, SCOPE2M: 0, SCOPE3: 15}
MONETARY, PHYSICAL = 2, 1
SOURCE_NONE = 1
RENEWABLE = {7, 8, 9}
SOURCE_TEXT = {2: "coal", 3: "oil", 4: "natural gas", 5: "other fossil", 6: "nuclear", 7: "renewable fuel",
               8: "renewable, purchased", 9: "renewable, self-generated", 10: "grid, mix not declared"}
M_NONE, M_WATER_CONSUMED, M_WATER_RECYCLED, M_WASTE_GENERATED, M_WASTE_RECYCLED, M_WASTE_TREATED = 1, 2, 3, 4, 5, 6
K_EMISSION, K_ENERGY, K_WATER, K_WASTE, K_UNASSIGNED = 1, 2, 3, 4, 5
RECORDED, APPROVED = 1, 2
ACT_RECORDED, ACT_CANCELLED = 1, 2
PH_LINES, PH_ACTIVITIES, PH_SEALED = 1, 2, 3
OWNER_SET, OWNER_FACTOR = 1, 2
MISS_LINE_NO_RULE, MISS_LINE_NOT_IN_FORCE, MISS_LINE_NOT_SPEND = 1, 2, 3
MISS_ACTIVITY_NO_RULE, MISS_ACTIVITY_NOT_IN_FORCE, MISS_ACTIVITY_UNIT, MISS_ENTRY_TOO_LARGE = 4, 5, 6, 7
WASTE_HAZARDOUS, WASTE_NON_HAZARDOUS = 1, 2
ZERO32 = bytes(32)
RUN_TAG = b"mentat/esg/run/1"
TONNE = 10 ** 12
GIGAJOULE = 10 ** 6


def write_blob(b):
    return len(b).to_bytes(2, "big") + bytes(b)


def write_bool(b):
    return b"\x01" if b else b"\x00"


# ── the codec ────────────────────────────────────────────────────────────────

def read_gwp_set(r):
    f = {"companyId": r.nat(), "name": r.text(), "database": r.text(), "edition": r.text(), "sourceSha256": r.blob()}
    f["gases"] = [{"gas": r.text(), "group": r.nat8(), "gwpMilli": r.nat()} for _ in range(r.len16())]
    return f


def write_gwp_set(f):
    out = write_nat(f["companyId"]) + write_text(f["name"]) + write_text(f["database"]) + write_text(f["edition"]) + write_blob(f["sourceSha256"])
    out += len(f["gases"]).to_bytes(2, "big")
    for g in f["gases"]:
        out += write_text(g["gas"]) + bytes([g["group"]]) + write_nat(g["gwpMilli"])
    return out


def read_factor(r):
    f = {"companyId": r.nat(), "code": r.text(), "gwpSetId": r.nat(), "database": r.text(), "edition": r.text(),
         "sourceSha256": r.blob(), "reference": r.text(), "scope": r.nat8(), "category": r.nat(), "basis": r.nat8(),
         "unit": r.text(), "per": r.nat()}
    f["gases"] = [{"gas": r.text(), "micrograms": r.nat()} for _ in range(r.len16())]
    f["energySource"] = r.nat8()
    f["kilojoules"] = r.nat()
    return f


def write_factor(f):
    out = (write_nat(f["companyId"]) + write_text(f["code"]) + write_nat(f["gwpSetId"]) + write_text(f["database"])
           + write_text(f["edition"]) + write_blob(f["sourceSha256"]) + write_text(f["reference"]) + bytes([f["scope"]])
           + write_nat(f["category"]) + bytes([f["basis"]]) + write_text(f["unit"]) + write_nat(f["per"]))
    out += len(f["gases"]).to_bytes(2, "big")
    for g in f["gases"]:
        out += write_text(g["gas"]) + write_nat(g["micrograms"])
    return out + bytes([f["energySource"]]) + write_nat(f["kilojoules"])


def read_activity(r):
    return {"companyId": r.nat(), "day": r.nat(), "departmentId": r.nat(), "factorCode": r.text(), "productId": r.nat(),
            "partnerId": r.nat(), "quantity": r.nat(), "unit": r.text(), "measure": r.nat8(), "hazardous": r.bool(),
            "sourceMoveId": r.nat(), "note": r.text()}


def write_activity(f):
    return (write_nat(f["companyId"]) + write_nat(f["day"]) + write_nat(f["departmentId"]) + write_text(f["factorCode"])
            + write_nat(f["productId"]) + write_nat(f["partnerId"]) + write_nat(f["quantity"]) + write_text(f["unit"])
            + bytes([f["measure"]]) + write_bool(f["hazardous"]) + write_nat(f["sourceMoveId"]) + write_text(f["note"]))


READERS = {
    615: ("recordGwpSet", lambda r: {"facts": read_gwp_set(r)}),
    616: ("approveGwpSet", lambda r: {"companyId": r.nat(), "setId": r.nat()}),
    617: ("recordEsgFactor", lambda r: {"facts": read_factor(r)}),
    618: ("approveEsgFactor", lambda r: {"companyId": r.nat(), "factorId": r.nat()}),
    619: ("setEsgRule", lambda r: {"facts": {"companyId": r.nat(), "factorCode": r.text(), "productId": r.nat(),
                                             "partnerId": r.nat(), "accountId": r.nat()}}),
    620: ("retireEsgRule", lambda r: {"companyId": r.nat(), "ruleId": r.nat()}),
    621: ("recordEsgActivity", lambda r: {"facts": read_activity(r)}),
    622: ("cancelEsgActivity", lambda r: {"companyId": r.nat(), "activityId": r.nat()}),
    623: ("openEsgRun", lambda r: {"facts": {"companyId": r.nat(), "fromDay": r.nat(), "throughDay": r.nat()}}),
    624: ("esgRunSlice", lambda r: {"companyId": r.nat(), "runId": r.nat(), "limit": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_esg_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def _pair(a, b):
    return lambda c: write_nat(c[a]) + write_nat(c[b])


ENCODERS = {
    "recordGwpSet": (615, lambda c: write_gwp_set(c["facts"])),
    "approveGwpSet": (616, _pair("companyId", "setId")),
    "recordEsgFactor": (617, lambda c: write_factor(c["facts"])),
    "approveEsgFactor": (618, _pair("companyId", "factorId")),
    "setEsgRule": (619, lambda c: (write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["factorCode"]) + write_nat(c["facts"]["productId"])
                                   + write_nat(c["facts"]["partnerId"]) + write_nat(c["facts"]["accountId"]))),
    "retireEsgRule": (620, _pair("companyId", "ruleId")),
    "recordEsgActivity": (621, lambda c: write_activity(c["facts"])),
    "cancelEsgActivity": (622, _pair("companyId", "activityId")),
    "openEsgRun": (623, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["fromDay"]) + write_nat(c["facts"]["throughDay"])),
    "esgRunSlice": (624, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_nat(c["limit"])),
}


def esg_command_bytes(cmd):
    tag, enc = ENCODERS[cmd["family"]]
    return put_tag(tag) + enc(cmd)


# ── texts and fields, as the contract holds them ─────────────────────────────

def trimmed(t):
    return t.strip(" \t\n\r")


def normalise(t):
    return "".join(chr(ord(ch) + 32) if "A" <= ch <= "Z" else ch for ch in t).strip(" \t\n\r")


def field(t, width):
    """A text as a zero-padded field of `width` bytes, or None when it does not fit or would not read back as itself."""
    raw = t.encode("utf-8")
    if len(raw) > width or raw.endswith(b"\x00"):
        return None
    return raw + bytes(width - len(raw))


def code_field(code):
    t = normalise(code)
    return field(t, CODE) if t else None


def name_field(t0, width):
    t = trimmed(t0)
    return field(t, width) if t else None


def field_text(b):
    return b.rstrip(b"\x00").decode("utf-8")


def half_even(n, d):
    q, r = divmod(n, d)
    return q + 1 if 2 * r > d or (2 * r == d and q % 2 == 1) else q


def weigh(q, num, den):
    m = half_even(abs(q) * num, den)
    return -m if q < 0 else m


def zig(i):
    return 2 * i if i >= 0 else 2 * (-i) - 1


def decimal(v, den, places):
    scale = 10 ** places
    m = half_even(abs(v) * scale, den)
    frac = str(m % scale).rjust(places, "0")
    return ("-" if v < 0 and m > 0 else "") + str(m // scale) + ("." + frac if places > 0 else "")


def figure_key(run_id, kind, scope, category, detail, dept):
    return run_id.to_bytes(6, "big") + bytes([kind, scope, category, detail]) + dept.to_bytes(6, "big")


def chain_figure(prev, x):
    link = (prev + figure_key(x["runId"], x["kind"], x["scope"], x["category"], x["detail"], x["departmentId"])
            + zig(x["amount"]).to_bytes(16, "big") + zig(x["co2e"]).to_bytes(16, "big") + x["entries"].to_bytes(4, "big"))
    assert len(link) == 84
    return hashlib.sha256(link).digest()


def run_hash(x):
    b = (RUN_TAG + x["companyId"].to_bytes(6, "big") + x["fromDay"].to_bytes(3, "big") + x["throughDay"].to_bytes(3, "big")
         + x["openedBlock"].to_bytes(6, "big"))
    for k in ("lines", "linesAssigned", "activities", "activitiesAssigned", "activitiesMeasured", "figures"):
        b += x[k].to_bytes(4, "big")
    b += x["sealedBlock"].to_bytes(6, "big") + x["tip"] + x["chain"]
    assert len(b) == 128
    return hashlib.sha256(b).digest()


class Esg:
    def __init__(self):
        self.sets = {}
        self.gases = {}
        self.factors = {}
        self.rules = {}
        self.activities = {}
        self.runs = {}
        self.figures = {}
        self.next = {"set": 1, "gas": 1, "factor": 1, "rule": 1, "activity": 1, "run": 1, "figure": 1}
        self.faults = []
        self.lines_weighed = 0
        self.activities_weighed = 0
        self.slices = 0
        self.sealed = 0

    def take(self, kind):
        i = self.next[kind]
        self.next[kind] += 1
        return i

    # ── reads, as the contract's indexes give them ──────────────────────────

    def gases_of(self, kind, owner):
        return sorted((g for g in self.gases.values() if g["ownerKind"] == kind and g["ownerId"] == owner), key=lambda g: g["ordinal"])

    def gas_of(self, kind, owner, name):
        for g in self.gases.values():
            if g["ownerKind"] == kind and g["ownerId"] == owner and g["gas"] == name:
                return g
        return None

    def versions(self, co, code):
        """A code's versions, newest first."""
        return sorted((x for x in self.factors.values() if x["companyId"] == co and x["code"] == code), key=lambda x: -x["version"])

    def in_force(self, co, code, block):
        for x in self.versions(co, code):
            if x["state"] == APPROVED and x["approvedBlock"] < block:
                return x
        return None

    def rule_at(self, co, product, partner, account, block):
        for rid in sorted(self.rules):
            x = self.rules[rid]
            if ((x["companyId"], x["productId"], x["partnerId"], x["accountId"]) == (co, product, partner, account)
                    and x["createdBlock"] < block and (x["retiredBlock"] == 0 or x["retiredBlock"] >= block)):
                return x
        return None

    def line_rule(self, co, partner, account, expense, block):
        if partner != 0:
            r = self.rule_at(co, 0, partner, account, block)
            if r is not None:
                return r
            if expense:
                r = self.rule_at(co, 0, partner, 0, block)
                if r is not None:
                    return r
        return self.rule_at(co, 0, 0, account, block)

    def activity_rule(self, co, product, partner, block):
        if product != 0 and partner != 0:
            r = self.rule_at(co, product, partner, 0, block)
            if r is not None:
                return r
        if product != 0:
            r = self.rule_at(co, product, 0, 0, block)
            if r is not None:
                return r
        if partner != 0:
            return self.rule_at(co, 0, partner, 0, block)
        return None

    def figures_in_key_order(self, run_id):
        return sorted((x for x in self.figures.values() if x["runId"] == run_id),
                      key=lambda x: figure_key(x["runId"], x["kind"], x["scope"], x["category"], x["detail"], x["departmentId"]))

    # ── the fold ────────────────────────────────────────────────────────────

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = bytes(block["caller"])

        def role(co):
            d = store.discuss
            if co not in store.companies or not d.is_member(co, caller) or (co, caller) in d.suspended:
                return None
            return d.roles.get((co, caller))

        def recorder(co):
            r = role(co)
            return r is not None and r not in RECORDERS_NOT

        def officer(co):
            return role(co) in OFFICERS

        def lock(co):
            return store.ledger.locks.get(co, 0)

        def product_of(co, pid):
            return store.stock.categories.get(pid) == co

        def partner_of(co, pid):
            p = store.credit.partners.get(pid)
            return p is not None and p["companyId"] == co

        def department_of(co, did):
            d = store.discuss.departments.get(did)
            return d is not None and d["open"] and d["companyId"] == co

        def source_ok(fc):
            return trimmed(fc["database"]) != "" and trimmed(fc["edition"]) != "" and len(fc["sourceSha256"]) == 32

        def refused(why):
            self.faults.append("block %d accepted %s, which %s" % (idx, f, why))

        if f == "recordGwpSet":
            fc = c["facts"]
            co = fc["companyId"]
            if not recorder(co):
                return refused("no member in standing who records could send")
            if trimmed(fc["name"]) == "" or not source_ok(fc) or not 0 < len(fc["gases"]) <= SET_GASES:
                return refused("names no set, no source, or no gases it could hold")
            names = []
            for g in fc["gases"]:
                b = name_field(g["gas"], ESG_GAS)
                if b is None or b in names or g["gwpMilli"] >= QUANTITY_FITS:
                    return refused("names a gas it could not hold, or twice")
                names.append(b)
            if any(len(t) > MAX_TEXT for t in (trimmed(fc["name"]), trimmed(fc["database"]), trimmed(fc["edition"]))):
                return refused("carries a text past its bound")
            sid = self.take("set")
            self.sets[sid] = {"id": sid, "companyId": co, "name": trimmed(fc["name"]), "database": trimmed(fc["database"]),
                              "edition": trimmed(fc["edition"]), "sourceSha256": bytes(fc["sourceSha256"]), "gases": len(fc["gases"]),
                              "state": RECORDED, "recordedBy": caller, "approvedBy": caller, "recordedDay": day, "approvedDay": 0,
                              "approvedBlock": 0, "lastBlock": idx}
            for k, g in enumerate(fc["gases"]):
                gid = self.take("gas")
                self.gases[gid] = {"id": gid, "companyId": co, "ownerKind": OWNER_SET, "ownerId": sid, "ordinal": k, "gas": names[k],
                                   "group": g["group"], "micrograms": 0, "gwpMilli": g["gwpMilli"], "lastBlock": idx}

        elif f == "approveGwpSet":
            co = c["companyId"]
            x = self.sets.get(c["setId"])
            if not officer(co) or x is None or x["companyId"] != co or x["state"] != RECORDED or x["recordedBy"] == caller:
                return refused("approves no recorded set of the company, or by one who could not")
            x.update(state=APPROVED, approvedBy=caller, approvedDay=day, approvedBlock=idx, lastBlock=idx)

        elif f == "recordEsgFactor":
            fc = c["facts"]
            co = fc["companyId"]
            code = code_field(fc["code"])
            s = self.sets.get(fc["gwpSetId"])
            if not recorder(co) or code is None:
                return refused("no recorder could send, or names no code")
            if s is None or s["companyId"] != co or s["state"] != APPROVED:
                return refused("names no approved GWP set of the company")
            if not source_ok(fc) or trimmed(fc["reference"]) == "" or fc["category"] > CATEGORY_MAX[fc["scope"]]:
                return refused("names no source or a category its scope has not")
            if fc["basis"] == MONETARY:
                unit = name_field(fc["unit"], CURRENCY_CODE) and name_field(fc["unit"], ESG_UNIT)
            else:
                unit = name_field(fc["unit"], ESG_UNIT)
            if not unit:
                return refused("names no unit it could hold")
            if fc["per"] == 0 or fc["per"] >= QUANTITY_FITS or fc["kilojoules"] >= QUANTITY_FITS or len(fc["gases"]) > FACTOR_GASES:
                return refused("is per nothing, or past its bounds")
            if (not fc["gases"] and fc["kilojoules"] == 0) or ((fc["kilojoules"] > 0) != (fc["energySource"] != SOURCE_NONE)):
                return refused("weighs nothing, or carries energy without its source or a source without energy")
            parts = []
            for g in fc["gases"]:
                b = name_field(g["gas"], ESG_GAS)
                sg = self.gas_of(OWNER_SET, s["id"], b) if b is not None else None
                if b is None or any(p[0] == b for p in parts) or sg is None or g["micrograms"] >= QUANTITY_FITS:
                    return refused("names a gas not in its set, or twice")
                parts.append((b, sg, g["micrograms"]))
            vs = self.versions(co, code)
            fid = self.take("factor")
            self.factors[fid] = {"id": fid, "companyId": co, "code": code, "version": vs[0]["version"] + 1 if vs else 1,
                                 "gwpSetId": s["id"], "database": trimmed(fc["database"]), "edition": trimmed(fc["edition"]),
                                 "reference": trimmed(fc["reference"]), "sourceSha256": bytes(fc["sourceSha256"]), "scope": fc["scope"],
                                 "category": fc["category"], "basis": fc["basis"], "unit": unit, "per": fc["per"], "gases": len(fc["gases"]),
                                 "energySource": fc["energySource"], "kilojoules": fc["kilojoules"], "state": RECORDED,
                                 "recordedBy": caller, "approvedBy": caller, "recordedDay": day, "approvedDay": 0, "approvedBlock": 0,
                                 "lastBlock": idx}
            for k, (b, sg, mg) in enumerate(parts):
                gid = self.take("gas")
                self.gases[gid] = {"id": gid, "companyId": co, "ownerKind": OWNER_FACTOR, "ownerId": fid, "ordinal": k, "gas": b,
                                   "group": sg["group"], "micrograms": mg, "gwpMilli": sg["gwpMilli"], "lastBlock": idx}

        elif f == "approveEsgFactor":
            co = c["companyId"]
            x = self.factors.get(c["factorId"])
            if not officer(co) or x is None or x["companyId"] != co or x["state"] != RECORDED or x["recordedBy"] == caller:
                return refused("approves no recorded version of the company, or by one who could not")
            if any(v["state"] == APPROVED and v["version"] > x["version"] for v in self.versions(co, x["code"])):
                return refused("approves a version older than one approved")
            x.update(state=APPROVED, approvedBy=caller, approvedDay=day, approvedBlock=idx, lastBlock=idx)

        elif f == "setEsgRule":
            fc = c["facts"]
            co = fc["companyId"]
            code = code_field(fc["factorCode"])
            if not officer(co) or code is None or not self.versions(co, code):
                return refused("no officer sent it, or names no recorded code")
            pr, pa, ac = fc["productId"], fc["partnerId"], fc["accountId"]
            if (pr, pa, ac) == (0, 0, 0) or (pr and ac) or (pr and not product_of(co, pr)) or (pa and not partner_of(co, pa)):
                return refused("matches nothing, a product with an account, or a product or partner not of the company")
            if ac:
                a = store.ledger.accounts.get(ac)
                if a is None or a["companyId"] != co or a["accountType"] not in ("expense", "asset"):
                    return refused("names no expense or asset account of the company")
            if any((r["companyId"], r["productId"], r["partnerId"], r["accountId"]) == (co, pr, pa, ac) and r["retiredBlock"] == 0
                   for r in self.rules.values()):
                return refused("sets a second rule standing for the same keys")
            rid = self.take("rule")
            self.rules[rid] = {"id": rid, "companyId": co, "factorCode": code, "productId": pr, "partnerId": pa, "accountId": ac,
                               "createdBlock": idx, "retiredBlock": 0, "createdBy": caller, "retiredBy": caller, "day": day, "lastBlock": idx}

        elif f == "retireEsgRule":
            co = c["companyId"]
            x = self.rules.get(c["ruleId"])
            if not officer(co) or x is None or x["companyId"] != co or x["retiredBlock"] != 0:
                return refused("retires no standing rule of the company, or by one who could not")
            x.update(retiredBlock=idx, retiredBy=caller, lastBlock=idx)

        elif f == "recordEsgActivity":
            fc = c["facts"]
            co = fc["companyId"]
            if role(co) is None:
                return refused("no member in standing sent it")
            if not 1 <= fc["day"] < DAY_LIMIT or fc["day"] <= lock(co):
                return refused("is dated out of range or inside the period lock")
            if fc["departmentId"] and not department_of(co, fc["departmentId"]):
                return refused("names no open department of the company")
            named = normalise(fc["factorCode"]) != ""
            if named:
                code = code_field(fc["factorCode"])
                if code is None or not self.versions(co, code):
                    return refused("names a code with no recorded version")
            else:
                code = bytes(CODE)
            if (fc["productId"] and not product_of(co, fc["productId"])) or (fc["partnerId"] and not partner_of(co, fc["partnerId"])):
                return refused("names a product or a partner not of the company")
            if not named and not fc["productId"] and not fc["partnerId"] and fc["measure"] == M_NONE:
                return refused("weighs and measures nothing")
            if not 0 < fc["quantity"] < QUANTITY_MAX:
                return refused("carries no quantity, or one past its bound")
            unit = name_field(fc["unit"], ESG_UNIT)
            want = {M_WATER_CONSUMED: "L", M_WATER_RECYCLED: "L", M_WASTE_GENERATED: "kg", M_WASTE_RECYCLED: "kg", M_WASTE_TREATED: "kg"}.get(fc["measure"])
            if unit is None or (want is not None and trimmed(fc["unit"]) != want):
                return refused("is in no unit, or a measure in another unit than its own")
            if fc["hazardous"] and fc["measure"] not in (M_WASTE_GENERATED, M_WASTE_RECYCLED, M_WASTE_TREATED):
                return refused("is hazardous and not waste")
            if fc["sourceMoveId"]:
                m = store.ledger.moves.get(fc["sourceMoveId"])
                if m is None or m["companyId"] != co or m["state"] != "posted":
                    return refused("names no posted move of the company")
            if len(fc["note"]) > MAX_TEXT:
                return refused("carries a note past its bound")
            aid = self.take("activity")
            self.activities[aid] = {"id": aid, "companyId": co, "day": fc["day"], "departmentId": fc["departmentId"], "factorCode": code,
                                    "productId": fc["productId"], "partnerId": fc["partnerId"], "quantity": fc["quantity"], "unit": unit,
                                    "measure": fc["measure"], "hazardous": fc["hazardous"], "sourceMoveId": fc["sourceMoveId"],
                                    "note": fc["note"], "state": ACT_RECORDED, "recordedBy": caller, "recordedDay": day, "lastBlock": idx}

        elif f == "cancelEsgActivity":
            co = c["companyId"]
            r = role(co)
            x = self.activities.get(c["activityId"])
            if r is None or x is None or x["companyId"] != co or x["state"] != ACT_RECORDED:
                return refused("cancels no recorded activity of the company")
            if x["recordedBy"] != caller and r not in OFFICERS:
                return refused("was sent by neither its recorder nor an officer")
            if x["day"] <= lock(co):
                return refused("cancels an activity of a locked day")
            x.update(state=ACT_CANCELLED, lastBlock=idx)

        elif f == "openEsgRun":
            fc = c["facts"]
            co = fc["companyId"]
            if not recorder(co):
                return refused("no recorder sent it")
            if not (1 <= fc["fromDay"] <= fc["throughDay"] < DAY_LIMIT) or fc["throughDay"] > lock(co):
                return refused("is no period, or one past the period lock")
            if any(r["companyId"] == co and r["phase"] != PH_SEALED for r in self.runs.values()):
                return refused("opens a second run while one is open")
            rid = self.take("run")
            self.runs[rid] = {"id": rid, "companyId": co, "fromDay": fc["fromDay"], "throughDay": fc["throughDay"], "phase": PH_LINES,
                              "cursorDay": fc["fromDay"], "cursorId": 0, "openedBlock": idx, "openedBy": caller, "openedDay": day,
                              "lines": 0, "linesAssigned": 0, "activities": 0, "activitiesAssigned": 0, "activitiesMeasured": 0,
                              "figures": 0, "sealedBlock": 0, "tip": ZERO32, "chain": ZERO32, "hash": ZERO32, "lastBlock": idx}

        elif f == "esgRunSlice":
            co = c["companyId"]
            run = self.runs.get(c["runId"])
            if not 1 <= c["limit"] <= MAX_LIMIT or not recorder(co) or run is None or run["companyId"] != co or run["phase"] == PH_SEALED:
                return refused("slices no open run of the company, or by one who could not")
            self.slice(run, c["limit"], idx, block["parent"] or ZERO32, store)

    # ── one slice ────────────────────────────────────────────────────────────

    def add(self, run, kind, scope, category, detail, dept, amount, co2e, idx):
        key = (kind, scope, category, detail, dept)
        for x in self.figures.values():
            if x["runId"] == run["id"] and (x["kind"], x["scope"], x["category"], x["detail"], x["departmentId"]) == key:
                x["amount"] += amount
                x["co2e"] += co2e
                x["entries"] += 1
                x["lastBlock"] = idx
                return
        fid = self.take("figure")
        self.figures[fid] = {"id": fid, "runId": run["id"], "companyId": run["companyId"], "kind": kind, "scope": scope,
                             "category": category, "detail": detail, "departmentId": dept, "amount": amount, "co2e": co2e,
                             "entries": 1, "lastBlock": idx}
        run["figures"] += 1

    def weigh_entry(self, run, x, q, dept, idx):
        parts = []
        for g in self.gases_of(OWNER_FACTOR, x["id"]):
            mass = weigh(q, g["micrograms"], x["per"])
            parts.append((g, mass, weigh(mass, g["gwpMilli"], 1000)))
        energy = weigh(q, x["kilojoules"], x["per"])
        if abs(energy) > ENTRY_MAX or any(abs(m) > ENTRY_MAX or abs(e) > ENTRY_MAX for _g, m, e in parts):
            self.add(run, K_UNASSIGNED, 0, 0, MISS_ENTRY_TOO_LARGE, dept, q, 0, idx)
            return False
        for g, mass, co2e in parts:
            self.add(run, K_EMISSION, x["scope"], x["category"], g["group"], dept, mass, co2e, idx)
        if x["kilojoules"] > 0:
            self.add(run, K_ENERGY, x["scope"], x["category"], x["energySource"], dept, energy, 0, idx)
        return True

    def slice(self, run, limit, idx, tip, store):
        self.slices += 1
        co = run["companyId"]
        ledger = store.ledger
        if run["phase"] == PH_LINES:
            lo = (run["cursorDay"], run["cursorId"])
            page = sorted((m["businessDay"], mid) for mid, m in ledger.moves.items()
                          if m["companyId"] == co and lo <= (m["businessDay"], mid) and m["businessDay"] <= run["throughDay"])[:limit]
            for d, mid in page:
                run["cursorDay"], run["cursorId"] = d, mid + 1
                m = ledger.moves[mid]
                if m["state"] != "posted" or m["moveType"] == "closing":
                    continue
                for l in ledger.lines[mid]:
                    a = ledger.accounts[l["accountId"]]
                    expense = a["accountType"] == "expense"
                    partner = l["partnerId"] if l["partnerId"] else m["partnerId"]
                    rule = self.line_rule(co, partner, l["accountId"], expense, run["openedBlock"]) if expense or a["accountType"] == "asset" else None
                    if not expense and rule is None:
                        continue
                    run["lines"] += 1
                    self.lines_weighed += 1
                    net = l["debit"] - l["credit"]
                    amount = net if l["amountCurrency"] == 0 else (-l["amountCurrency"] if net < 0 else l["amountCurrency"])
                    if rule is None:
                        self.add(run, K_UNASSIGNED, 0, 0, MISS_LINE_NO_RULE, 0, amount, 0, idx)
                        continue
                    x = self.in_force(co, rule["factorCode"], run["openedBlock"])
                    if x is None:
                        self.add(run, K_UNASSIGNED, 0, 0, MISS_LINE_NOT_IN_FORCE, 0, amount, 0, idx)
                    elif x["basis"] != MONETARY or field_text(x["unit"]) != m["currency"]:
                        self.add(run, K_UNASSIGNED, 0, 0, MISS_LINE_NOT_SPEND, 0, amount, 0, idx)
                    elif self.weigh_entry(run, x, amount, 0, idx):
                        run["linesAssigned"] += 1
            if len(page) < limit:
                run["phase"], run["cursorDay"], run["cursorId"] = PH_ACTIVITIES, run["fromDay"], 0
        elif run["phase"] == PH_ACTIVITIES:
            lo = (run["cursorDay"], run["cursorId"])
            page = sorted((a["day"], aid) for aid, a in self.activities.items()
                          if a["companyId"] == co and lo <= (a["day"], aid) and a["day"] <= run["throughDay"])[:limit]
            for d, aid in page:
                run["cursorDay"], run["cursorId"] = d, aid + 1
                self.weigh_activity(run, self.activities[aid], idx)
            if len(page) < limit:
                run["phase"], run["cursorDay"], run["cursorId"] = PH_SEALED, run["throughDay"], 0
        run["lastBlock"] = idx
        if run["phase"] == PH_SEALED:
            chain = ZERO32
            for x in self.figures_in_key_order(run["id"]):
                chain = chain_figure(chain, x)
            run.update(sealedBlock=idx, tip=bytes(tip), chain=chain)
            run["hash"] = run_hash(run)
            self.sealed += 1

    def weigh_activity(self, run, x, idx):
        if x["state"] != ACT_RECORDED:
            return
        run["activities"] += 1
        self.activities_weighed += 1
        q = x["quantity"]
        dept = x["departmentId"]
        if x["measure"] in (M_WATER_CONSUMED, M_WATER_RECYCLED):
            self.add(run, K_WATER, 0, x["measure"], 0, dept, q, 0, idx)
            run["activitiesMeasured"] += 1
        elif x["measure"] in (M_WASTE_GENERATED, M_WASTE_RECYCLED, M_WASTE_TREATED):
            self.add(run, K_WASTE, 0, x["measure"], WASTE_HAZARDOUS if x["hazardous"] else WASTE_NON_HAZARDOUS, dept, q, 0, idx)
            run["activitiesMeasured"] += 1
        if x["factorCode"] != bytes(CODE):
            code = x["factorCode"]
        else:
            if x["productId"] == 0 and x["partnerId"] == 0:
                return
            rule = self.activity_rule(run["companyId"], x["productId"], x["partnerId"], run["openedBlock"])
            code = rule["factorCode"] if rule is not None else None
        if code is None:
            self.add(run, K_UNASSIGNED, 0, 0, MISS_ACTIVITY_NO_RULE, dept, q, 0, idx)
            return
        f = self.in_force(run["companyId"], code, run["openedBlock"])
        if f is None:
            self.add(run, K_UNASSIGNED, 0, 0, MISS_ACTIVITY_NOT_IN_FORCE, dept, q, 0, idx)
        elif field_text(f["unit"]) != field_text(x["unit"]):
            self.add(run, K_UNASSIGNED, 0, 0, MISS_ACTIVITY_UNIT, dept, q, 0, idx)
        elif self.weigh_entry(run, f, q, dept, idx):
            run["activitiesAssigned"] += 1

    # ── the disclosure, restated ─────────────────────────────────────────────

    def totals(self, run_id):
        t = {"s1": 0, "s2l": 0, "s2m": 0, "s3": 0, "s3c": [0] * 15, "gas": [0] * 7, "emissionEntries": 0,
             "energyBy": [[0] * 9 for _ in range(4)], "energyEntries": [0] * 4, "wc": 0, "wr": 0, "wcN": 0, "wrN": 0,
             "wg": 0, "wrec": 0, "wt": 0, "wh": 0, "wasteN": 0, "unassigned": 0, "tooLarge": 0}
        for f in self.figures_in_key_order(run_id):
            k = f["kind"]
            if k == K_EMISSION:
                t["emissionEntries"] += f["entries"]
                s = f["scope"]
                if s == SCOPE1:
                    t["s1"] += f["co2e"]
                elif s == SCOPE2L:
                    t["s2l"] += f["co2e"]
                elif s == SCOPE2M:
                    t["s2m"] += f["co2e"]
                elif s == SCOPE3:
                    t["s3"] += f["co2e"]
                    if 1 <= f["category"] <= 15:
                        t["s3c"][f["category"] - 1] += f["co2e"]
                if 1 <= f["detail"] <= 7:
                    t["gas"][f["detail"] - 1] += f["co2e"]
            elif k == K_ENERGY:
                if 1 <= f["scope"] <= 4 and 2 <= f["detail"] <= 10:
                    t["energyBy"][f["scope"] - 1][f["detail"] - 2] += f["amount"]
                    t["energyEntries"][f["scope"] - 1] += f["entries"]
            elif k == K_WATER:
                if f["category"] == M_WATER_CONSUMED:
                    t["wc"] += f["amount"]
                    t["wcN"] += f["entries"]
                else:
                    t["wr"] += f["amount"]
                    t["wrN"] += f["entries"]
            elif k == K_WASTE:
                t["wasteN"] += f["entries"]
                if f["detail"] == WASTE_HAZARDOUS:
                    t["wh"] += f["amount"]
                if f["category"] == M_WASTE_GENERATED:
                    t["wg"] += f["amount"]
                elif f["category"] == M_WASTE_RECYCLED:
                    t["wrec"] += f["amount"]
                else:
                    t["wt"] += f["amount"]
            elif k == K_UNASSIGNED:
                t["unassigned"] += f["entries"]
                if f["detail"] == MISS_ENTRY_TOO_LARGE:
                    t["tooLarge"] += f["entries"]
        return t

    @staticmethod
    def within(t):
        if t["energyEntries"][1] > 0:
            s2, n2, method = t["energyBy"][1], t["energyEntries"][1], "location-based"
        elif t["energyEntries"][2] > 0:
            s2, n2, method = t["energyBy"][2], t["energyEntries"][2], "market-based"
        else:
            s2, n2, method = [0] * 9, 0, "none"
        return [t["energyBy"][0][i] + s2[i] for i in range(9)], t["energyEntries"][0] + n2, method

    def disclosure(self, run_id, prior_id):
        """The disclosure line and the seven FRA lines of a sealed run, as the export prints them; None if not sealed."""
        x = self.runs.get(run_id)
        if x is None or x["phase"] != PH_SEALED:
            return None
        t = self.totals(run_id)
        by_source, entries, method = self.within(t)
        energy = sum(by_source)
        renewable = sum(by_source[i] for i in range(9) if i + 2 in RENEWABLE)
        sources = ["%s %s%%" % (SOURCE_TEXT[i + 2], decimal(by_source[i] * 100, abs(energy), 1)) for i in range(9) if energy > 0 and by_source[i] != 0]
        total = t["s1"] + t["s2l"] + t["s3"]
        e33 = "Does the company calculate the percentage of annual saved energy?"
        if prior_id == 0:
            saved = ("No", "no prior sealed run was named")
        else:
            pr = self.runs.get(prior_id)
            if pr is None:
                saved = ("No", "no ESG run %d" % prior_id)
            elif pr["companyId"] != x["companyId"] or pr["phase"] != PH_SEALED or pr["throughDay"] >= x["fromDay"]:
                saved = ("No", "run %d is not a sealed run of the company ending before day %d" % (prior_id, x["fromDay"]))
            else:
                prior = sum(self.within(self.totals(prior_id))[0])
                if prior <= 0:
                    saved = ("No", "run %d consumed no energy" % prior_id)
                else:
                    saved = ("Yes", "%s%% saved against run %d (%s GJ then, %s GJ now)" % (
                        decimal((prior - energy) * 100, abs(prior), 1), prior_id, decimal(prior, GIGAJOULE, 3), decimal(energy, GIGAJOULE, 3)))

        def yes(b):
            return "Yes" if b else "No"
        fra = [
            ("E2.1", "Does the company calculate the total amount of carbon emissions (Carbon Footprint) in metric tons?", yes(t["emissionEntries"] > 0),
             "%s t CO2e: scope 1 %s, scope 2 (location-based) %s, scope 3 %s; scope 2 (market-based) %s" % (
                 decimal(total, TONNE, 3), decimal(t["s1"], TONNE, 3), decimal(t["s2l"], TONNE, 3), decimal(t["s3"], TONNE, 3), decimal(t["s2m"], TONNE, 3))),
            ("E3.1", "Does the company calculate the total amount of energy directly consumed?", yes(entries > 0),
             "%s GJ within the organisation (scope 2 %s); %s GJ outside it" % (decimal(energy, GIGAJOULE, 3), method, decimal(sum(t["energyBy"][3]), GIGAJOULE, 3))),
            ("E3.2", "Does the company calculate the percentage of energy consumption according to the type of generation source?", yes(energy > 0),
             ("renewable %s%%; " % decimal(renewable * 100, abs(energy), 1)) + "; ".join(sources) if energy > 0 else "no energy consumed"),
            ("E3.3", e33, saved[0], saved[1]),
            ("E4.1", "Does the company calculate the total amount of water annual consumed?", yes(t["wcN"] > 0), "%s m3" % decimal(t["wc"], 1000, 3)),
            ("E4.2", "Does the company calculate the total amount of annual water recycled and treated?", yes(t["wrN"] > 0), "%s m3" % decimal(t["wr"], 1000, 3)),
            ("E5.1", "Does the company calculate the total amount of waste generated or recycled and that, which has been treated according to type and weight?",
             yes(t["wasteN"] > 0),
             "generated %s t, recycled %s t, treated %s t; hazardous %s t" % (decimal(t["wg"], 1000, 3), decimal(t["wrec"], 1000, 3), decimal(t["wt"], 1000, 3), decimal(t["wh"], 1000, 3))),
        ]

        def lst(a):
            return ",".join(str(v) for v in a)
        line = "esg_disclosure: %d %d %d %d %d %d %s %d %d %d %d %s %s %d %d %s %s %d %d %d %d %d %d %d %d %d" % (
            run_id, prior_id, x["companyId"], x["fromDay"], x["throughDay"], x["sealedBlock"], x["hash"].hex(), t["s1"], t["s2l"], t["s2m"], t["s3"],
            lst(t["s3c"]), lst(t["gas"]), energy, renewable, lst(by_source), method.encode().hex(), sum(t["energyBy"][3]), t["wc"], t["wr"],
            t["wg"], t["wrec"], t["wt"], t["wh"], t["unassigned"], t["tooLarge"])
        answers = ["esg_fra: %d %d %s %s %s %s" % (run_id, prior_id, code, q.encode().hex(), a, cl.encode().hex()) for code, q, a, cl in fra]
        return line, answers

    # ── what is compared ─────────────────────────────────────────────────────

    def rows(self):
        out = {k: {} for k in ("esg_gwp_set", "esg_gas", "esg_factor", "esg_factor_text", "esg_rule", "esg_activity", "esg_run", "esg_figure")}
        h = lambda t: t.encode("utf-8").hex()  # noqa: E731
        for i, x in self.sets.items():
            out["esg_gwp_set"][i] = "esg_gwp_set: %d %d %s %s %s %s %d %d %s %s %d %d %d %d" % (
                i, x["companyId"], h(x["name"]), h(x["database"]), h(x["edition"]), x["sourceSha256"].hex(), x["gases"], x["state"],
                x["recordedBy"].hex(), x["approvedBy"].hex(), x["recordedDay"], x["approvedDay"], x["approvedBlock"], x["lastBlock"])
        for i, g in self.gases.items():
            out["esg_gas"][i] = "esg_gas: %d %d %d %d %d %s %d %d %d %d" % (
                i, g["companyId"], g["ownerKind"], g["ownerId"], g["ordinal"], g["gas"].hex(), g["group"], g["micrograms"], g["gwpMilli"], g["lastBlock"])
        for i, x in self.factors.items():
            out["esg_factor_text"][i] = "esg_factor_text: %d %s %s %s" % (i, h(x["database"]), h(x["edition"]), h(x["reference"]))
            out["esg_factor"][i] = "esg_factor: %d %d %s %d %d %s %d %d %d %s %d %d %d %d %d %s %s %d %d %d %d" % (
                i, x["companyId"], x["code"].hex(), x["version"], x["gwpSetId"],
                x["sourceSha256"].hex(), x["scope"], x["category"], x["basis"], x["unit"].hex(), x["per"], x["gases"], x["energySource"],
                x["kilojoules"], x["state"], x["recordedBy"].hex(), x["approvedBy"].hex(), x["recordedDay"], x["approvedDay"],
                x["approvedBlock"], x["lastBlock"])
        for i, x in self.rules.items():
            out["esg_rule"][i] = "esg_rule: %d %d %s %d %d %d %d %d %s %s %d %d" % (
                i, x["companyId"], x["factorCode"].hex(), x["productId"], x["partnerId"], x["accountId"], x["createdBlock"], x["retiredBlock"],
                x["createdBy"].hex(), x["retiredBy"].hex(), x["day"], x["lastBlock"])
        for i, x in self.activities.items():
            out["esg_activity"][i] = "esg_activity: %d %d %d %d %s %d %d %d %s %d %d %d %s %d %s %d %d" % (
                i, x["companyId"], x["day"], x["departmentId"], x["factorCode"].hex(), x["productId"], x["partnerId"], x["quantity"],
                x["unit"].hex(), x["measure"], 1 if x["hazardous"] else 0, x["sourceMoveId"], h(x["note"]), x["state"], x["recordedBy"].hex(),
                x["recordedDay"], x["lastBlock"])
        for i, x in self.runs.items():
            out["esg_run"][i] = "esg_run: %d %d %d %d %d %d %d %d %s %d %d %d %d %d %d %d %d %s %s %s %d" % (
                i, x["companyId"], x["fromDay"], x["throughDay"], x["phase"], x["cursorDay"], x["cursorId"], x["openedBlock"],
                x["openedBy"].hex(), x["openedDay"], x["lines"], x["linesAssigned"], x["activities"], x["activitiesAssigned"],
                x["activitiesMeasured"], x["figures"], x["sealedBlock"], x["tip"].hex(), x["chain"].hex(), x["hash"].hex(), x["lastBlock"])
        for i, x in self.figures.items():
            out["esg_figure"][i] = "esg_figure: %d %d %d %d %d %d %d %d %d %d %d %d" % (
                i, x["runId"], x["companyId"], x["kind"], x["scope"], x["category"], x["detail"], x["departmentId"], x["amount"], x["co2e"],
                x["entries"], x["lastBlock"])
        return out

    def summary(self):
        return {"gwp sets": len(self.sets), "factor versions": len(self.factors), "rules": len(self.rules),
                "activities": len(self.activities), "runs": len(self.runs), "runs sealed": self.sealed, "slices walked": self.slices,
                "lines weighed": self.lines_weighed, "activities weighed": self.activities_weighed, "figures": len(self.figures)}
