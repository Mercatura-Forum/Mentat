"""A page of the read method, decoded from its bytes alone (src/ReadSurface.mo).

A page is the log's height, the tip it was read at (or none), the kind, the company, a count, each row as its id and
its fields in the order the row type declares them, and the id to ask after (or none). An enumeration is written as
its variant's byte and read back as the variant's name; a signed number - an Int, or a Nat the declaration marks
zigzagged (`zag`) - is written zigzagged and read back signed. The fields are written by the
command codec's canonical rules, and how each kind's fields are written is read from `read_kinds.json`, which
`tools/read_surface.py` writes from the declarations and holds to them. This decoder is written from those rules, not
from the contract's code: a page it cannot read to its last byte, or that is not the one spelling of what it holds, is
refused.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import json
import os

from canonical import Reader, write_nat, write_text

KINDS = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "read_kinds.json")))["kinds"]


def _opt_bool(r):
    tag = r.byte()
    if tag == 0:
        return None
    if tag == 1:
        return r.bool()
    raise ValueError("an optional Bool tagged %d" % tag)


def _many(r, one):
    return [one(r) for _ in range(r.len16())]


def _int(r):
    z = r.nat()
    return z >> 1 if z % 2 == 0 else -((z + 1) >> 1)


FIELD = {
    "nat": lambda r: r.nat(),
    "principal": lambda r: bytes(r.principal()),
    "text": lambda r: r.text(),
    "blob": lambda r: bytes(r.blob()),
    "bool": lambda r: r.bool(),
    "int": _int,
    "zag": _int,
    "optBool": _opt_bool,
    "nats": lambda r: _many(r, lambda x: x.nat()),
    "blobs": lambda r: _many(r, lambda x: bytes(x.blob())),
    "enum": lambda r: r.nat8(),
    "enums": lambda r: _many(r, lambda x: x.nat8()),
}


def _len16(n):
    return n.to_bytes(2, "big")


def _wblob(b):
    return _len16(len(b)) + bytes(b)


def _wint(i):
    return write_nat(2 * i if i >= 0 else -2 * i - 1)


WRITE = {
    "nat": write_nat,
    "principal": lambda p: bytes([len(p)]) + bytes(p),
    "text": write_text,
    "blob": _wblob,
    "bool": lambda b: bytes([1 if b else 0]),
    "int": _wint,
    "zag": _wint,
    "optBool": lambda o: b"\x00" if o is None else b"\x01" + bytes([1 if o else 0]),
    "nats": lambda xs: _len16(len(xs)) + b"".join(write_nat(x) for x in xs),
    "blobs": lambda xs: _len16(len(xs)) + b"".join(_wblob(x) for x in xs),
    "enum": lambda n: bytes([n]),
    "enums": lambda xs: _len16(len(xs)) + bytes(xs),
}


def _name(kind, f, b):
    n = f[2].get(str(b))
    if n is None:
        raise ValueError("%s.%s holds byte %d, which names no variant" % (kind, f[0], b))
    return n


def _read_field(r, kind, f):
    """A field's value; an enum read as the name of its variant, by the table the declarations give."""
    v = FIELD[f[1]](r)
    if f[1] == "enum":
        return _name(kind, f, v)
    if f[1] == "enums":
        return [_name(kind, f, b) for b in v]
    return v


def _write_field(kind, f, v):
    if f[1] in ("enum", "enums"):
        back = {n: int(b) for b, n in f[2].items()}
        v = back[v] if f[1] == "enum" else [back[x] for x in v]
    return WRITE[f[1]](v)


def encode(page):
    """The one spelling of a page: what the contract writes for these values."""
    out = write_nat(page["height"])
    out += b"\x00" if page["tip"] is None else b"\x01" + _wblob(page["tip"])
    out += write_text(page["kind"]) + write_nat(page["companyId"]) + _len16(len(page["rows"]))
    for rid, row in page["rows"]:
        out += write_nat(rid) + b"".join(_write_field(page["kind"], f, row[f[0]]) for f in KINDS[page["kind"]]["fields"])
    out += b"\x00" if page["next"] is None else b"\x01" + write_nat(page["next"])
    return out


def request_page(kind, company_id, after, limit):
    """A request for a page (src/ReadSurface.mo `requestBytes`): byte 0, the kind, the company, the id to start after
    (or none) and how many rows at most - written here from the codec's rules for a client to send."""
    return (b"\x00" + write_text(kind) + write_nat(company_id)
            + (b"\x00" if after is None else b"\x01" + write_nat(after)) + write_nat(limit))


def decode(data):
    """The page the bytes hold, read whole: {height, tip, kind, companyId, rows: [(id, {field: value})], next}."""
    r = Reader(data)
    height = r.nat()
    tip = r.opt_blob()
    kind = r.text()
    if kind not in KINDS:
        raise ValueError("a page of %r, which is no kind of the read method" % kind)
    company = r.nat()
    rows = []
    for _ in range(r.len16()):
        rid = r.nat()
        rows.append((rid, {f[0]: _read_field(r, kind, f) for f in KINDS[kind]["fields"]}))
    nxt = r.opt_nat()
    if not r.at_end():
        raise ValueError("a page of %s with %d byte(s) after it" % (kind, r.remaining()))
    page = {"height": height, "tip": None if tip is None else bytes(tip), "kind": kind, "companyId": company,
            "rows": rows, "next": nxt}
    if encode(page) != bytes(data):
        raise ValueError("a page of %s that is not the one spelling of what it holds" % kind)
    return page
