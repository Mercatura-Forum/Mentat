#!/usr/bin/env python3
"""Every record a Studio field may be defined on is in the registry, and the registry reads each from its own store.

A Studio field is defined on a KIND OF RECORD, and a kind is a table whose rows name their company (src/StudioFold.mo).
The fold asks `State.recordOf` whether a record of a kind is there and whose it is; that function and the list of
kinds beside it, `State.RECORD_KINDS`, are written by this tool (`--write`) between two marker lines of src/State.mo,
and checked by it otherwise. The check holds:

  EVERY RECORD     the kinds are every declared table whose row type carries `companyId : Nat` (through an alias
                   to another module's type where it is one), and the company itself, whose company is its own id - 
                   no table missing and none extra;
  EVERY OTHER      every declared table without a company is classified here, as PART OF a record that carries
  TABLE            one (a line of its document) or PLATFORM-WIDE, and Studio's own three tables are left out; a
                   table without a company that is not classified, or a classified one that carries a company, is
                   red - a new table is a decision, not a silence;
  ITS OWN STORE    each case of `recordOf` reads the store the fingerprint sweeps for the same declaration, with the
                   declaration whose table is the case's name and the row type the fingerprint reads it as;
  THE LIST         `RECORD_KINDS` is exactly the cases, in order;
  THE TEXT         the block is the one this tool writes, byte for byte.

The case-by-case check does not use the writer: it parses the block back and holds every case to the declarations
and the fingerprint on its own, so a fault in the writer is caught by the reader too.

Before it reads the tree it reads a fixture tree of its own - a table with a company, one through an alias, a line,
and the company - and must pass it and flag each of four faults written into it; then it puts three faults into the
real tree's block in memory (a case removed, two stores swapped, a kind listed that is not a case) and must flag
each. A lint that passes everything is not a lint.

Usage: studio_lint.py [--write] [src-dir]
Attribution: Thebes Core Team. Licence: Apache 2.0.
"""
import os
import re
import sys
import tempfile

BEGIN = "  // ── THE RECORD KINDS: written by tools/studio_lint.py --write, and held to the tables by it ──────────────"
END = "  // ── the end of the record kinds ─────────────────────────────────────────────────────────────────────────"

# A table without a company is a part of a record that has one, or belongs to no company at all.
PART_OF = {
    "sequence": "a journal's numbering in a fiscal year",
    "close_line": "a line of a close run's plan",
    "close_move": "a move a close run posted",
    "ledger_statement_line": "a line of a ledger statement",
    "deferral_entry": "an entry of a deferral's schedule",
    "depreciation_entry": "an entry of an asset's depreciation",
    "expense_line": "a line of an expense claim",
    "consolidation_line": "a line of a consolidation",
    "payslip_line": "a line of a payslip",
    "pos_price": "a point-of-sale shop's price for a category",
    "pos_sale": "a sale of a point-of-sale session",
    "pos_kind": "a kind of goods a point-of-sale session sold",
    "rst_course": "a course of a restaurant tab",
    "rst_line": "a line of a restaurant tab",
    "rst_share": "a share of a restaurant tab's bill",
    "site_version": "a version of a website page",
    "web_listing": "a storefront's listing",
    "ctl_standing": "a company's controls standing, under the company's own id",
    "ctl_item": "an item of a screening profile's list",
    "ctl_count": "a fact a screening run counted",
    "ctl_mark": "a bill or an order a screening run marked",
}
PLATFORM = {
    "statutory_profile": "a jurisdiction's statutory payroll profile",
    "tax_bracket": "a bracket of a statutory profile",
    "platform": "the platform operator: the one principal the whole contract names, and the one it has offered the role to",
}
OWN = {"studio_field", "studio_rule", "studio_value"}
# the index of the log by caller and by company: a finding aid the fold writes at every accepted block, not a record
# anyone acts on, so no Studio field is defined on it
INDEX = {
    "audit_by_caller": "the log's blocks found by their caller",
    "audit_by_company": "the log's blocks found by their company",
}
COMPANY_TABLE = "company"

DECL = re.compile(r'public let (\w+)\s*:\s*RowStore\.Decl<(\w+)>\s*=\s*\{\s*table\s*=\s*"([^"]+)"', re.S)
IMPORT = re.compile(r'^import (\w+) "(\w+)";', re.M)
SECTION = re.compile(r'section<([\w.]+)>\(s, f, "[^"]+",\s*(s\.[\w.]+),\s*(\w+)\.(\w+),', re.S)
CASE = re.compile(r'^      case "([a-z0-9_]+)" \{ (.*) \};$', re.M)
HELD = re.compile(r'^held<([\w.]+)>\((s\.[\w.]+), (\w+)\.(\w+), id, func\(r : ([\w.]+)\) : Nat \{ r\.companyId \}\)$')
COMPANY_CASE = 'if (RowStore.has<Rows.Company>(s.companies, Rows.company, id)) #company(id) else #absent'


class Tree:
    """The declarations of a source tree, the types they read, and the stores the fingerprint sweeps."""

    def __init__(self, src, files=None):
        self.src = src
        self.files = files if files is not None else {
            f[:-3]: open(os.path.join(src, f)).read() for f in sorted(os.listdir(src)) if f.endswith(".mo")}
        self.decls = {}      # (module, name) -> (type, table)
        for mod, text in self.files.items():
            for m in DECL.finditer(text):
                self.decls[(mod, m.group(1))] = (m.group(2), m.group(3))

    def imports(self, mod):
        return {a: m for a, m in IMPORT.findall(self.files.get(mod, ""))}

    def has_company(self, mod, typ, seen=()):
        """Whether `typ` of `mod` carries `companyId : Nat`, following an alias to another module's type."""
        text = self.files.get(mod, "")
        m = re.search(r'public type ' + typ + r'\s*=\s*(\{.*?\n  \}|[\w.]+);', text, re.S)
        if m is None or (mod, typ) in seen:
            return None
        body = m.group(1)
        if body.startswith("{"):
            return bool(re.search(r'^\s*companyId\s*:\s*Nat\s*;', body, re.M))
        alias, _, other = body.partition(".")
        target = self.imports(mod).get(alias)
        return None if target is None else self.has_company(target, other, seen + ((mod, typ),))

    def sections(self):
        """(module, declaration) -> (store, row type) for every table the fingerprint sweeps, from src/State.mo."""
        state = self.files.get("State", "")
        imp = self.imports("State")
        out = {}
        for m in SECTION.finditer(state):
            rowtype, store, alias, name = m.groups()
            out[(imp.get(alias, alias), name)] = (store, rowtype, alias)
        return out


def classify(tree, part_of, platform, own, index=frozenset()):
    """The record kinds, and the faults of the classification."""
    faults, kinds = [], {}
    sections = tree.sections()
    tables = {}
    for (mod, name), (typ, table) in sorted(tree.decls.items()):
        if table in tables:
            faults.append("DECLARED TWICE: table %s" % table)
        tables[table] = (mod, name, typ)
    for table, (mod, name, typ) in sorted(tables.items()):
        carries = tree.has_company(mod, typ)
        if carries is None:
            faults.append("UNRESOLVED: the row type %s.%s of table %s" % (mod, typ, table))
            continue
        if table in index:
            # covered by the index's running digest, not swept row by row (src/AuditIndex.mo), and no record kind
            continue
        if (mod, name) not in sections:
            faults.append("UNSWEPT: table %s has no fingerprint section to read its store from" % table)
            continue
        store, rowtype, alias = sections[(mod, name)]
        if table in own:
            continue
        if table == COMPANY_TABLE:
            kinds[table] = ("company", store, rowtype, alias, name)
            continue
        if carries:
            if table in part_of or table in platform:
                faults.append("MISCLASSIFIED: table %s carries a company and is classified as without one" % table)
            kinds[table] = ("held", store, rowtype, alias, name)
        elif table not in part_of and table not in platform:
            faults.append("NOT CLASSIFIED: table %s names no company and is neither part of a record nor platform-wide" % table)
    for table in sorted(set(part_of) | set(platform) | set(own) | set(index)):
        if table not in tables:
            faults.append("CLASSIFIED BUT NOT DECLARED: table %s" % table)
    return kinds, faults, tables


def write_block(kinds):
    names = sorted(kinds)
    lines = [BEGIN,
             "",
             "  /// Every kind of record a Studio field may be defined on: each table whose rows name their company, and the",
             "  /// company itself. `tools/studio_lint.py` holds the list to the declarations both ways.",
             "  public let RECORD_KINDS : [Text] = ["]
    row = "   "
    for n in names:
        piece = ' "%s",' % n
        if len(row) + len(piece) > 118:
            lines.append(row)
            row = "   "
        row += piece
    lines.append(row)
    lines += ["  ];",
              "",
              "  func held<T>(store : RowStore.Store, decl : RowStore.Decl<T>, id : Nat, company : T -> Nat) : StudioFold.Record {",
              "    switch (RowStore.get<T>(store, decl, id)) { case (?r) #company(company(r)); case null #absent }",
              "  };",
              "",
              "  /// THE REGISTRY: a record of a kind by its id - there and whose, or not there - read from the store the",
              "  /// fingerprint sweeps for the kind's own declaration; `#unknownKind` for a name that is not a kind.",
              "  public func recordOf(s : State, record : Text, id : Nat) : StudioFold.Record {",
              "    switch (record) {"]
    for n in names:
        how, store, rowtype, alias, name = kinds[n]
        if how == "company":
            lines.append('      case "%s" { %s };' % (n, COMPANY_CASE))
        else:
            lines.append('      case "%s" { held<%s>(%s, %s.%s, id, func(r : %s) : Nat { r.companyId }) };' % (n, rowtype, store, alias, name, rowtype))
    lines += ["      case _ #unknownKind;",
              "    }",
              "  };",
              END]
    return "\n".join(lines) + "\n"


def block_of(state_text):
    a = state_text.find(BEGIN)
    b = state_text.find(END)
    if a < 0 or b < 0 or b < a:
        return None
    return state_text[a:b + len(END) + 1]


def verify_block(tree, block, kinds):
    """The block held to the declarations and the fingerprint case by case, without the writer."""
    faults = []
    sections = tree.sections()
    imp = tree.imports("State")
    by_table = {table: (mod, name, typ) for (mod, name), (typ, table) in tree.decls.items()}
    m = re.search(r'public let RECORD_KINDS : \[Text\] = \[(.*?)\];', block, re.S)
    listed = re.findall(r'"([a-z0-9_]+)"', m.group(1)) if m else []
    cases = CASE.findall(block)
    labels = [c[0] for c in cases]
    if listed != labels:
        faults.append("THE LIST: RECORD_KINDS is not the cases of recordOf, in order")
    if labels != sorted(labels) or len(set(labels)) != len(labels):
        faults.append("THE LIST: the cases are not each kind once, in order")
    missing = sorted(set(kinds) - set(labels))
    extra = sorted(set(labels) - set(kinds))
    for t in missing:
        faults.append("EVERY RECORD: table %s is a kind and recordOf has no case for it" % t)
    for t in extra:
        faults.append("EVERY RECORD: recordOf has a case %s that is not a kind" % t)
    for label, body in cases:
        if label == COMPANY_TABLE:
            if body != COMPANY_CASE:
                faults.append("ITS OWN STORE: the company's case does not read the companies by their own id")
            continue
        h = HELD.match(body)
        if h is None:
            faults.append("ITS OWN STORE: the case %s does not read a store of its declaration" % label)
            continue
        rowtype, store, alias, name, rowtype2 = h.groups()
        mod = imp.get(alias, alias)
        decl = tree.decls.get((mod, name))
        if decl is None or decl[1] != label:
            faults.append("ITS OWN STORE: the case %s reads the declaration %s.%s, whose table is not %s" % (label, alias, name, label))
            continue
        swept = sections.get((mod, name))
        if swept is None or swept[0] != store:
            faults.append("ITS OWN STORE: the case %s reads %s, and the fingerprint sweeps %s.%s from %s" % (label, store, alias, name, swept[0] if swept else "nowhere"))
        if swept is None or swept[1] != rowtype or rowtype2 != rowtype:
            faults.append("ITS OWN STORE: the case %s reads its rows as a type the fingerprint does not" % label)
    return faults


def check(src, part_of, platform, own, write=False, files=None, index=frozenset()):
    tree = Tree(src, files)
    kinds, faults, tables = classify(tree, part_of, platform, own, index)
    state = tree.files.get("State", "")
    want = write_block(kinds)
    block = block_of(state)
    if write:
        if block is None:
            raise SystemExit("studio_lint: src/State.mo has no marker lines to write the record kinds between")
        new = state.replace(block, want)
        with open(os.path.join(src, "State.mo"), "w") as f:
            f.write(new)
        return kinds, faults, tables
    if block is None:
        faults.append("THE TEXT: src/State.mo holds no record kinds between the marker lines")
        return kinds, faults, tables
    faults += verify_block(tree, block, kinds)
    if block != want:
        faults.append("THE TEXT: the record kinds are not the block this tool writes (run tools/studio_lint.py --write)")
    return kinds, faults, tables


FIXTURE = {
    "ARows": '''import B "BRows";
module {
  public type Thing = {
    companyId : Nat;
    name : Nat;
  };
  public let thing : RowStore.Decl<Thing> = { table = "a_thing"; idBytes = 6; };
  public type Line = {
    thingId : Nat;
  };
  public let line : RowStore.Decl<Line> = { table = "a_line"; idBytes = 6; };
  public type Run = B.Run;
  public let run : RowStore.Decl<Run> = { table = "a_run"; idBytes = 6; };
}
''',
    "BRows": '''module {
  public type Run = {
    companyId : Nat;
  };
}
''',
    "Rows": '''module {
  public type Company = {
    name : Nat;
  };
  public let company : RowStore.Decl<Company> = { table = "company"; idBytes = 6; };
}
''',
    "State": '''import ARows "ARows";
import Rows "Rows";
module {
    section<Rows.Company>(s, f, "company", s.companies, Rows.company, func(_r) { [] });
    section<ARows.Thing>(s, f, "a_thing", s.a.things, ARows.thing, func(_r) { [] });
    section<ARows.Line>(s, f, "a_line", s.a.lines, ARows.line, func(_r) { [] });
    section<ARows.Run>(s, f, "a_run", s.a.runs, ARows.run, func(_r) { [] });
%s}
''',
}


def self_test():
    """The lint on a tree of its own: green as written, red for each of four faults."""
    part = {"a_line": "a line of a thing"}
    tree = Tree("", dict(FIXTURE, State=FIXTURE["State"] % ""))
    kinds, faults, _ = classify(tree, part, {}, set())
    if faults or sorted(kinds) != ["a_run", "a_thing", "company"]:
        return "the fixture's kinds are %s with %s, not a_run, a_thing and company" % (sorted(kinds), faults)
    good = FIXTURE["State"] % (BEGIN[:0] + write_block(kinds))
    _, faults, _ = check("", part, {}, set(), files=dict(FIXTURE, State=good))
    if faults:
        return "the fixture as written is flagged: %s" % faults
    bad = [
        ("a line not classified", {}, dict(FIXTURE, State=good), "NOT CLASSIFIED"),
        ("a table with a company classified as a line", {"a_line": "", "a_thing": ""}, dict(FIXTURE, State=good), "MISCLASSIFIED"),
        ("a case removed", part, dict(FIXTURE, State=good.replace(re.search(r'      case "a_run".*\n', good).group(0), "")), "EVERY RECORD"),
        ("a case reading another table's store", part, dict(FIXTURE, State=good.replace("held<ARows.Thing>(s.a.things", "held<ARows.Thing>(s.a.runs")), "ITS OWN STORE"),
    ]
    for what, p, files, word in bad:
        _, faults, _ = check("", p, {}, set(), files=files)
        if not any(f.startswith(word) for f in faults):
            return "the fixture with %s was not flagged %s (%s)" % (what, word, faults)
    return None


def tree_control(src):
    """Three faults put into the real tree's block in memory, each of which the case-by-case check must flag."""
    tree = Tree(src)
    kinds, _, _ = classify(tree, PART_OF, PLATFORM, OWN, INDEX)
    block = write_block(kinds)
    cases = CASE.findall(block)
    held = [(l, b) for l, b in cases if b.startswith("held<")]
    if len(held) < 2:
        return 0, "the tree has fewer than two kinds to put faults into"
    (l1, b1), (l2, b2) = held[0], held[1]
    s1, s2 = HELD.match(b1).group(2), HELD.match(b2).group(2)
    faults_in = [
        ("a case removed", block.replace('      case "%s" { %s };\n' % (l2, b2), ""), "EVERY RECORD"),
        ("two stores swapped", block.replace("(%s," % s1, "(@@,").replace("(%s," % s2, "(%s," % s1).replace("(@@,", "(%s," % s2), "ITS OWN STORE"),
        ("a kind listed that is not a case", block.replace('"%s",' % l1, '"%s", "not_a_table",' % l1, 1), "THE LIST"),
    ]
    flagged = 0
    for what, text, word in faults_in:
        found = verify_block(tree, text, kinds)
        if not any(f.startswith(word) for f in found):
            return flagged, "%s was not flagged %s" % (what, word)
        flagged += 1
    return flagged, None


def main():
    args = [a for a in sys.argv[1:] if a != "--write"]
    write = "--write" in sys.argv[1:]
    src = args[0] if args else "src"
    broken = self_test()
    if broken:
        print("CONTROL BROKEN: " + broken)
        print("STUDIO LINT FAILED")
        return 1
    kinds, faults, tables = check(src, PART_OF, PLATFORM, OWN, write=write, index=INDEX)
    if write:
        print("studio_lint: wrote %d record kinds into %s" % (len(kinds), os.path.join(src, "State.mo")))
        kinds, faults, tables = check(src, PART_OF, PLATFORM, OWN, index=INDEX)
    flagged, broken = tree_control(src)
    if broken:
        print("CONTROL BROKEN: " + broken)
        faults.append("the tree control")
    for f in faults:
        print(f)
    print("count: tables declared = %d" % len(tables))
    print("count: record kinds a field may be defined on = %d" % len(kinds))
    print("count: tables part of a record = %d" % len(PART_OF))
    print("count: platform-wide tables = %d" % len(PLATFORM))
    print("count: Studio's own tables = %d" % len(OWN))
    print("count: index tables of the log, no record kind = %d" % len(INDEX))
    print("count: faults put into the tree's registry, each flagged = %d" % flagged)
    if faults:
        print("STUDIO LINT FAILED")
        return 1
    print("STUDIO LINT GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
