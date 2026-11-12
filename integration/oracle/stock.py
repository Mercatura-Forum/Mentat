"""The inventory families, decoded, re-encoded and refolded independently.

Families 57 to 63 as `src/Encoding.mo` specifies them under version 1: a warehouse, a location, a
lot, a costing rule, a picking with its moves, and the acts on a picking. Written from the
specification, not translated from the Motoko, so that a block read off a chain can be decoded
here, RE-ENCODED here, and required to be the very bytes the contract hashed.

And the fold: quants per place and lot in thousandths, first-in-first-out layers per place in the
order they were laid down, the average-cost pair per category, the standard cost, and the value a
validated picking carries - each computed here by Python's own decimal arithmetic at the
reference precision (34 significant digits, ROUND_HALF_EVEN, quantised to the minor unit as the
payroll twin does) and compared, in `log_reader.py`, with what the contract exported. A picking
that would take from a place more than it holds, or would value what it takes by layers it does
not have, is a FAULT here whether or not the contract accepted it.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from decimal import Decimal, getcontext, ROUND_HALF_EVEN

from canonical import Reader, write_nat, write_text  # noqa: F401  (Reader named for callers)

getcontext().prec = 34

# ── the enumeration codes, from the design ──────────────────────────────────────

LOCATION_USAGE = {1: "internal", 2: "view", 3: "supplier", 4: "customer", 5: "virtual", 6: "inventory", 7: "production", 8: "transit"}
COST_METHOD = {1: "standard", 2: "fifo", 3: "avco"}
MAY_GO_NEGATIVE = {"supplier", "customer", "virtual", "inventory", "production", "transit"}
MAX_MOVES = 255


def named(table, b, what):
    if b not in table:
        raise ValueError("unknown %s code %d" % (what, b))
    return table[b]


def code_of(table, name, what):
    for b, n in table.items():
        if n == name:
            return b
    raise ValueError("unknown %s name %r" % (what, name))


# ── decoding ────────────────────────────────────────────────────────────────────

def read_location(r):
    return {"companyId": r.nat(), "code": r.text(), "name": r.text(), "usage": named(LOCATION_USAGE, r.nat8(), "location usage"),
            "warehouseId": r.nat(), "parentId": r.nat()}


def read_costing(r):
    return {"companyId": r.nat(), "categoryId": r.nat(), "method": named(COST_METHOD, r.nat8(), "cost method"), "standardCost": r.nat(),
            "inventoryAccountId": r.nat(), "cogsAccountId": r.nat(), "varianceAccountId": r.nat()}


def read_picking(r):
    f = {"companyId": r.nat(), "fromLocationId": r.nat(), "toLocationId": r.nat(), "businessDay": r.nat(), "partnerId": r.nat(), "reference": r.text()}
    n = r.len16()
    f["moves"] = [{"categoryId": r.nat(), "lotId": r.nat(), "quantity": r.nat(), "unitCost": r.nat()} for _ in range(n)]
    return f


READERS = {
    57: ("createWarehouse",  lambda r: {"facts": {"companyId": r.nat(), "code": r.text(), "name": r.text()}}),
    58: ("createLocation",   lambda r: {"facts": read_location(r)}),
    59: ("createLot",        lambda r: {"facts": {"companyId": r.nat(), "categoryId": r.nat(), "code": r.text(), "expiryDay": r.nat()}}),
    60: ("setCosting",       lambda r: {"facts": read_costing(r)}),
    61: ("createPicking",    lambda r: {"facts": read_picking(r)}),
    62: ("cancelPicking",    lambda r: {"companyId": r.nat(), "pickingId": r.nat(), "reason": r.text()}),
    63: ("validatePicking",  lambda r: {"companyId": r.nat(), "pickingId": r.nat(), "journalId": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_stock_command(tag, r):
    family, fn = READERS[tag]
    cmd = fn(r)
    cmd["family"] = family
    return cmd


# ── re-encoding ─────────────────────────────────────────────────────────────────

def write_location(f):
    return (write_nat(f["companyId"]) + write_text(f["code"]) + write_text(f["name"]) + bytes([code_of(LOCATION_USAGE, f["usage"], "location usage")])
            + write_nat(f["warehouseId"]) + write_nat(f["parentId"]))


def write_costing(f):
    return (write_nat(f["companyId"]) + write_nat(f["categoryId"]) + bytes([code_of(COST_METHOD, f["method"], "cost method")]) + write_nat(f["standardCost"])
            + write_nat(f["inventoryAccountId"]) + write_nat(f["cogsAccountId"]) + write_nat(f["varianceAccountId"]))


def write_picking(f):
    out = bytearray(write_nat(f["companyId"]) + write_nat(f["fromLocationId"]) + write_nat(f["toLocationId"]) + write_nat(f["businessDay"])
                    + write_nat(f["partnerId"]) + write_text(f["reference"]))
    n = len(f["moves"])
    if n > 65535:
        raise ValueError("a picking of %d moves" % n)
    out += n.to_bytes(2, "big")
    for m in f["moves"]:
        out += write_nat(m["categoryId"]) + write_nat(m["lotId"]) + write_nat(m["quantity"]) + write_nat(m["unitCost"])
    return bytes(out)


ENCODERS = {
    "createWarehouse":  (57, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["code"]) + write_text(c["facts"]["name"])),
    "createLocation":   (58, lambda c: write_location(c["facts"])),
    "createLot":        (59, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["categoryId"]) + write_text(c["facts"]["code"]) + write_nat(c["facts"]["expiryDay"])),
    "setCosting":       (60, lambda c: write_costing(c["facts"])),
    "createPicking":    (61, lambda c: write_picking(c["facts"])),
    "cancelPicking":    (62, lambda c: write_nat(c["companyId"]) + write_nat(c["pickingId"]) + write_text(c["reason"])),
    "validatePicking":  (63, lambda c: write_nat(c["companyId"]) + write_nat(c["pickingId"]) + write_nat(c["journalId"])),
}


def stock_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return bytes([tag]) + fn(cmd)


# ── the fold ────────────────────────────────────────────────────────────────────

def money(exact):
    """An exact decimal to minor units, ROUND_HALF_EVEN, never below zero - `quantiseWithResidue`
    under a zero-decimal currency."""
    units = int(exact.to_integral_value(rounding=ROUND_HALF_EVEN))
    return 0 if units < 0 else units


def value_of(quantity_thousandths, unit_cost):
    """quantity / 1000 × unit cost, quantised."""
    return money(Decimal(quantity_thousandths) / Decimal(1000) * Decimal(unit_cost))


class Stock:
    """Inventory, refolded. The rules are the ones the design states: a picking arrives whole and
    is applied whole or not at all; an internal location cannot go negative; every category moved
    has a costing rule; goods leaving stock are valued by what is there, never by the caller."""

    def __init__(self):
        self.categories = {}          # id -> companyId, from the sales-and-purchase family
        self.next_category = 1
        self.warehouses = {}
        self.locations = {}
        self.lots = {}
        self.costings = {}            # (companyId, categoryId) -> dict
        self.pickings = {}
        self.moves = {}
        self.quants = {}              # id -> dict; keyed lookup below
        self.quant_by_place = {}      # (companyId, locationId, categoryId, lotId) -> id
        self.layers = {}              # id -> dict
        self.next = {"warehouse": 1, "location": 1, "lot": 1, "costing": 1, "picking": 1, "move": 1, "quant": 1, "layer": 1}
        self.faults = []

    # -- reads --

    def on_hand(self, company, location, category):
        return sum(q["quantity"] for q in self.quants.values() if (q["companyId"], q["locationId"], q["categoryId"]) == (company, location, category))

    def first_category(self, picking_id):
        """The category of a picking's first move: the one whose costing names the accounts the
        valuation entry posts to, as the contract has it."""
        return min(((m["ordinal"], m["categoryId"]) for m in self.moves.values() if m["pickingId"] == picking_id))[1]

    def layers_at(self, company, category, location):
        return sorted(((lid, l) for lid, l in self.layers.items() if (l["companyId"], l["categoryId"], l["locationId"]) == (company, category, location)),
                      key=lambda x: x[1]["sequence"])

    def move_quant(self, company, location, category, lot, delta, block):
        key = (company, location, category, lot)
        qid = self.quant_by_place.get(key)
        if qid is None:
            qid = self.next["quant"]; self.next["quant"] += 1
            self.quants[qid] = {"companyId": company, "locationId": location, "categoryId": category, "lotId": lot, "quantity": 0, "reserved": 0}
            self.quant_by_place[key] = qid
        self.quants[qid]["quantity"] += delta

    # -- the fold --

    def apply(self, block):
        c = block["command"]
        f = c["family"]
        facts = c.get("facts", {})
        if f == "createCategory":
            self.categories[self.next_category] = facts["companyId"]
            self.next_category += 1
        elif f == "createWarehouse":
            wid = self.next["warehouse"]; self.next["warehouse"] += 1
            self.warehouses[wid] = dict(facts)
        elif f == "createLocation":
            if facts["warehouseId"] and facts["warehouseId"] not in self.warehouses:
                self.faults.append("block %d placed a location in a warehouse that does not exist" % block["index"])
            lid = self.next["location"]; self.next["location"] += 1
            self.locations[lid] = dict(facts)
        elif f == "createLot":
            if self.categories.get(facts["categoryId"]) != facts["companyId"]:
                self.faults.append("block %d created a lot of a category the company does not have" % block["index"])
            lid = self.next["lot"]; self.next["lot"] += 1
            self.lots[lid] = dict(facts)
        elif f == "setCosting":
            key = (facts["companyId"], facts["categoryId"])
            if self.categories.get(facts["categoryId"]) != facts["companyId"]:
                self.faults.append("block %d costed a category the company does not have" % block["index"])
            if key in self.costings:
                existing = self.costings[key]
                has_stock = any(q["quantity"] != 0 for q in self.quants.values() if (q["companyId"], q["categoryId"]) == key)
                if existing["method"] != facts["method"] and has_stock:
                    self.faults.append("block %d changed a costing method on a category holding stock" % block["index"])
                existing.update({k: facts[k] for k in ("method", "standardCost", "inventoryAccountId", "cogsAccountId", "varianceAccountId")})
            else:
                cid = self.next["costing"]; self.next["costing"] += 1
                self.costings[key] = {**facts, "id": cid, "avcoQuantity": 0, "avcoValue": 0}
        elif f == "createPicking":
            self.create_picking(block, facts)
        elif f == "cancelPicking":
            p = self.pickings.get(c["pickingId"])
            if p is None or p["state"] != "ready":
                self.faults.append("block %d cancelled a picking that was not ready" % block["index"])
                return
            p["state"] = "cancelled"
            # the picking's moves are cancelled with it (StockFold.cancelPicking)
            for m in self.moves.values():
                if m["pickingId"] == c["pickingId"]:
                    m["state"] = "cancelled"
        elif f == "validatePicking":
            self.validate_picking(block, c)

    def create_picking(self, block, facts):
        moves = facts["moves"]
        src, dst = self.locations.get(facts["fromLocationId"]), self.locations.get(facts["toLocationId"])
        if (not moves or len(moves) > MAX_MOVES or facts["fromLocationId"] == facts["toLocationId"] or src is None or dst is None
                or src["usage"] == "view" or dst["usage"] == "view"):
            self.faults.append("block %d created a picking the rules refuse" % block["index"])
            return
        for m in moves:
            if m["quantity"] == 0 or self.categories.get(m["categoryId"]) != facts["companyId"] or (facts["companyId"], m["categoryId"]) not in self.costings:
                self.faults.append("block %d created a picking with a move the rules refuse" % block["index"])
                return
            if m["lotId"]:
                lot = self.lots.get(m["lotId"])
                if lot is None or lot["categoryId"] != m["categoryId"]:
                    self.faults.append("block %d created a picking naming a lot of another category" % block["index"])
                    return
        pid = self.next["picking"]; self.next["picking"] += 1
        self.pickings[pid] = {**{k: facts[k] for k in ("companyId", "fromLocationId", "toLocationId", "businessDay", "partnerId", "reference")},
                              "state": "ready", "valuationMoveId": 0, "value": 0, "validatedBy": None, "madeBy": block["caller"]}
        for k, m in enumerate(moves):
            mid = self.next["move"]; self.next["move"] += 1
            self.moves[mid] = {**m, "pickingId": pid, "ordinal": k + 1, "valueApplied": 0, "state": "ready"}

    def validate_picking(self, block, c):
        p = self.pickings.get(c["pickingId"])
        if p is None or p["state"] != "ready" or p["companyId"] != c["companyId"]:
            self.faults.append("block %d validated a picking that was not ready" % block["index"])
            return
        company = p["companyId"]
        src, dst = self.locations[p["fromLocationId"]], self.locations[p["toLocationId"]]
        source_internal, dest_internal = src["usage"] == "internal", dst["usage"] == "internal"
        moves = sorted(((mid, m) for mid, m in self.moves.items() if m["pickingId"] == c["pickingId"]), key=lambda x: x[1]["ordinal"])

        # THE PLAN, against the place as it stands. The contract plans every move against the
        # same unchanged store, so two moves of one category in one picking would each see the
        # whole quantity; this reader plans against a running copy and reports the difference as
        # a fault rather than agreeing with an over-consumption.
        on_hand = {}
        layer_left = {lid: l["quantityRemaining"] for lid, l in self.layers.items()}
        avco = {}
        planned = []
        total = 0
        for mid, m in moves:
            costing = self.costings[(company, m["categoryId"])]
            cat = m["categoryId"]
            if source_internal:
                have = on_hand.setdefault(cat, self.on_hand(company, p["fromLocationId"], cat))
                if have < m["quantity"]:
                    self.faults.append("block %d took %d of category %d from location %d holding %d" % (block["index"], m["quantity"], cat, p["fromLocationId"], have))
                    return
                on_hand[cat] = have - m["quantity"]
            unit_cost, value, consumed, avco_after = m["unitCost"], 0, [], None
            if source_internal:
                if costing["method"] == "fifo":
                    remaining = m["quantity"]
                    for lid, l in self.layers_at(company, cat, p["fromLocationId"]):
                        if remaining > 0 and layer_left[lid] > 0:
                            take = min(remaining, layer_left[lid])
                            value += value_of(take, l["unitCost"])
                            consumed.append((lid, take))
                            layer_left[lid] -= take
                            remaining -= take
                    if remaining > 0:
                        self.faults.append("block %d valued a move by layers it does not have (category %d, short %d)" % (block["index"], cat, remaining))
                        return
                elif costing["method"] == "avco":
                    aq, av = avco.get(cat, (costing["avcoQuantity"], costing["avcoValue"]))
                    if aq == 0:
                        self.faults.append("block %d moved a category out under average cost with no average" % block["index"])
                        return
                    value = money(Decimal(m["quantity"]) * Decimal(av) / Decimal(aq))
                    avco_after = (aq - min(aq, m["quantity"]), av - min(av, value))
                    avco[cat] = avco_after
                else:
                    unit_cost = costing["standardCost"]
                    value = value_of(m["quantity"], unit_cost)
            else:
                if unit_cost == 0 and costing["method"] == "standard":
                    unit_cost = costing["standardCost"]
                value = value_of(m["quantity"], unit_cost)
                if costing["method"] == "avco":
                    aq, av = avco.get(cat, (costing["avcoQuantity"], costing["avcoValue"]))
                    avco_after = (aq + m["quantity"], av + value)
                    avco[cat] = avco_after
            total += value
            planned.append((mid, m, unit_cost, value, consumed, dest_internal and costing["method"] == "fifo", avco_after))

        # the writes
        for mid, m, unit_cost, value, consumed, creates_layer, avco_after in planned:
            self.move_quant(company, p["fromLocationId"], m["categoryId"], m["lotId"], -m["quantity"], block)
            self.move_quant(company, p["toLocationId"], m["categoryId"], m["lotId"], m["quantity"], block)
            for lid, take in consumed:
                self.layers[lid]["quantityRemaining"] -= min(self.layers[lid]["quantityRemaining"], take)
            if creates_layer:
                seq = len(self.layers_at(company, m["categoryId"], p["toLocationId"])) + 1
                lid = self.next["layer"]; self.next["layer"] += 1
                self.layers[lid] = {"companyId": company, "categoryId": m["categoryId"], "locationId": p["toLocationId"], "sequence": seq,
                                    "quantityRemaining": m["quantity"], "unitCost": unit_cost, "sourceMoveId": mid}
            if avco_after is not None:
                self.costings[(company, m["categoryId"])]["avcoQuantity"], self.costings[(company, m["categoryId"])]["avcoValue"] = avco_after
            self.moves[mid].update({"unitCost": unit_cost, "valueApplied": value, "state": "done"})
        p["state"] = "done"; p["validatedBy"] = block["caller"]
        p["value"] = total if (total > 0 and (source_internal or dest_internal)) else 0
        p["posts"] = p["value"] > 0
        p["direction"] = "in" if (dest_internal and not source_internal) else "out"

    # -- what the export is compared with --

    def stock_value(self, company, category, location):
        """The value of a category's stock at a location: layers under FIFO, the pair's value
        under AVCO, quantity × standard under standard."""
        costing = self.costings.get((company, category))
        if costing is None:
            return 0
        if costing["method"] == "fifo":
            return sum(value_of(l["quantityRemaining"], l["unitCost"]) for _, l in self.layers_at(company, category, location))
        if costing["method"] == "avco":
            return costing["avcoValue"]
        return value_of(max(0, self.on_hand(company, location, category)), costing["standardCost"])

    def summary(self):
        return {"warehouses": len(self.warehouses), "locations": len(self.locations), "lots": len(self.lots), "costings": len(self.costings),
                "pickings": len(self.pickings), "validated_pickings": sum(1 for p in self.pickings.values() if p["state"] == "done"),
                "quants": len(self.quants), "layers": len(self.layers)}
