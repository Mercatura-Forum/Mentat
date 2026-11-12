"""The studio families (593 to 598), decoded from their canonical bytes, re-encoded so the command hash can be
re-derived, and folded by rules written from the design:

  * A FIELD IS DEFINED ON A KIND OF RECORD by an administrator of the company in standing, with the first version
    of its rule: a caption, a code free on that kind, normalised, a word, at most sixteen bytes; a shape its type
    takes - a text one to 512 bytes wide, a number one to eighteen digits with at most six (and no more than its
    digits) after the point, a day, a flag and a choice of no width; unique only for a text, a number or a day;
    choices, at most sixteen, each a code and offered once, for a choice field and no other;
  * A RULE is a version of the field's rule, recorded by an administrator on an active field and different from
    the one in force: whether a value may be cleared, bounds within the range the type takes (a text's bytes, a
    number at the field's scale, a day; none for a flag or a choice), the minimum not above the maximum, and the
    roles that write the field, at least one, each named once;
  * AN AMENDMENT changes the caption, widens the width and extends the choices, every choice offered before in
    its place; a RETIRED field keeps its values and takes no more;
  * A VALUE is a writer's - a member in standing, not suspended, whose role the rule in force names - on a record
    of the field's kind, there, of the field's company; of the field's type and width, within the bounds of the
    rule in force, a choice one of the field's choices; a unique field's value held by no other record; never the
    value the record already holds under the rule in force. A value CLEARED stays as a row, not set, and a value
    the rule in force requires is never cleared.

This reader recomputes every value's fingerprint from the bytes the command carried, re-adds every field's count
of values from the rows it folded, and re-derives which values the rule in force would now refuse. A record is
held to the readers that watched it: the company to the store, a department and a channel to the discussion
reader, an article to the knowledge reader. A field on any other kind is a fault here, because this reader would
otherwise take on trust a record it never saw.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import hashlib

from canonical import write_nat, write_text

TYPES = {1: "choice", 2: "day", 3: "flag", 4: "number", 5: "text"}
STATES = {"active": 1, "retired": 2}
ROLES = {1: "CompanyAdmin", 2: "HR", 3: "Director", 4: "Manager", 5: "Employee", 6: "Auditor", 7: "Drafter"}
# the roles that hold no act: the auditor reads, the drafter only proposes drafts
NO_ACT = {"Auditor", "Drafter"}
ROLE_BYTE = {v: k for k, v in ROLES.items()}
CODE_BYTES = 16
MAX_CHOICES = 16
TEXT_MAX = 512
DIGITS_MAX = 18
SCALE_MAX = 6
DAY_BYTES = 3
MONEY_SIGNED_BYTES = 9
MAX_TEXT = 4_000
# the kinds of record this reader holds a value's record to
KINDS = ("company", "department", "channel", "kb_article")


def zig(i):
    return i * 2 if i >= 0 else -i * 2 - 1


def zag(n):
    return n // 2 if n % 2 == 0 else -((n + 1) // 2)


def write_bool(b):
    return b"\x01" if b else b"\x00"


def write_len16(n):
    return n.to_bytes(2, "big")


def write_texts(xs):
    return write_len16(len(xs)) + b"".join(write_text(x) for x in xs)


def write_bound(b):
    return b"\x00" if b is None else b"\x01" + write_nat(zig(b))


def read_list(r, fn):
    return [fn() for _ in range(r.len16())]


def read_bound(r):
    z = r.opt_nat()
    return None if z is None else zag(z)


def read_field(r):
    return {"companyId": r.nat(), "record": r.text(), "code": r.text(), "caption": r.text(), "valueType": r.nat8(),
            "width": r.nat(), "scale": r.nat(), "unique": r.bool(), "choices": read_list(r, r.text)}


def write_field(f):
    return (write_nat(f["companyId"]) + write_text(f["record"]) + write_text(f["code"]) + write_text(f["caption"])
            + bytes([f["valueType"]]) + write_nat(f["width"]) + write_nat(f["scale"]) + write_bool(f["unique"])
            + write_texts(f["choices"]))


def read_rule(r):
    return {"companyId": r.nat(), "required": r.bool(), "minimum": read_bound(r), "maximum": read_bound(r),
            "writers": read_list(r, r.nat8)}


def write_rule(f):
    return (write_nat(f["companyId"]) + write_bool(f["required"]) + write_bound(f["minimum"]) + write_bound(f["maximum"])
            + write_len16(len(f["writers"])) + bytes(f["writers"]))


def read_amend(r):
    return {"companyId": r.nat(), "caption": r.text(), "width": r.nat(), "choices": read_list(r, r.text)}


def write_amend(f):
    return write_nat(f["companyId"]) + write_text(f["caption"]) + write_nat(f["width"]) + write_texts(f["choices"])


def read_value(r):
    return {"companyId": r.nat(), "fieldId": r.nat(), "recordId": r.nat(), "text": r.text(), "number": zag(r.nat()),
            "day": r.nat(), "flag": r.bool(), "choice": r.text()}


def write_value(f):
    return (write_nat(f["companyId"]) + write_nat(f["fieldId"]) + write_nat(f["recordId"]) + write_text(f["text"])
            + write_nat(zig(f["number"])) + write_nat(f["day"]) + write_bool(f["flag"]) + write_text(f["choice"]))


READERS = {
    593: ("defineStudioField", lambda r: {"facts": read_field(r), "rule": read_rule(r)}),
    594: ("amendStudioField", lambda r: {"fieldId": r.nat(), "facts": read_amend(r)}),
    595: ("retireStudioField", lambda r: {"companyId": r.nat(), "fieldId": r.nat()}),
    596: ("setStudioRule", lambda r: {"fieldId": r.nat(), "facts": read_rule(r)}),
    597: ("setStudioValue", lambda r: {"facts": read_value(r)}),
    598: ("clearStudioValue", lambda r: {"companyId": r.nat(), "fieldId": r.nat(), "recordId": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_studio_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "defineStudioField": (593, lambda c: write_field(c["facts"]) + write_rule(c["rule"])),
    "amendStudioField": (594, lambda c: write_nat(c["fieldId"]) + write_amend(c["facts"])),
    "retireStudioField": (595, lambda c: write_nat(c["companyId"]) + write_nat(c["fieldId"])),
    "setStudioRule": (596, lambda c: write_nat(c["fieldId"]) + write_rule(c["facts"])),
    "setStudioValue": (597, lambda c: write_value(c["facts"])),
    "clearStudioValue": (598, lambda c: write_nat(c["companyId"]) + write_nat(c["fieldId"]) + write_nat(c["recordId"])),
}


def studio_command_bytes(cmd):
    tag, enc = ENCODERS[cmd["family"]]
    return put_tag(tag) + enc(cmd)


def normalise(name):
    """Lower-case ASCII only and trim spaces, tabs and line ends - the contract's rule, restated."""
    lowered = "".join(chr(ord(ch) + 32) if "A" <= ch <= "Z" else ch for ch in name)
    return lowered.strip(" \t\n\r")


def code_of(text):
    """A code as the row keeps it, or None where the contract refuses it: normalised, a word, at most sixteen bytes,
    reading back as written (no NUL at its end, which the padding would swallow)."""
    n = normalise(text)
    b = n.encode("utf-8")
    if not n or len(b) > CODE_BYTES or b.endswith(b"\x00"):
        return None
    return n


def choices_of(choices):
    if len(choices) > MAX_CHOICES:
        return None
    out = []
    for t in choices:
        n = code_of(t)
        if n is None or n in out:
            return None
        out.append(n)
    return out


def number_max(digits):
    return 10 ** digits - 1


def shape_ok(t, width, scale, unique, choices):
    lo, hi = {"text": (1, TEXT_MAX), "number": (1, DIGITS_MAX)}.get(t, (0, 0))
    if width < lo or width > hi:
        return False
    if t == "number":
        if scale > SCALE_MAX or scale > width:
            return False
    elif scale != 0:
        return False
    if unique and t in ("flag", "choice"):
        return False
    return bool(choices) if t == "choice" else not choices


def bound_range(t, width):
    if t == "text":
        return (0, width)
    if t == "number":
        return (-number_max(width), number_max(width))
    if t == "day":
        return (1, 256 ** DAY_BYTES - 1)
    return None


def rule_ok(t, width, r):
    rng = bound_range(t, width)
    if rng is None:
        if r["minimum"] is not None or r["maximum"] is not None:
            return False
    else:
        lo, hi = rng
        for b in (r["minimum"], r["maximum"]):
            if b is not None and not lo <= b <= hi:
                return False
        if r["minimum"] is not None and r["maximum"] is not None and r["minimum"] > r["maximum"]:
            return False
    roles = r["writers"]
    # the auditor holds no act, so a rule never names it a writer
    return bool(roles) and all(x in ROLES and ROLES[x] not in NO_ACT for x in roles) and len(set(roles)) == len(roles)


def writers_mask(roles):
    return sum(1 << (b - 1) for b in roles)


def canonical(t, text, number, day, flag, choice):
    """The bytes a value's fingerprint is taken over: a text's own bytes, a number zigzagged in nine bytes, a day in
    three, a flag as 2 or 1, a choice's ordinal."""
    if t == "text":
        return text.encode("utf-8")
    if t == "number":
        return zig(number).to_bytes(MONEY_SIGNED_BYTES, "big")
    if t == "day":
        return day.to_bytes(DAY_BYTES, "big")
    if t == "flag":
        return bytes([2 if flag else 1])
    return bytes([choice])


class Studio:
    def __init__(self):
        self.fields = {}
        self.field_of = {}       # (company, kind, code) -> field id
        self.rules = {}
        self.rule_of = {}        # (field id, version) -> rule id
        self.values = {}
        self.value_of = {}       # (field id, record id) -> value id
        self.next_field = 1
        self.next_rule = 1
        self.next_value = 1
        self.counts_readded = 0
        self.hashes_recomputed = 0
        self.records_held = 0
        self.faults = []

    # -- the rules, restated --

    def role_in_standing(self, store, co, caller):
        d = store.discuss
        if co not in store.companies or not d.is_member(co, caller) or (co, caller) in d.suspended:
            return None
        return d.roles.get((co, caller))

    def record_company(self, store, kind, rid):
        """The company a record of a kind belongs to, held to the reader that watched it, or None where it is not
        there."""
        if kind == "company":
            return rid if rid in store.companies else None
        if kind == "department":
            x = store.discuss.departments.get(rid)
        elif kind == "channel":
            x = store.discuss.channels.get(rid)
        else:
            x = store.knowledge.articles.get(rid)
        return None if x is None else x["companyId"]

    def in_force(self, fid):
        return self.rules[self.rule_of[(fid, self.fields[fid]["ruleVersion"])]]

    def within(self, x, rule, v):
        t = x["valueType"]
        if t in ("flag", "choice"):
            return True
        measure = len(v["text"].encode("utf-8")) if t == "text" else (v["number"] if t == "number" else v["day"])
        return ((rule["minimum"] is None or measure >= rule["minimum"])
                and (rule["maximum"] is None or measure <= rule["maximum"]))

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = bytes(block["caller"])

        def fault(what):
            self.faults.append("block %d %s" % (idx, what))

        def administrator(co):
            return self.role_in_standing(store, co, caller) == "CompanyAdmin"

        def field(co, fid):
            x = self.fields.get(fid)
            return x if x is not None and x["companyId"] == co else None

        def record_rule(co, fid, version, r):
            rid = self.next_rule
            self.next_rule += 1
            self.rules[rid] = {"companyId": co, "fieldId": fid, "version": version, "required": r["required"],
                               "minimum": r["minimum"], "maximum": r["maximum"], "writers": writers_mask(r["writers"]),
                               "setBy": caller, "day": day}
            self.rule_of[(fid, version)] = rid

        if f == "defineStudioField":
            fc, r = c["facts"], c["rule"]
            co = fc["companyId"]
            t = TYPES.get(fc["valueType"])
            code = code_of(fc["code"])
            choices = choices_of(fc["choices"])
            if fc["record"] not in KINDS:
                fault("defined a field on a kind of record this reader holds no record of: %r" % fc["record"])
                return
            if (not administrator(co) or r["companyId"] != co or t is None or not fc["caption"] or len(fc["caption"]) > MAX_TEXT
                    or code is None or (co, fc["record"], code) in self.field_of or choices is None
                    or not shape_ok(t, fc["width"], fc["scale"], fc["unique"], choices) or not rule_ok(t, fc["width"], r)):
                fault("defined a field it could not")
                return
            fid = self.next_field
            self.next_field += 1
            self.fields[fid] = {"companyId": co, "kind": fc["record"], "code": code, "valueType": t, "width": fc["width"],
                                "scale": fc["scale"], "unique": fc["unique"], "choices": choices, "state": "active",
                                "ruleVersion": 1, "values": 0, "definedBy": caller, "caption": fc["caption"]}
            self.field_of[(co, fc["record"], code)] = fid
            record_rule(co, fid, 1, r)
            return

        if f == "amendStudioField":
            a = c["facts"]
            x = field(a["companyId"], c["fieldId"])
            choices = choices_of(a["choices"])
            if (not administrator(a["companyId"]) or x is None or x["state"] == "retired" or not a["caption"]
                    or len(a["caption"]) > MAX_TEXT or a["width"] < x["width"] or choices is None
                    or choices[:len(x["choices"])] != x["choices"] or len(choices) < len(x["choices"])
                    or not shape_ok(x["valueType"], a["width"], x["scale"], x["unique"], choices)
                    or (a["caption"] == x["caption"] and a["width"] == x["width"] and len(choices) == len(x["choices"]))):
                fault("amended a field it could not")
                return
            x.update(caption=a["caption"], width=a["width"], choices=choices)
            return

        if f == "retireStudioField":
            x = field(c["companyId"], c["fieldId"])
            if not administrator(c["companyId"]) or x is None or x["state"] == "retired":
                fault("retired a field it could not")
                return
            x["state"] = "retired"
            return

        if f == "setStudioRule":
            r = c["facts"]
            co = r["companyId"]
            x = field(co, c["fieldId"])
            if not administrator(co) or x is None or x["state"] == "retired" or not rule_ok(x["valueType"], x["width"], r):
                fault("recorded a rule it could not")
                return
            now = self.in_force(c["fieldId"])
            if (now["required"], now["minimum"], now["maximum"], now["writers"]) == (r["required"], r["minimum"], r["maximum"], writers_mask(r["writers"])):
                fault("recorded the rule in force again")
                return
            x["ruleVersion"] += 1
            record_rule(co, c["fieldId"], x["ruleVersion"], r)
            return

        def writable(co, fid):
            role = self.role_in_standing(store, co, caller)
            x = field(co, fid)
            if role is None or x is None or x["state"] == "retired":
                return None
            rule = self.in_force(fid)
            return (x, rule) if rule["writers"] & (1 << (ROLE_BYTE[role] - 1)) else None

        if f == "setStudioValue":
            v = c["facts"]
            got = writable(v["companyId"], v["fieldId"])
            if got is None:
                fault("let somebody write a value who may not")
                return
            x, rule = got
            if self.record_company(store, x["kind"], v["recordId"]) != x["companyId"]:
                fault("set a value on a record that is not the field's company's %s" % x["kind"])
                return
            self.records_held += 1
            t = x["valueType"]
            choice = 0
            ok = True
            if t == "text":
                n = len(v["text"].encode("utf-8"))
                ok = 1 <= n <= x["width"] and len(v["text"]) <= MAX_TEXT
            elif t == "number":
                ok = abs(v["number"]) <= number_max(x["width"])
            elif t == "day":
                ok = 1 <= v["day"] < 256 ** DAY_BYTES
            elif t == "choice":
                n = normalise(v["choice"])
                choice = x["choices"].index(n) + 1 if n in x["choices"] else 0
                ok = choice != 0
            number = v["number"] if t == "number" else 0
            vday = v["day"] if t == "day" else 0
            flag = t == "flag" and v["flag"]
            text = v["text"] if t == "text" else ""
            row = {"companyId": v["companyId"], "fieldId": v["fieldId"], "recordId": v["recordId"], "isSet": True, "text": text,
                   "number": number, "day": vday, "flag": flag, "choice": choice, "ruleVersion": x["ruleVersion"],
                   "hash": hashlib.sha256(canonical(t, text, number, vday, flag, choice)).digest(), "setBy": caller, "setDay": day}
            if not ok or not self.within(x, rule, row):
                fault("admitted a value its field's type, width or rule refuses")
                return
            key = (v["fieldId"], v["recordId"])
            held = self.values.get(self.value_of.get(key))
            if held is not None and held["isSet"] and held["hash"] == row["hash"] and held["ruleVersion"] == row["ruleVersion"]:
                fault("set the value a record already holds under the rule in force")
                return
            if x["unique"] and any(o["fieldId"] == v["fieldId"] and o["isSet"] and o["hash"] == row["hash"] and o["recordId"] != v["recordId"]
                                   for o in self.values.values()):
                fault("let two records hold one unique value")
                return
            if held is None:
                self.value_of[key] = self.next_value
                self.next_value += 1
                x["values"] += 1
            elif not held["isSet"]:
                x["values"] += 1
            self.values[self.value_of[key]] = row
            return

        if f == "clearStudioValue":
            got = writable(c["companyId"], c["fieldId"])
            held = self.values.get(self.value_of.get((c["fieldId"], c["recordId"])))
            if got is None or held is None or not held["isSet"] or got[1]["required"]:
                fault("cleared a value it could not")
                return
            held.update(isSet=False, setBy=caller, setDay=day)
            got[0]["values"] -= 1
            return

    # -- what the contract prints, recomputed --

    def field_line(self, fid, store):
        """companyId kind code type width scale unique choices state ruleVersion values definedBy - the values
        re-added from the rows this reader folded"""
        x = self.fields[fid]
        self.counts_readded += 1
        values = sum(1 for v in self.values.values() if v["fieldId"] == fid and v["isSet"])
        if values != x["values"]:
            self.faults.append("field %d counts %d value(s), its rows hold %d" % (fid, x["values"], values))
        return (x["companyId"], x["kind"], x["code"], {v: k for k, v in TYPES.items()}[x["valueType"]], x["width"], x["scale"],
                int(x["unique"]), len(x["choices"]), STATES[x["state"]], x["ruleVersion"], values,
                store.discuss.membership_id(x["companyId"], x["definedBy"]))

    def rule_line(self, rid, store):
        r = self.rules[rid]
        bound = lambda b: "-" if b is None else str(b)  # noqa: E731
        return (r["fieldId"], r["version"], int(r["required"]), bound(r["minimum"]), bound(r["maximum"]), r["writers"],
                store.discuss.membership_id(r["companyId"], r["setBy"]), r["day"])

    def value_line(self, vid, store):
        v = self.values[vid]
        self.hashes_recomputed += 1
        return (v["fieldId"], v["recordId"], int(v["isSet"]), v["number"], v["day"], int(v["flag"]), v["choice"], v["ruleVersion"],
                store.discuss.membership_id(v["companyId"], v["setBy"]), v["setDay"], v["hash"].hex())

    def nonconforming(self):
        """The set values the rule in force would refuse, re-derived over every field."""
        return sum(1 for v in self.values.values()
                   if v["isSet"] and not self.within(self.fields[v["fieldId"]], self.in_force(v["fieldId"]), v))

    def summary(self):
        return {"fields": len(self.fields), "rules": len(self.rules), "values": len(self.values),
                "values set": sum(1 for v in self.values.values() if v["isSet"]), "faults": len(self.faults)}
