"""The manufacturing families (64 to 71), decoded from their canonical bytes and re-encoded so the
command hash can be re-derived, and folded: a production's STATE - planned, confirmed, in progress,
done, cancelled - which the maintenance reader asks about a failure's production and the quality
reader about a check's; and, since the quality extension, a production's STOCK MOVEMENTS. `produce`
moves components from the source into work in progress and the finished goods out of it into the
destination as two pickings through the contract's stock fold; this reader builds the same two - 
each component's quantity scaled exactly, line × produced / bill quantity, quantised to the
thousandth half to even - and HANDS THEM TO ITS OWN STOCK FOLD, made, validated and posted.

THE REQUIREMENT EXPLOSION (family 71) is folded by its rules, on this reader's own graph: from the root, level by
level, every category with an active bill of its company expanded into its lines - the version of the bill in effect
on the block's day, asked of the product-lifecycle reader, else its declared lines - each scaled exactly to the
thousandth half to even and dropped at zero; a category with no bill is something bought and is published, below the
root, in the order the walk meets it; an explosion with a level past its depth (at most 32), or of nothing, is one
the contract refused, so a block holding one is a fault. The rows are compared with the export's whole.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from decimal import Decimal, ROUND_HALF_EVEN

from canonical import write_nat, write_text

MAX_DEPTH = 32


def _bom(r):
    f = {"companyId": r.nat(), "categoryId": r.nat(), "code": r.text(), "quantity": r.nat()}
    n = r.len16()
    f["lines"] = [{"categoryId": r.nat(), "quantity": r.nat()} for _ in range(n)]
    return f


def _production(r):
    return {"companyId": r.nat(), "bomId": r.nat(), "plannedQty": r.nat(), "businessDay": r.nat(),
            "sourceLocationId": r.nat(), "destLocationId": r.nat(), "wipLocationId": r.nat()}


READERS = {
    64: ("declareBom", lambda r: {"facts": _bom(r)}),
    65: ("retireBom", lambda r: {"companyId": r.nat(), "bomId": r.nat(), "reason": r.text()}),
    66: ("planProduction", lambda r: {"facts": _production(r)}),
    67: ("confirmProduction", lambda r: {"companyId": r.nat(), "productionId": r.nat(), "reason": r.text()}),
    68: ("produce", lambda r: {"companyId": r.nat(), "productionId": r.nat(), "quantity": r.nat(), "journalId": r.nat()}),
    69: ("closeProductionShort", lambda r: {"companyId": r.nat(), "productionId": r.nat(), "reason": r.text()}),
    70: ("cancelProduction", lambda r: {"companyId": r.nat(), "productionId": r.nat(), "reason": r.text()}),
    71: ("explodeRequirements", lambda r: {"companyId": r.nat(), "runId": r.nat(), "planHash": r.blob(), "rootCategoryId": r.nat(), "rootQuantity": r.nat(), "maxDepth": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_manufacturing_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def _bom_bytes(c):
    f = c["facts"]
    out = write_nat(f["companyId"]) + write_nat(f["categoryId"]) + write_text(f["code"]) + write_nat(f["quantity"]) + len(f["lines"]).to_bytes(2, "big")
    for l in f["lines"]:
        out += write_nat(l["categoryId"]) + write_nat(l["quantity"])
    return out


ENCODERS = {
    "declareBom": (64, _bom_bytes),
    "retireBom": (65, lambda c: write_nat(c["companyId"]) + write_nat(c["bomId"]) + write_text(c["reason"])),
    "planProduction": (66, lambda c: b"".join(write_nat(c["facts"][k]) for k in ("companyId", "bomId", "plannedQty", "businessDay", "sourceLocationId", "destLocationId", "wipLocationId"))),
    "confirmProduction": (67, lambda c: write_nat(c["companyId"]) + write_nat(c["productionId"]) + write_text(c["reason"])),
    "produce": (68, lambda c: write_nat(c["companyId"]) + write_nat(c["productionId"]) + write_nat(c["quantity"]) + write_nat(c["journalId"])),
    "closeProductionShort": (69, lambda c: write_nat(c["companyId"]) + write_nat(c["productionId"]) + write_text(c["reason"])),
    "cancelProduction": (70, lambda c: write_nat(c["companyId"]) + write_nat(c["productionId"]) + write_text(c["reason"])),
    "explodeRequirements": (71, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + len(c["planHash"]).to_bytes(2, "big") + c["planHash"]
                            + write_nat(c["rootCategoryId"]) + write_nat(c["rootQuantity"]) + write_nat(c["maxDepth"])),
}


def manufacturing_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


class Manufacturing:
    def __init__(self):
        self.boms = {}
        self.productions = {}
        self.next_bom = 1
        self.next_production = 1
        self.requirements = {}
        self.next_requirement = 1
        self.faults = []
        # the product-lifecycle reader, which pins a production to the version of its bill in effect on its day
        self.plm = None

    def apply(self, block, consume=None):
        """`consume(block, picking_facts, journal_id)` hands a picking to the stock reader and its
        valuation entry to the ledger; it returns the picking's id."""
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        if f == "declareBom":
            self.boms[self.next_bom] = {**c["facts"], "isActive": True}
            self.next_bom += 1
        elif f == "retireBom":
            b = self.boms.get(c["bomId"])
            if b is None or b["companyId"] != c["companyId"] or not b["isActive"]:
                self.faults.append("block %d retired a bill of materials it could not" % idx)
                return
            b["isActive"] = False
        elif f == "planProduction":
            fc = c["facts"]
            b = self.boms.get(fc["bomId"])
            locs = (fc["sourceLocationId"], fc["wipLocationId"], fc["destLocationId"])
            if b is None or b["companyId"] != fc["companyId"] or not b["isActive"] or fc["plannedQty"] == 0 or len(set(locs)) != 3:
                self.faults.append("block %d planned a production it could not" % idx)
                return
            self.productions[self.next_production] = {**fc, "categoryId": b["categoryId"], "producedQty": 0, "state": "draft", "closedShort": False}
            if self.plm is not None:
                self.plm.pin(self.next_production, fc["companyId"], fc["bomId"], fc["businessDay"], idx)
            self.next_production += 1
        elif f == "confirmProduction":
            p = self.productions.get(c["productionId"])
            if p is None or p["companyId"] != c["companyId"] or p["state"] != "draft":
                self.faults.append("block %d confirmed a production it could not" % idx)
                return
            p["state"] = "confirmed"
        elif f == "produce":
            p = self.productions.get(c["productionId"])
            if (p is None or p["companyId"] != c["companyId"] or p["state"] not in ("confirmed", "inProgress") or c["quantity"] == 0
                    or p["producedQty"] + c["quantity"] > p["plannedQty"]):
                self.faults.append("block %d produced on a production it could not" % idx)
                return
            # THE VERSION THE PRODUCTION WAS PINNED TO when it was planned, or the bill's declared lines
            b = self.plm.made(c["productionId"], self.boms[p["bomId"]]) if self.plm is not None else self.boms[p["bomId"]]
            # the components, scaled EXACTLY: line × produced / bill quantity, to the thousandth half to even
            moves = []
            for l in b["lines"]:
                q = int((Decimal(l["quantity"] * c["quantity"]) / Decimal(b["quantity"])).quantize(Decimal(1), rounding=ROUND_HALF_EVEN))
                if q > 0:
                    moves.append({"categoryId": l["categoryId"], "lotId": 0, "quantity": q, "unitCost": 0})
            if not moves or consume is None:
                self.faults.append("block %d produced with no component to consume" % idx)
                return
            # SOURCE → WORK IN PROGRESS, then WORK IN PROGRESS → DESTINATION, each through the stock reader
            consume(block, {"companyId": c["companyId"], "fromLocationId": p["sourceLocationId"], "toLocationId": p["wipLocationId"], "businessDay": p["businessDay"],
                            "partnerId": 0, "reference": "production %d components" % c["productionId"], "moves": moves}, c["journalId"])
            consume(block, {"companyId": c["companyId"], "fromLocationId": p["wipLocationId"], "toLocationId": p["destLocationId"], "businessDay": p["businessDay"],
                            "partnerId": 0, "reference": "production %d output" % c["productionId"],
                            "moves": [{"categoryId": p["categoryId"], "lotId": 0, "quantity": c["quantity"], "unitCost": 0}]}, c["journalId"])
            p["producedQty"] += c["quantity"]
            p["state"] = "done" if p["producedQty"] >= p["plannedQty"] else "inProgress"
        elif f == "explodeRequirements":
            self._explode(block, c)
        elif f == "closeProductionShort":
            p = self.productions.get(c["productionId"])
            if p is None or p["companyId"] != c["companyId"] or p["state"] not in ("confirmed", "inProgress"):
                self.faults.append("block %d closed a production short it could not" % idx)
                return
            p["state"] = "done"
            p["closedShort"] = True
        elif f == "cancelProduction":
            p = self.productions.get(c["productionId"])
            if p is None or p["companyId"] != c["companyId"] or p["state"] == "done" or p["producedQty"] > 0:
                self.faults.append("block %d cancelled a production it could not" % idx)
                return
            p["state"] = "cancelled"

    def bill_for(self, company_id, category_id):
        """The active bill of materials a company makes a category by, or None: something bought."""
        found = [(i, b) for i, b in self.boms.items() if b["isActive"] and b["companyId"] == company_id and b["categoryId"] == category_id]
        return found[0] if found else None

    def _made(self, bom_id, bom, day):
        if self.plm is not None:
            eco = self.plm.version_at(bom_id, day)
            if eco is not None:
                return self.plm.made_by(eco)
        return {"quantity": bom["quantity"], "lines": bom["lines"]}

    def _explode(self, block, c):
        idx = block["index"]
        if c["rootQuantity"] == 0:
            self.faults.append("block %d exploded nothing" % idx)
            return
        bound = min(c["maxDepth"], MAX_DEPTH)
        frontier = [(c["rootCategoryId"], c["rootQuantity"], 0)]
        published = []
        depth = 0
        while frontier:
            if depth > bound:
                self.faults.append("block %d exploded past its depth %d" % (idx, bound))
                return
            nxt = []
            for category, quantity, d in frontier:
                found = self.bill_for(c["companyId"], category)
                if found is None:
                    if d > 0:
                        published.append((category, quantity, d))
                    continue
                made = self._made(found[0], found[1], block["day"])
                for l in made["lines"]:
                    q = int((Decimal(l["quantity"] * quantity) / Decimal(made["quantity"])).quantize(Decimal(1), rounding=ROUND_HALF_EVEN))
                    if q > 0:
                        nxt.append((l["categoryId"], q, d + 1))
            frontier = nxt
            depth += 1
        for ordinal, (category, quantity, d) in enumerate(published, 1):
            self.requirements[self.next_requirement] = {"runId": c["runId"], "companyId": c["companyId"], "ordinal": ordinal,
                                                        "categoryId": category, "depth": d, "quantity": quantity, "lastBlock": idx}
            self.next_requirement += 1

    def requirement_line(self, rid):
        r = self.requirements[rid]
        return "mrp_requirement: %d %d %d %d %d %d %d %d" % (rid, r["runId"], r["companyId"], r["ordinal"], r["categoryId"], r["depth"], r["quantity"], r["lastBlock"])

    def summary(self):
        return {"boms": len(self.boms), "productions": len(self.productions), "produced": sum(1 for p in self.productions.values() if p["producedQty"] > 0), "faults": len(self.faults)}
