"""The audit index, recomputed from the blocks: who acted, in which company, at which height.

The contract keeps two tables, one entry per accepted block in each: under the
block's caller, the act's family and the company it acted in; under the company, the act's family and its caller.
This reader writes the same two tables by its own statement of where an act is - the company the command names, the
company of the record it names by id, the company a founding brings into existence, and none (0) for the platform
operator's acts and an uploader's - and the log reader compares them with the export's both ways, entry by entry.

Where an act is, is asked before the block is folded, as the contract asks it: an act that closes a record is in the
company the record was in.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import gate


class Audit:
    def __init__(self):
        self.by_caller = set()    # (height, caller hex, family, company)
        self.by_company = set()   # (height, company, family, caller hex)
        self.faults = []

    def company_before(self, block, store):
        """Where the act is, read before its fold: None for a founding, which is the company it brings into being."""
        cmd = block["command"]
        f = cmd["family"]
        if f == "bootstrapCompany":
            return None
        if f in gate.PLATFORM_ACTS or f in gate.UPLOAD_ACTS:
            return 0
        co = gate.Gate.company_of(store.gate, cmd, store)
        if co is None:
            raise ValueError("block %d: %s names a record of no company, and was accepted" % (block["index"], f))
        return co

    def write(self, block, company):
        caller = bytes(block["caller"]).hex()
        f = block["command"]["family"]
        h = block["index"]
        self.by_caller.add((h, caller, f, company))
        self.by_company.add((h, company, f, caller))

    def summary(self):
        return {"by caller": len(self.by_caller), "by company": len(self.by_company)}


def parse(line):
    """One printed entry: `audit_caller: height caller family company` or `audit_company: height company family caller`."""
    # split on single spaces: a principal of no bytes prints as no hex digits, an empty field - the last one, under a
    # company, lost with the line's trailing space when the reader strips it
    parts = line.rstrip("\n").split(" ")
    if len(parts) == 4:
        parts.append("")
    kind, h, a, f, b = parts
    if kind == "audit_caller:":
        return "caller", (int(h), a, f, int(b))
    return "company", (int(h), int(a), f, b)


def compare(mine, reported, faults):
    """Both tables, both ways: every entry the reader wrote the contract printed, and every entry it printed the
    reader wrote."""
    compared = 0
    for name, refolded, theirs in (("caller", mine.by_caller, reported["caller"]), ("company", mine.by_company, reported["company"])):
        for e in sorted(refolded - theirs):
            print("ORACLE: the log yields the audit entry under its %s %r, which the contract did not print" % (name, e))
            faults.append("audit entry under its %s missing" % name)
        for e in sorted(theirs - refolded):
            print("ORACLE: the contract printed the audit entry under its %s %r, which the log does not yield" % (name, e))
            faults.append("audit entry under its %s not on the log" % name)
        compared += len(refolded & theirs)
    return compared
