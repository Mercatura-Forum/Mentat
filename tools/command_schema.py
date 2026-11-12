#!/usr/bin/env python3
"""The command type, published as data: docs/landed/commands.json.

Every form a client renders and every command it writes is generated from this file, never written by hand: a family's
tag, its fields in declared order with each one's type resolved to the canonical forms of the wire format, and every
enumeration's cases with the byte `src/Enums.mo` assigns each. It is read from the command type by the independent
reader's own parser (`integration/oracle/typed_codec.py`), so the file states the same wire format the reader holds
every block to, and a client that writes a command from it writes the bytes the contract decodes.

A type is one of:
  {"k": "nat" | "nat8" | "nat16" | "nat32" | "nat64" | "int" | "bool" | "text" | "blob" | "principal"}
  {"k": "opt", "t": T}
  {"k": "arr", "t": T, "count": "len16" | "nat"}     the count's form; `nat` only for the four lists typed_codec names
  {"k": "rec", "fields": [[name, T], ...]}            in declared order
  {"k": "tup", "items": [T, ...]}
  {"k": "enum", "name": N, "cases": [[case, byte], ...]}
and a family is {"name", "tag", "type": T or null for a family that carries nothing}; `version` is the encoding
version the bytes are written under (`Encoding.registry.current`), the one `submit` is told.

  tools/command_schema.py           check docs/landed/commands.json is what the command type gives
  tools/command_schema.py --write   write it

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""
import hashlib
import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(ROOT, "integration", "oracle"))
import typed_codec  # noqa: E402

OUT = os.path.join(ROOT, "docs", "landed", "commands.json")
PRIM = {"Nat": "nat", "Nat8": "nat8", "Nat16": "nat16", "Nat32": "nat32", "Nat64": "nat64", "Int": "int", "Bool": "bool",
        "Text": "text", "Blob": "blob", "Principal": "principal"}


def schema(root=ROOT):
    codec = typed_codec.Codec(root)

    def conv(fam, mod, t, field, depth=0):
        if depth > 32:
            raise ValueError("%s: a type nested past 32 levels" % fam)
        k = t[0]
        if k == "name" and t[1] in PRIM:
            return {"k": PRIM[t[1]]}
        if k in ("name", "path"):
            m, name, d = codec._resolve(mod, t)
            table = codec._enum(name, d)
            if table is not None:
                return {"k": "enum", "name": name, "cases": [[c, table[c]] for c, _ in d[1]]}
            return conv(fam, m, d, field, depth + 1)
        if k == "opt":
            return {"k": "opt", "t": conv(fam, mod, t[1], field, depth + 1)}
        if k == "arr":
            return {"k": "arr", "t": conv(fam, mod, t[1], field, depth + 1), "count": "nat" if (fam, field) in typed_codec.NAT_COUNT else "len16"}
        if k == "rec":
            return {"k": "rec", "fields": [[n, conv(fam, mod, ft, n, depth + 1)] for n, ft in t[1]]}
        if k == "tup":
            return {"k": "tup", "items": [conv(fam, mod, x, field, depth + 1) for x in t[1]]}
        raise ValueError("%s: a type the wire format does not state: %r" % (fam, t))

    fams = []
    for fam in codec.families:
        t = codec.arms[fam]
        fams.append({"name": fam, "tag": codec.tag[fam], "type": None if t is None else conv(fam, codec.cmd, t, None)})
    # the version the bytes are written under: the encoding registry's current version, which `submit` is told
    src = open(os.path.join(root, "src", "Encoding.mo"), encoding="utf-8").read()
    m = re.search(r"public let registry : E\.Registry<Command> = \{[^}]*?current = (\d+);", src, flags=re.S)
    if not m:
        raise ValueError("src/Encoding.mo names no current encoding version")
    return {"format": "mentat-commands/1", "version": int(m.group(1)), "families": fams}


def text(d):
    return json.dumps(d, indent=1, ensure_ascii=False) + "\n"


def main():
    d = schema()
    t = text(d)
    if "--write" in sys.argv[1:]:
        open(OUT, "w", encoding="utf-8").write(t)
        print("command schema: %d families written (sha256 %s)" % (len(d["families"]), hashlib.sha256(t.encode()).hexdigest()))
        return 0
    if not os.path.exists(OUT) or open(OUT, encoding="utf-8").read() != t:
        print("COMMAND SCHEMA: docs/landed/commands.json is not what the command type gives (tools/command_schema.py --write)")
        return 1
    print("count: families in the published command schema = %d" % len(d["families"]))
    print("command schema: current (sha256 %s)" % hashlib.sha256(t.encode()).hexdigest())
    return 0


if __name__ == "__main__":
    sys.exit(main())
