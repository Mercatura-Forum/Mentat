#!/usr/bin/env python3
"""The audit index's company, held to the gate's route: what an act is indexed under is where the gate found its company.

`State.auditCompany` reads the company an accepted act is indexed under from `Gate.route`: the command's own
`companyId`, the company of the record it names by id, the company a founding act brings into existence, or none.
"None" is a statement about the act, and this lint holds it to the act's holders, both ways:

  1. NO ARM NAMES A CONSTANT COMPANY. Every `co(...)` and `about(...)` arm passes a field of the command, never a
     number literal: a route that wrote `co(412, 1)` would index every such act under company 1.
  2. NO COMPANY ONLY WHERE THE HOLDERS ARE THE PLATFORM'S OR THE UPLOADER'S. An arm routed to `#platform` is a
     family held by the platform operator, its claim or its offer; an arm routed to `#upload` is a family held by
     the uploader; and every such family is routed so. A company's act routed to `#platform` would be indexed under
     no company - out of reach of the company's own reads - and held to the operator besides.
  3. ONE FOUNDING ARM, bringing a company into existence.

THE CONTROL runs first, on copies of the gate: one with an arm's company made a literal, one with a member's act
routed to the platform. Each must be refused, or this lint proves nothing.

Usage: audit_lint.py [src]

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import os
import re
import sys

ARM = re.compile(r'^      case \(#(\w+)\b[^\n]*?\) (co|about|of)\((\d+), ([^\n]*)\);$', re.M)
HOLDER = re.compile(r'^    \("(\w+)", (#\w+)')
NO_COMPANY_HOLDERS = {"#platform": "#platform", "#claim": "#platform", "#offered": "#platform", "#uploader": "#upload"}


def faults_of(gate_text):
    faults = []
    arms = ARM.findall(gate_text)
    body = gate_text[gate_text.index("public let HOLDERS"):]
    holders = {}
    for line in body.splitlines():
        m = HOLDER.match(line)
        if m:
            holders[m.group(1)] = m.group(2)
    if len(arms) != len(holders):
        faults.append("the route has %d arms and the holders %d entries" % (len(arms), len(holders)))
    founding = 0
    for family, kind, tag, args in arms:
        held = holders.get(family)
        if held is None:
            faults.append("%s: routed, but no holders" % family)
            continue
        if kind in ("co", "about"):
            company = args.split(",")[0].strip()
            if re.fullmatch(r'[0-9_]+', company):
                faults.append("A CONSTANT COMPANY: %s is routed to company %s whatever it names" % (family, company))
            if held in NO_COMPANY_HOLDERS:
                faults.append("%s is held by %s but routed to a company" % (family, held))
        else:
            source = args.strip()
            if source == "#founding":
                founding += 1
                if held != "#founder":
                    faults.append("%s is routed as a founding but held by %s" % (family, held))
            elif source == "#platform" or source.startswith("#upload"):
                kind_of = "#platform" if source == "#platform" else "#upload"
                if NO_COMPANY_HOLDERS.get(held) != kind_of:
                    faults.append("OF NO COMPANY WITHOUT THE HOLDERS FOR IT: %s is routed to %s but held by %s" % (family, kind_of, held))
            elif held in NO_COMPANY_HOLDERS:
                faults.append("%s is held by %s but routed to a record of a company" % (family, held))
    if founding != 1:
        faults.append("%d founding arms, not one" % founding)
    return faults, len(arms)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src")
    gate = open(os.path.join(src, "Gate.mo"), encoding="utf-8").read()

    # THE CONTROL: two faults put into copies of the gate, each refused
    m = re.search(r'^(      case \(#createAccount\b[^\n]*?\) co\(\d+, )([^\n]*?)(\);)$', gate, re.M)
    if not m:
        print("AUDIT LINT CONTROL BROKEN: no createAccount arm to put a constant company into")
        return 1
    constant = gate[:m.start()] + m.group(1) + "1" + m.group(3) + gate[m.end():]
    m2 = re.search(r'^(      case \(#createLead\b[^\n]*?\) )co\((\d+), [^\n]*?\);$', gate, re.M)
    if not m2:
        print("AUDIT LINT CONTROL BROKEN: no createLead arm to route to the platform")
        return 1
    platform = gate[:m2.start()] + m2.group(1) + "of(%s, #platform);" % m2.group(2) + gate[m2.end():]
    caught = 0
    for name, text, expect in (("a constant company", constant, "A CONSTANT COMPANY"),
                               ("a member's act routed to the platform", platform, "OF NO COMPANY WITHOUT THE HOLDERS")):
        f, _ = faults_of(text)
        if not any(expect in x for x in f):
            print("AUDIT LINT CONTROL BROKEN: %s was not refused" % name)
            return 1
        print("caught: %s" % name)
        caught += 1

    faults, arms = faults_of(gate)
    for f in faults:
        print("AUDIT LINT: " + f)
    print("count: route arms held to their holders = %d" % arms)
    print("count: faults put into copies of the gate, each refused = %d" % caught)
    if faults:
        print("AUDIT LINT FAILED")
        return 1
    print("AUDIT LINT GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
