#!/usr/bin/env python3
"""Writes test/Camt053Fixtures.mo from test/fixtures/camt053/*.xml, each file a Text constant, so
the batteries and the export carry the very bytes the files hold and the reader compares them back.

  tools/camt_fixtures.py          rewrite the module
  tools/camt_fixtures.py --check  exit 1 if the module is not what the files say

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FIX = os.path.join(ROOT, "test", "fixtures", "camt053")
OUT = os.path.join(ROOT, "test", "Camt053Fixtures.mo")


def ident(name):
    return "".join(ch if ch.isalnum() else "_" for ch in name.rsplit(".", 1)[0]).upper()


def escape(t):
    return t.replace("\\", "\\\\").replace("\"", "\\\"")


def render():
    out = ["// Camt053Fixtures.mo - the camt.053 fixtures under test/fixtures/camt053/, byte for byte, written",
           "// by tools/camt_fixtures.py. Edit the files, not this module; the gate checks the two agree.",
           "//",
           "// Attribution: Thebes Core Team. Licence: Apache 2.0.",
           "", "module {", ""]
    for name in sorted(os.listdir(FIX)):
        if not name.endswith(".xml"):
            continue
        text = open(os.path.join(FIX, name), encoding="utf-8").read()
        out.append("  /// %s" % name)
        out.append("  public let %s : Text = \"%s\";" % (ident(name), escape(text).replace("\n", "\\n")))
        out.append("")
    out.append("}")
    return "\n".join(out) + "\n"


def main():
    text = render()
    if "--check" in sys.argv:
        if not os.path.exists(OUT) or open(OUT, encoding="utf-8").read() != text:
            print("camt_fixtures: test/Camt053Fixtures.mo is not what test/fixtures/camt053/ says; run tools/camt_fixtures.py")
            return 1
        print("count: camt.053 fixtures carried = %d" % sum(1 for n in os.listdir(FIX) if n.endswith(".xml")))
        return 0
    open(OUT, "w", encoding="utf-8").write(text)
    print("wrote %s" % OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
