"""Every command family, decoded and re-encoded from its declared type: the reader's own statement of the wire format.

The contract's command type (`src/Command.mo`, and the facts types it names in other modules) declares every
family's fields in order. This reader reads those declarations - not the contract's encoder - and decodes a command
by the canonical form of each field's type, in declared order:

  Nat            the canonical natural: a byte holding the count of big-endian bytes that follow (zero for 0)
  Nat8           one byte;   Nat64  eight bytes, big-endian;   Int  the natural of its zigzag (2n, or -2n - 1)
  Bool           one byte, 0 or 1
  Text, Blob     a two-byte length, then the bytes (a text's UTF-8)
  Principal      a byte holding its length, then its bytes
  ?T             a byte, 0 for none, 1 then the value
  [T]            a two-byte count, then the items
  a record       its fields in declared order;   a tuple  its items in order
  an enumeration the byte `src/Enums.mo` assigns its case (`fooByte`), read from those functions' own tables

and a command is its family's tag (`Encoding.putTag`: one byte below 255, then 0xFF and an offset, then 0xFF 0xFF
and two bytes) followed by its arm's fields. So a command the contract wrote with a field dropped, moved or written
in another form does not read back as itself here, and the export's samples of every family - the plainest value
each type admits and the richest - are held to this reading byte for byte and value for value.

ONE STATED EXCEPTION. Three families of the shop and the restaurant write a list's count as a canonical natural
rather than a two-byte count: `ringUpSale` its lines, `orderCourse` its lines, `settleTab` its weights and its
tenders. Blocks already on logs carry that form, so it is the wire format of those four lists and is stated here,
by family and field, rather than read into any other list.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import os
import re

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

NAT_COUNT = {("ringUpSale", "lines"), ("orderCourse", "lines"), ("settleTab", "weights"), ("settleTab", "tenders")}
PRIMS = {"Nat", "Nat8", "Nat16", "Nat32", "Nat64", "Int", "Bool", "Text", "Blob", "Principal"}


def _strip(s):
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    return re.sub(r"//[^\n]*", "", s)


class _Module:
    def __init__(self, path):
        src = _strip(open(path, encoding="utf-8").read())
        self.path = path
        self.imports = dict(re.findall(r'import\s+(\w+)\s+"([^"]+)"', src))
        self.types = {m.group(1): (src, m.end()) for m in re.finditer(r"public\s+type\s+(\w+)(?:\s*<[^>]*>)?\s*=\s*", src)}


class _Parser:
    def __init__(self, src, pos):
        self.s, self.i = src, pos

    def _ws(self):
        while self.i < len(self.s) and self.s[self.i] in " \t\r\n":
            self.i += 1

    def _peek(self):
        self._ws()
        return self.s[self.i] if self.i < len(self.s) else ""

    def _eat(self, t):
        self._ws()
        if not self.s.startswith(t, self.i):
            raise ValueError("the type reader expected %r at %r" % (t, self.s[self.i:self.i + 40]))
        self.i += len(t)

    def _ident(self):
        self._ws()
        m = re.compile(r"[A-Za-z_][A-Za-z0-9_]*").match(self.s, self.i)
        if not m:
            raise ValueError("the type reader expected a name at %r" % self.s[self.i:self.i + 40])
        self.i = m.end()
        return m.group(0)

    def typ(self):
        c = self._peek()
        if c == "?":
            self._eat("?")
            return ("opt", self.typ())
        if c == "[":
            self._eat("[")
            self._ws()
            if self.s.startswith("var ", self.i):
                self.i += 4
            t = self.typ()
            self._eat("]")
            return ("arr", t)
        if c == "(":
            self._eat("(")
            items = []
            while self._peek() != ")":
                items.append(self.typ())
                if self._peek() == ",":
                    self._eat(",")
            self._eat(")")
            return items[0] if len(items) == 1 else ("tup", items)
        if c == "{":
            self._eat("{")
            if self._peek() == "#":
                alts = []
                while self._peek() != "}":
                    self._eat("#")
                    n = self._ident()
                    t = None
                    if self._peek() == ":":
                        self._eat(":")
                        t = self.typ()
                    alts.append((n, t))
                    if self._peek() == ";":
                        self._eat(";")
                self._eat("}")
                return ("var", alts)
            fields = []
            while self._peek() != "}":
                self._ws()
                if self.s.startswith("var ", self.i):
                    self.i += 4
                n = self._ident()
                self._eat(":")
                fields.append((n, self.typ()))
                if self._peek() == ";":
                    self._eat(";")
            self._eat("}")
            return ("rec", fields)
        name = self._ident()
        if self._peek() == ".":
            self._eat(".")
            return ("path", name, self._ident())
        return ("name", name)


class _Reader:
    def __init__(self, b):
        self.b, self.i = b, 0

    def byte(self):
        if self.i >= len(self.b):
            raise ValueError("the command ends early")
        v = self.b[self.i]
        self.i += 1
        return v

    def take(self, n):
        v = self.b[self.i:self.i + n]
        if len(v) != n:
            raise ValueError("the command ends early")
        self.i += n
        return bytes(v)

    def nat(self):
        n = self.byte()
        if n == 0:
            return 0
        v = self.take(n)
        if v[0] == 0:
            raise ValueError("a natural with a leading zero byte is not canonical")
        return int.from_bytes(v, "big")

    def count(self):
        return int.from_bytes(self.take(2), "big")


def _nat(n):
    if n == 0:
        return b"\x00"
    k = (n.bit_length() + 7) // 8
    return bytes([k]) + n.to_bytes(k, "big")


class Codec:
    """The command type of a source tree, read once; `decode` and `encode` a command body by it."""

    def __init__(self, root=ROOT):
        self.root = root
        self.modules = {}
        self.resolved = {}
        cmd = self._module("Command")
        src, pos = cmd.types["Command"]
        self.cmd = cmd
        self.arms = dict(_Parser(src, pos).typ()[1])
        fam = _strip(open(os.path.join(root, "src", "Command.mo"), encoding="utf-8").read())
        self.families = re.findall(r'"(\w+)"', re.search(r"public let FAMILIES : \[Text\] = \[(.*?)\];", fam, re.S).group(1))
        if set(self.families) != set(self.arms):
            raise ValueError("the families listed and the command's arms differ: %r" % (set(self.families) ^ set(self.arms)))
        self.tag = {f: i for i, f in enumerate(self.families)}
        en = _strip(open(os.path.join(root, "src", "Enums.mo"), encoding="utf-8").read())
        self.bytes = {}
        for m in re.finditer(r"public func (\w+)Byte\(\w+ : (\w+)\) : Nat8 \{\s*switch \(\w+\) \{(.*?)\}\s*\}", en, re.S):
            cases = {}
            for c in re.finditer(r"case \(([^)]*)\) (\d+)", m.group(3)):
                for alt in re.findall(r"#(\w+)", c.group(1)):
                    cases[alt] = int(c.group(2))
            self.bytes[m.group(2)] = cases

    def _module(self, name):
        path = os.path.join(self.root, "src", name + ".mo")
        if path not in self.modules:
            self.modules[path] = _Module(path)
        return self.modules[path]

    def _resolve(self, mod, t):
        key = (mod.path, t)
        if key not in self.resolved:
            self.resolved[key] = self._resolve_once(mod, t)
        return self.resolved[key]

    def _resolve_once(self, mod, t):
        if t[0] == "path":
            target = mod.imports.get(t[1])
            if not target or target.startswith("mo:"):
                raise ValueError("a type from outside the tree: %r" % (t,))
            m, name = self._module(os.path.basename(target)), t[2]
        else:
            m, name = mod, t[1]
        if name not in m.types:
            raise ValueError("no type %s in %s" % (name, m.path))
        src, pos = m.types[name]
        return m, name, _Parser(src, pos).typ()

    def _enum(self, name, d):
        if d[0] == "var" and all(pt is None for _, pt in d[1]):
            if name not in self.bytes:
                raise ValueError("the enumeration %s has no byte table in src/Enums.mo" % name)
            table = self.bytes[name]
            if set(table) != {n for n, _ in d[1]}:
                raise ValueError("the enumeration %s and its byte table name different cases" % name)
            return table
        return None

    # -- decoding --

    def _dec(self, fam, mod, t, r, field):
        k = t[0]
        if k == "name" and t[1] in PRIMS:
            p = t[1]
            if p in ("Nat", "Nat16", "Nat32"):
                return r.nat()
            if p == "Nat8":
                return r.byte()
            if p == "Nat64":
                return int.from_bytes(r.take(8), "big")
            if p == "Int":
                z = r.nat()
                return z >> 1 if z % 2 == 0 else -((z + 1) >> 1)
            if p == "Bool":
                v = r.byte()
                if v > 1:
                    raise ValueError("a boolean byte of %d" % v)
                return v == 1
            if p == "Text":
                return r.take(r.count()).decode("utf-8")
            if p == "Blob":
                return r.take(r.count())
            if p == "Principal":
                n = r.byte()
                if n > 29:
                    raise ValueError("a principal of %d bytes" % n)
                return r.take(n)
        if k in ("name", "path"):
            m, name, d = self._resolve(mod, t)
            table = self._enum(name, d)
            if table is not None:
                b = r.byte()
                for case, v in table.items():
                    if v == b:
                        return {"$case": case}
                raise ValueError("%s has no case for the byte %d" % (name, b))
            return self._dec(fam, m, d, r, field)
        if k == "opt":
            f = r.byte()
            if f > 1:
                raise ValueError("an option's flag byte of %d" % f)
            return None if f == 0 else self._dec(fam, mod, t[1], r, field)
        if k == "arr":
            n = r.nat() if (fam, field) in NAT_COUNT else r.count()
            return [self._dec(fam, mod, t[1], r, field) for _ in range(n)]
        if k == "rec":
            return {n: self._dec(fam, mod, ft, r, n) for n, ft in t[1]}
        if k == "tup":
            return [self._dec(fam, mod, x, r, field) for x in t[1]]
        raise ValueError("a type the wire format does not state: %r" % (t,))

    def decode(self, body):
        """(family, value) of one command body; every byte must be read."""
        r = _Reader(body)
        tag = r.byte()
        if tag == 255:
            s = r.byte()
            tag = 255 + s if s < 255 else 510 + int.from_bytes(r.take(2), "big")
        if tag >= len(self.families):
            raise ValueError("no family has the tag %d" % tag)
        fam = self.families[tag]
        t = self.arms[fam]
        value = None if t is None else self._dec(fam, self.cmd, t, r, None)
        if r.i != len(body):
            raise ValueError("%s: %d byte(s) left over" % (fam, len(body) - r.i))
        return fam, value

    # -- encoding --

    def _enc(self, fam, mod, t, v, field):
        k = t[0]
        if k == "name" and t[1] in PRIMS:
            p = t[1]
            if p in ("Nat", "Nat16", "Nat32"):
                return _nat(v)
            if p == "Nat8":
                return bytes([v])
            if p == "Nat64":
                return v.to_bytes(8, "big")
            if p == "Int":
                return _nat(2 * v if v >= 0 else -2 * v - 1)
            if p == "Bool":
                return b"\x01" if v else b"\x00"
            if p == "Text":
                b = v.encode("utf-8")
                return len(b).to_bytes(2, "big") + b
            if p == "Blob":
                return len(v).to_bytes(2, "big") + v
            if p == "Principal":
                return bytes([len(v)]) + v
        if k in ("name", "path"):
            m, name, d = self._resolve(mod, t)
            table = self._enum(name, d)
            if table is not None:
                return bytes([table[v["$case"]]])
            return self._enc(fam, m, d, v, field)
        if k == "opt":
            return b"\x00" if v is None else b"\x01" + self._enc(fam, mod, t[1], v, field)
        if k == "arr":
            head = _nat(len(v)) if (fam, field) in NAT_COUNT else len(v).to_bytes(2, "big")
            return head + b"".join(self._enc(fam, mod, t[1], x, field) for x in v)
        if k == "rec":
            return b"".join(self._enc(fam, mod, ft, v[n], n) for n, ft in t[1])
        if k == "tup":
            return b"".join(self._enc(fam, mod, x, y, field) for x, y in zip(t[1], v))
        raise ValueError("a type the wire format does not state: %r" % (t,))

    def encode(self, fam, value):
        tag = self.tag[fam]
        head = bytes([tag]) if tag < 255 else bytes([255, tag - 255]) if tag < 510 else bytes([255, 255]) + (tag - 510).to_bytes(2, "big")
        t = self.arms[fam]
        return head + (b"" if t is None else self._enc(fam, self.cmd, t, value, None))

    def round_trip(self, body):
        """The family of a body this codec reads whole and writes back as the same bytes; raises otherwise."""
        fam, value = self.decode(body)
        if self.encode(fam, value) != body:
            raise ValueError("%s re-encodes by its declared type to different bytes" % fam)
        return fam, value


def expected(v):
    """A value of test/fixtures/codec_samples.json as this codec reads it back."""
    if isinstance(v, dict):
        if "$blob" in v:
            return bytes.fromhex(v["$blob"])
        if "$principal" in v:
            return bytes.fromhex(v["$principal"])
        if "$case" in v:
            return {"$case": v["$case"]} if "$value" not in v else v  # a case with a payload is compared whole
        return {k: expected(x) for k, x in v.items()}
    if isinstance(v, list):
        return [expected(x) for x in v]
    return v
