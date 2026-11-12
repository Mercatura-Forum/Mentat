"""The sales-and-purchase families, decoded and re-encoded independently.

Families 48 to 56 as `src/Encoding.mo` specifies them under version 1: a partner, a category, an
order with its lines, and the acts on an order. Written from the specification, not translated from
the Motoko, so that a block read off a chain can be decoded here, RE-ENCODED here, and required to
be the very bytes the contract hashed. A reader that can only decode cannot make that claim.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import Reader, write_nat, write_text  # noqa: F401  (Reader named for callers)

# ── the enumeration codes, from the design ──────────────────────────────────────

ORDER_DIRECTION = {1: "sale", 2: "purchase"}


def named(table, b, what):
    if b not in table:
        raise ValueError("unknown %s code %d" % (what, b))
    return table[b]


def code_of(table, name, what):
    for b, n in table.items():
        if n == name:
            return b
    raise ValueError("unknown %s name %r" % (what, name))


# ── the payload decoders ────────────────────────────────────────────────────────

def read_partner_facts(r):
    return {"companyId": r.nat(), "code": r.text(), "name": r.text(),
            "isCustomer": r.bool(), "isSupplier": r.bool(),
            "receivableAccountId": r.nat(), "payableAccountId": r.nat(),
            "taxIdentifier": r.text()}


def read_category_facts(r):
    return {"companyId": r.nat(), "code": r.text(), "name": r.text(),
            "incomeAccountId": r.nat(), "expenseAccountId": r.nat()}


def read_order_facts(r):
    companyId = r.nat()
    partnerId = r.nat()
    direction = named(ORDER_DIRECTION, r.nat8(), "order direction")
    orderDay = r.nat()
    currency = r.text()
    clientRef = r.text()
    n = r.len16()
    lines = []
    for _ in range(n):
        lines.append({"categoryId": r.nat(), "name": r.text(), "quantity": r.nat(),
                      "priceUnit": r.nat(), "taxRate": r.nat()})
    return {"companyId": companyId, "partnerId": partnerId, "direction": direction,
            "orderDay": orderDay, "currency": currency, "clientRef": clientRef, "lines": lines}


def read_on_order(r):
    return {"companyId": r.nat(), "orderId": r.nat(), "reason": r.text()}


READERS = {
    48: ("createPartner",  lambda r: {"facts": read_partner_facts(r)}),
    49: ("amendPartner",   lambda r: {"partnerId": r.nat(), "facts": read_partner_facts(r)}),
    50: ("createCategory", lambda r: {"facts": read_category_facts(r)}),
    51: ("amendCategory",  lambda r: {"categoryId": r.nat(), "facts": read_category_facts(r)}),
    52: ("placeOrder",     lambda r: {"facts": read_order_facts(r)}),
    53: ("amendOrder",     lambda r: {"orderId": r.nat(), "facts": read_order_facts(r)}),
    54: ("confirmOrder",   read_on_order),
    55: ("cancelOrder",    read_on_order),
    56: ("issueInvoice",   lambda r: {"companyId": r.nat(), "orderId": r.nat(), "journalId": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_order_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


# ── the payload encoders: the same layout, written the other way ────────────────

def _bool(b):
    return b"\x01" if b else b"\x00"


def write_partner_facts(f):
    return (write_nat(f["companyId"]) + write_text(f["code"]) + write_text(f["name"])
            + _bool(f["isCustomer"]) + _bool(f["isSupplier"])
            + write_nat(f["receivableAccountId"]) + write_nat(f["payableAccountId"])
            + write_text(f["taxIdentifier"]))


def write_category_facts(f):
    return (write_nat(f["companyId"]) + write_text(f["code"]) + write_text(f["name"])
            + write_nat(f["incomeAccountId"]) + write_nat(f["expenseAccountId"]))


def write_order_facts(f):
    out = bytearray()
    out += write_nat(f["companyId"]) + write_nat(f["partnerId"])
    out += bytes([code_of(ORDER_DIRECTION, f["direction"], "order direction")])
    out += write_nat(f["orderDay"]) + write_text(f["currency"]) + write_text(f["clientRef"])
    n = len(f["lines"])
    if n > 65535:
        raise ValueError("an order of %d lines" % n)
    out += n.to_bytes(2, "big")
    for l in f["lines"]:
        out += (write_nat(l["categoryId"]) + write_text(l["name"]) + write_nat(l["quantity"])
                + write_nat(l["priceUnit"]) + write_nat(l["taxRate"]))
    return bytes(out)


def write_on_order(c):
    return write_nat(c["companyId"]) + write_nat(c["orderId"]) + write_text(c["reason"])


ENCODERS = {
    "createPartner":  (48, lambda c: write_partner_facts(c["facts"])),
    "amendPartner":   (49, lambda c: write_nat(c["partnerId"]) + write_partner_facts(c["facts"])),
    "createCategory": (50, lambda c: write_category_facts(c["facts"])),
    "amendCategory":  (51, lambda c: write_nat(c["categoryId"]) + write_category_facts(c["facts"])),
    "placeOrder":     (52, lambda c: write_order_facts(c["facts"])),
    "amendOrder":     (53, lambda c: write_nat(c["orderId"]) + write_order_facts(c["facts"])),
    "confirmOrder":   (54, write_on_order),
    "cancelOrder":    (55, write_on_order),
    "issueInvoice":   (56, lambda c: write_nat(c["companyId"]) + write_nat(c["orderId"]) + write_nat(c["journalId"])),
}


def order_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return bytes([tag]) + fn(cmd)
