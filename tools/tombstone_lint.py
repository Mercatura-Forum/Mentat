#!/usr/bin/env python3
"""No fold reads a range from its head in one page and takes the page as the whole answer.

`RowStore.page` stops after examining sixteen entries per row asked for, tombstones included, and
says so with a cursor; a caller that drops the cursor reads a range past sixteen tombstones as empty
or short (src/Lookup.mo says how that went wrong, and test/Tombstones.test.mo drives every kind of it
past the point). The cure is `Lookup.upTo` / `Lookup.firstOf`, which follow the cursor. This lint
keeps the cure in place: every `RowStore.page` call under src/ whose cursor argument is the literal
`null` must be a lookup at ONE EXACT KEY - the same expression for both ends of the range - or it is
red. A call with a cursor of its own (a walk that follows `next`, or a read that hands the cursor
back to its caller) is not this hazard and is not flagged. `src/Lookup.mo` is the one place a page
from the head is taken, because it is the place that follows the cursor.

Before it reads the tree it reads two lines it writes itself - a range from its head, and an exact
key - and must flag the first and pass the second: a lint that passes everything is not a lint.

Usage: tombstone_lint.py [src-dir]
Attribution: Thebes Core Team. Licence: Apache 2.0.
"""
import os
import re
import sys

CALL = re.compile(r"RowStore\.page\s*<")


def split_args(text, open_at):
    """The top-level arguments of the call whose '(' is at `open_at`, and the index after ')'."""
    depth, i, start, args = 0, open_at, open_at + 1, []
    in_str = False
    while i < len(text):
        ch = text[i]
        if in_str:
            if ch == "\\":
                i += 2; continue
            if ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                args.append(text[start:i].strip())
                return args, i + 1
        elif ch == "," and depth == 1:
            args.append(text[start:i].strip()); start = i + 1
        i += 1
    raise ValueError("an unbalanced call")


def findings(text):
    out = []
    for m in CALL.finditer(text):
        # past the type arguments to the call's own parenthesis
        j, depth = m.end(), 1
        while depth:
            depth += {"<": 1, ">": -1}.get(text[j], 0); j += 1
        while text[j].isspace():
            j += 1
        if text[j] != "(":
            continue
        args, _ = split_args(text, j)
        if len(args) != 7:
            continue
        _store, _decl, _index, lo, hi, cursor, _limit = args
        if cursor == "null" and lo != hi:
            out.append((text.count("\n", 0, m.start()) + 1, lo, hi))
    return out


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "src"
    # THE CONTROL
    hazard = 'let x = RowStore.page<R.Row>(st.rows, R.row, "by_state", lo, hi, null, 1);'
    exact = 'let y = RowStore.page<R.Row>(st.rows, R.row, "by_key", k, k, null, 1);'
    if len(findings(hazard)) != 1 or findings(exact):
        print("CONTROL BROKEN: the lint did not flag a range read from its head, or flagged an exact key")
        return 1
    bad, sites = [], 0
    for name in sorted(os.listdir(root)):
        if not name.endswith(".mo") or name == "Lookup.mo":
            continue
        text = open(os.path.join(root, name)).read()
        sites += len(CALL.findall(text))
        for line, lo, hi in findings(text):
            bad.append("%s/%s:%d  RowStore.page over [%s, %s] from its head, its cursor dropped" % (root, name, line, lo, hi))
    print("count: RowStore.page calls examined = %d" % sites)
    for b in bad:
        print("FROM THE HEAD: " + b)
    if bad:
        print("TOMBSTONE LINT FAILED: %d read(s) of a range in one page - use Lookup.upTo or Lookup.firstOf" % len(bad))
        return 1
    print("TOMBSTONE LINT GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
