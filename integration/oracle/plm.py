"""The product-lifecycle families (608 to 611), decoded from their canonical bytes, re-encoded so the command hash can be
re-derived, and folded by rules written from the design:

  * AN ENGINEERING CHANGE IS PROPOSED WHOLE by a member of the company in standing: the bill's next version - what it
    makes and from what - the day it takes effect and why, under a code of one to sixteen bytes no other change of the
    company holds, with a reason of one to four thousand characters;
  * IT IS THE BILL'S NEXT VERSION ONLY WHEN A SECOND MEMBER APPROVES IT: an administrator, director or manager in
    standing who did not propose it. Versions are numbered from 2 (the declared lines are the first) and take effect on
    STRICTLY INCREASING DAYS, none before the day it is approved; a version that is the bill as it stands changes
    nothing and is not one;
  * every version's components are asked what a bill's are, when proposed and again when approved: one to 255 lines,
    each with a quantity, none the product itself, each a category of the company, NONE CLOSING A CYCLE through any
    version of any bill ever in effect, and none reaching past depth 32 - this reader walks its own graph for both;
  * rejected by such a member, saying why, or withdrawn by its proposer; only a proposed change moves;
  * A PRODUCTION IS MADE TO THE VERSION IN EFFECT ON ITS OWN DAY, PINNED WHEN IT IS PLANNED: the manufacturing reader
    asks this one when it plans a production and consumes the pinned version's lines when it produces.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from collections import deque

from canonical import write_nat, write_text

DAY_LIMIT = 256 ** 3
MAX_TEXT = 4_000
CODE_BYTES = 16
MAX_DEPTH = 32
DECIDERS = {"CompanyAdmin", "Director", "Manager"}
STATE_BYTE = {"proposed": 1, "approved": 2, "rejected": 3, "withdrawn": 4}


def read_eco(r):
    f = {"companyId": r.nat(), "bomId": r.nat(), "code": r.text(), "quantity": r.nat()}
    n = r.len16()
    f["lines"] = [{"categoryId": r.nat(), "quantity": r.nat()} for _ in range(n)]
    f["effectiveDay"] = r.nat()
    f["reason"] = r.text()
    return f


def write_eco(f):
    out = write_nat(f["companyId"]) + write_nat(f["bomId"]) + write_text(f["code"]) + write_nat(f["quantity"])
    out += len(f["lines"]).to_bytes(2, "big")
    for l in f["lines"]:
        out += write_nat(l["categoryId"]) + write_nat(l["quantity"])
    return out + write_nat(f["effectiveDay"]) + write_text(f["reason"])


READERS = {
    608: ("proposeBomChange", lambda r: {"facts": read_eco(r)}),
    609: ("approveBomChange", lambda r: {"companyId": r.nat(), "ecoId": r.nat()}),
    610: ("rejectBomChange", lambda r: {"companyId": r.nat(), "ecoId": r.nat(), "reason": r.text()}),
    611: ("withdrawBomChange", lambda r: {"companyId": r.nat(), "ecoId": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_plm_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "proposeBomChange": (608, lambda c: write_eco(c["facts"])),
    "approveBomChange": (609, lambda c: write_nat(c["companyId"]) + write_nat(c["ecoId"])),
    "rejectBomChange": (610, lambda c: write_nat(c["companyId"]) + write_nat(c["ecoId"]) + write_text(c["reason"])),
    "withdrawBomChange": (611, lambda c: write_nat(c["companyId"]) + write_nat(c["ecoId"])),
}


def plm_command_bytes(cmd):
    tag, enc = ENCODERS[cmd["family"]]
    return put_tag(tag) + enc(cmd)


class Plm:
    def __init__(self, manufacturing):
        self.mfg = manufacturing          # the bills, as the manufacturing reader folds them
        self.ecos = {}
        self.lines = {}                   # line id -> line
        self.pins = {}                    # production id -> pin
        self.next_eco = 1
        self.next_line = 1
        self.faults = []

    # ── the bill's versions ──────────────────────────────────────────────────

    def versions(self, bom_id):
        return sorted((x for x in self.ecos.values() if x["state"] == "approved" and x["bomId"] == bom_id), key=lambda x: x["version"])

    def made_by(self, eco_id):
        x = self.ecos[eco_id]
        return {"quantity": x["quantity"], "lines": x["lines"]}

    def latest(self, bom_id):
        vs = self.versions(bom_id)
        if not vs:
            b = self.mfg.boms[bom_id]
            return 1, 0, {"quantity": b["quantity"], "lines": [{"categoryId": l["categoryId"], "quantity": l["quantity"]} for l in b["lines"]]}
        x = vs[-1]
        return x["version"], x["effectiveDay"], self.made_by(x["id"])

    def version_at(self, bom_id, day):
        found = None
        for x in self.versions(bom_id):
            if x["effectiveDay"] <= day:
                found = x["id"]
        return found

    def pin(self, production_id, company_id, bom_id, day, block_index):
        """Asked by the manufacturing reader when it plans a production: pin it to the version in effect on its day."""
        eco_id = self.version_at(bom_id, day)
        if eco_id is not None:
            self.pins[production_id] = {"companyId": company_id, "bomId": bom_id, "ecoId": eco_id, "lastBlock": block_index}

    def made(self, production_id, bom):
        """What a production consumes: its pinned version's, or the bill's declared lines."""
        p = self.pins.get(production_id)
        if p is None:
            return {"quantity": bom["quantity"], "lines": bom["lines"]}
        return self.made_by(p["ecoId"])

    # ── the graph every version of every bill draws, walked by this reader ──

    def edges(self):
        g = {}
        for b in self.mfg.boms.values():
            g.setdefault(b["categoryId"], set()).update(l["categoryId"] for l in b["lines"])
        for x in self.ecos.values():
            if x["state"] == "approved":
                product = self.mfg.boms[x["bomId"]]["categoryId"]
                g.setdefault(product, set()).update(l["categoryId"] for l in x["lines"])
        return g

    @staticmethod
    def distances(g, start):
        dist = {start: 0}
        q = deque([start])
        while q:
            n = q.popleft()
            for m in g.get(n, ()):
                if m not in dist:
                    dist[m] = dist[n] + 1
                    q.append(m)
        return dist

    def version_wrong(self, store, co, bom_id, quantity, lines, eff, day):
        """Why a version could not be made, or None."""
        b = self.mfg.boms.get(bom_id)
        if b is None or b["companyId"] != co:
            return "a bill not of the company"
        if not b["isActive"]:
            return "a retired bill"
        if eff >= DAY_LIMIT or eff < day:
            return "a day before today or past the field"
        version, latest_day, now = self.latest(bom_id)
        if version >= 255:
            return "a version past 255"
        if version > 1 and eff <= latest_day:
            return "a day not after version %d's" % version
        if not lines or len(lines) > 255 or quantity == 0:
            return "no components, too many, or a bill making nothing"
        g = self.edges()
        for l in lines:
            if l["quantity"] == 0 or l["categoryId"] == b["categoryId"] or store.stock.categories.get(l["categoryId"]) != co:
                return "a component of no quantity, the product itself, or not a category of the company"
            if b["categoryId"] in self.distances(g, l["categoryId"]):
                return "a component closing a cycle"
        for l in lines:
            far = max(self.distances(g, l["categoryId"]).values())
            if far + 1 > MAX_DEPTH:
                return "a component past the depth bound"
        if quantity == now["quantity"] and [(l["categoryId"], l["quantity"]) for l in lines] == [(l["categoryId"], l["quantity"]) for l in now["lines"]]:
            return "the bill as it stands"
        return None

    # ── the fold ─────────────────────────────────────────────────────────────

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = bytes(block["caller"])

        def fault(what):
            self.faults.append("block %d %s" % (idx, what))

        def in_standing(co):
            return (co in store.companies and store.discuss.is_member(co, caller)
                    and (co, caller) not in store.discuss.suspended)

        def decider(co, x):
            return in_standing(co) and store.discuss.roles.get((co, caller)) in DECIDERS and x["proposer"] != caller

        def proposed(co, eco_id):
            x = self.ecos.get(eco_id)
            return x if x is not None and x["companyId"] == co and x["state"] == "proposed" else None

        if f == "proposeBomChange":
            fc = c["facts"]
            co = fc["companyId"]
            code = fc["code"].encode("utf-8")
            if not in_standing(co):
                return fault("proposed a change by a member not in standing")
            if not (0 < len(code) <= CODE_BYTES) or any(x["companyId"] == co and x["code"] == fc["code"] for x in self.ecos.values()):
                return fault("proposed a change under a code it could not hold")
            if not (0 < len(fc["reason"]) <= MAX_TEXT):
                return fault("proposed a change without a reason it could hold")
            why = self.version_wrong(store, co, fc["bomId"], fc["quantity"], fc["lines"], fc["effectiveDay"], day)
            if why is not None:
                return fault("proposed a change that is not a version: " + why)
            eco_id = self.next_eco
            self.next_eco += 1
            self.ecos[eco_id] = {"id": eco_id, "companyId": co, "bomId": fc["bomId"], "code": fc["code"], "quantity": fc["quantity"],
                                 "effectiveDay": fc["effectiveDay"], "version": 0, "state": "proposed",
                                 "lines": [{"categoryId": l["categoryId"], "quantity": l["quantity"]} for l in fc["lines"]],
                                 "proposer": caller, "proposedDay": day, "reason": fc["reason"], "decidedBy": caller, "decidedDay": 0,
                                 "note": "", "lastBlock": idx}
            for k, l in enumerate(fc["lines"]):
                self.lines[self.next_line] = {"ecoId": eco_id, "companyId": co, "ordinal": k + 1, "categoryId": l["categoryId"],
                                              "quantity": l["quantity"], "lastBlock": idx}
                self.next_line += 1
        elif f == "approveBomChange":
            co = c["companyId"]
            x = proposed(co, c["ecoId"])
            if x is None or not decider(co, x):
                return fault("approved a change it could not, or by a member who could not")
            why = self.version_wrong(store, co, x["bomId"], x["quantity"], x["lines"], x["effectiveDay"], day)
            if why is not None:
                return fault("approved a change that is no longer a version: " + why)
            x["version"] = self.latest(x["bomId"])[0] + 1
            x.update(state="approved", decidedBy=caller, decidedDay=day, lastBlock=idx)
        elif f == "rejectBomChange":
            co = c["companyId"]
            x = proposed(co, c["ecoId"])
            if x is None or not decider(co, x) or not (0 < len(c["reason"]) <= MAX_TEXT):
                return fault("rejected a change it could not")
            x.update(state="rejected", decidedBy=caller, decidedDay=day, note=c["reason"], lastBlock=idx)
        elif f == "withdrawBomChange":
            co = c["companyId"]
            x = proposed(co, c["ecoId"])
            if x is None or not in_standing(co) or x["proposer"] != caller:
                return fault("withdrew a change it could not")
            x.update(state="withdrawn", decidedBy=caller, decidedDay=day, lastBlock=idx)

    def rows(self):
        out = {"plm_eco": {}, "plm_eco_line": {}, "plm_pin": {}}
        for i, x in self.ecos.items():
            out["plm_eco"][i] = "plm_eco: %d %d %d %s %d %d %d %d %d %s %d %s %s %d %s %d" % (
                i, x["companyId"], x["bomId"], x["code"], x["quantity"], x["effectiveDay"], x["version"], STATE_BYTE[x["state"]],
                len(x["lines"]), x["proposer"].hex(), x["proposedDay"], x["reason"].encode("utf-8").hex(), x["decidedBy"].hex(),
                x["decidedDay"], x["note"].encode("utf-8").hex(), x["lastBlock"])
        for i, l in self.lines.items():
            out["plm_eco_line"][i] = "plm_eco_line: %d %d %d %d %d %d %d" % (
                i, l["ecoId"], l["companyId"], l["ordinal"], l["categoryId"], l["quantity"], l["lastBlock"])
        for i, p in self.pins.items():
            out["plm_pin"][i] = "plm_pin: %d %d %d %d %d" % (i, p["companyId"], p["bomId"], p["ecoId"], p["lastBlock"])
        return out

    def summary(self):
        return {"changes": len(self.ecos), "versions": sum(1 for x in self.ecos.values() if x["state"] == "approved"), "pins": len(self.pins)}
