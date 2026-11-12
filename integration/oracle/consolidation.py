"""The consolidation families (348 to 355), decoded from their canonical bytes, re-encoded so the
command hash can be re-derived, and folded by rules written from the design:

  * a group is one row per parent company, the parent a member from its declaration; members join
    and leave while nothing is being consolidated; a partner in one member's books is LINKED to
    another member, and only a linked partner's lines are intercompany;
  * a consolidation opens over one PUBLISHED statement per standing member, all of one kind and
    one window, and records each statement's id, block and hash - the ledger reader has already
    refolded every one of those statements from the log and anchored it to the block before its
    own, so what this reader sums is what it has verified;
  * the consolidated lines are the members' statement lines summed by ACCOUNT CODE, plus, for every
    posted line over the window (closing moves excluded on an income statement) on a receivable,
    payable, income or expense account naming a linked partner, the reversal - an elimination entry
    per (member, counterparty, code) with the line's credit as its debit and its debit as its
    credit, and the same reversal into the line the kind maps that account to (the result line for
    profit-and-loss accounts on a balance sheet; on an income statement the account and the
    result line both, balances not at all);
  * on a trial balance or a balance sheet, debits less credits over every line is the DIFFERENCE,
    put on the parent's equity account the group names; an income statement takes none;
  * sealed at the slice that exhausts the last member's moves, with the log's tip - the block's own
    parent hash - and hashed as sha256("MENTAT-CONSOLIDATION-v1" ‖ group ‖ parent ‖ kind ‖ from ‖
    through ‖ block ‖ tip ‖ members-chain ‖ eliminations-chain ‖ lines-chain), restated here.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import hashlib

from canonical import write_nat, write_text

STATEMENT_KIND = {1: "trialBalance", 2: "balanceSheet", 3: "incomeStatement"}
KIND_BYTE = {v: k for k, v in STATEMENT_KIND.items()}
PROFIT_AND_LOSS = {"income", "expense", "roundingDifference"}
INTERCOMPANY = {"receivable", "payable", "income", "expense"}
ZERO_CODE = bytes(16)


def _members(r):
    n = r.len16()
    return [{"companyId": r.nat(), "statementId": r.nat()} for _ in range(n)]


READERS = {
    348: ("declareGroup", lambda r: {"facts": {"companyId": r.nat(), "name": r.text(), "differenceAccountId": r.nat()}}),
    349: ("addGroupMember", lambda r: {"groupId": r.nat(), "companyId": r.nat()}),
    350: ("removeGroupMember", lambda r: {"groupId": r.nat(), "companyId": r.nat(), "reason": r.text()}),
    351: ("linkIntercompanyPartner", lambda r: {"facts": {"groupId": r.nat(), "companyId": r.nat(), "partnerId": r.nat(), "counterpartyId": r.nat()}}),
    352: ("unlinkIntercompanyPartner", lambda r: {"groupId": r.nat(), "companyId": r.nat(), "partnerId": r.nat(), "reason": r.text()}),
    353: ("openConsolidation", lambda r: {"facts": {"groupId": r.nat(), "kind": STATEMENT_KIND[r.byte()], "fromDay": r.nat(), "throughDay": r.nat(), "members": _members(r)}}),
    354: ("consolidationSlice", lambda r: {"groupId": r.nat(), "consolidationId": r.nat(), "limit": r.nat()}),
    355: ("cancelConsolidation", lambda r: {"groupId": r.nat(), "consolidationId": r.nat(), "reason": r.text()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_consolidation_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def _open_bytes(c):
    f = c["facts"]
    out = write_nat(f["groupId"]) + bytes([KIND_BYTE[f["kind"]]]) + write_nat(f["fromDay"]) + write_nat(f["throughDay"]) + len(f["members"]).to_bytes(2, "big")
    for m in f["members"]:
        out += write_nat(m["companyId"]) + write_nat(m["statementId"])
    return out


ENCODERS = {
    "declareGroup": (348, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["name"]) + write_nat(c["facts"]["differenceAccountId"])),
    "addGroupMember": (349, lambda c: write_nat(c["groupId"]) + write_nat(c["companyId"])),
    "removeGroupMember": (350, lambda c: write_nat(c["groupId"]) + write_nat(c["companyId"]) + write_text(c["reason"])),
    "linkIntercompanyPartner": (351, lambda c: b"".join(write_nat(c["facts"][k]) for k in ("groupId", "companyId", "partnerId", "counterpartyId"))),
    "unlinkIntercompanyPartner": (352, lambda c: write_nat(c["groupId"]) + write_nat(c["companyId"]) + write_nat(c["partnerId"]) + write_text(c["reason"])),
    "openConsolidation": (353, _open_bytes),
    "consolidationSlice": (354, lambda c: write_nat(c["groupId"]) + write_nat(c["consolidationId"]) + write_nat(c["limit"])),
    "cancelConsolidation": (355, lambda c: write_nat(c["groupId"]) + write_nat(c["consolidationId"]) + write_text(c["reason"])),
}


def consolidation_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


def code_field(code):
    """An account code as the sixteen-byte field: UTF-8, zero-padded. The result line is the zero code."""
    b = code.encode("utf-8")
    return b + bytes(16 - len(b))


class Consolidation:
    def __init__(self):
        self.groups = {}           # id -> {companyId, name, differenceAccountId, members (set of standing), declaredBy}
        self.member_rows = {}      # id -> {groupId, companyId, isActive}
        self.links = {}            # id -> {groupId, companyId, partnerId, counterpartyId, isActive}
        self.consolidations = {}   # id -> row
        self.next_group = 1
        self.next_member = 1
        self.next_link = 1
        self.next_consolidation = 1
        self.faults = []

    # -- reads --

    def group_of_parent(self, company):
        for gid, g in self.groups.items():
            if g["companyId"] == company:
                return gid, g
        return None, None

    def standing(self, group):
        return sorted(m["companyId"] for m in self.member_rows.values() if m["groupId"] == group and m["isActive"])

    def link_of(self, group, company, partner):
        for lid, l in self.links.items():
            if l["groupId"] == group and l["companyId"] == company and l["partnerId"] == partner and l["isActive"]:
                return lid, l
        return None, None

    def open_of(self, group):
        for cid, x in self.consolidations.items():
            if x["groupId"] == group and x["state"] in ("gathering", "eliminating"):
                return cid
        return None

    # -- the families --

    def apply(self, block, ledger):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        caller = block["caller"]

        if f == "declareGroup":
            fc = c["facts"]
            a = ledger.accounts.get(fc["differenceAccountId"])
            if not fc["name"] or a is None or a["companyId"] != fc["companyId"] or a["deprecated"] or a["accountType"] != "equity":
                self.faults.append("block %d declared a group it could not" % idx)
            gid, g = self.group_of_parent(fc["companyId"])
            if g is not None:
                if self.open_of(gid) is not None:
                    self.faults.append("block %d changed a group while a consolidation was being built" % idx)
                g.update({"name": fc["name"], "differenceAccountId": fc["differenceAccountId"], "declaredBy": caller})
                return
            gid = self.next_group
            self.next_group += 1
            self.groups[gid] = {**fc, "declaredBy": caller}
            self.member_rows[self.next_member] = {"groupId": gid, "companyId": fc["companyId"], "isActive": True}
            self.next_member += 1
            return

        if f == "addGroupMember":
            g = self.groups.get(c["groupId"])
            if g is None or self.open_of(c["groupId"]) is not None or c["companyId"] in self.standing(c["groupId"]):
                self.faults.append("block %d added a member it could not" % idx)
                return
            for mid, m in self.member_rows.items():
                if m["groupId"] == c["groupId"] and m["companyId"] == c["companyId"] and not m["isActive"]:
                    m["isActive"] = True
                    return
            self.member_rows[self.next_member] = {"groupId": c["groupId"], "companyId": c["companyId"], "isActive": True}
            self.next_member += 1
            return

        if f == "removeGroupMember":
            g = self.groups.get(c["groupId"])
            if g is None or c["companyId"] not in self.standing(c["groupId"]) or c["companyId"] == g["companyId"] or self.open_of(c["groupId"]) is not None:
                self.faults.append("block %d removed a member it could not" % idx)
                return
            if any(l["isActive"] and l["groupId"] == c["groupId"] and c["companyId"] in (l["companyId"], l["counterpartyId"]) for l in self.links.values()):
                self.faults.append("block %d removed a member a link names" % idx)
                return
            for m in self.member_rows.values():
                if m["groupId"] == c["groupId"] and m["companyId"] == c["companyId"] and m["isActive"]:
                    m["isActive"] = False
            return

        if f == "linkIntercompanyPartner":
            fc = c["facts"]
            standing = self.standing(fc["groupId"])
            if (fc["groupId"] not in self.groups or fc["companyId"] not in standing or fc["counterpartyId"] not in standing
                    or fc["companyId"] == fc["counterpartyId"] or self.open_of(fc["groupId"]) is not None):
                self.faults.append("block %d linked a partner it could not" % idx)
                return
            lid, l = self.link_of(fc["groupId"], fc["companyId"], fc["partnerId"])
            if l is not None:
                l["counterpartyId"] = fc["counterpartyId"]
                return
            for l in self.links.values():
                if l["groupId"] == fc["groupId"] and l["companyId"] == fc["companyId"] and l["partnerId"] == fc["partnerId"] and not l["isActive"]:
                    l.update({"counterpartyId": fc["counterpartyId"], "isActive": True})
                    return
            self.links[self.next_link] = {**fc, "isActive": True}
            self.next_link += 1
            return

        if f == "unlinkIntercompanyPartner":
            lid, l = self.link_of(c["groupId"], c["companyId"], c["partnerId"])
            if l is None or self.open_of(c["groupId"]) is not None:
                self.faults.append("block %d unlinked a partner it could not" % idx)
                return
            l["isActive"] = False
            return

        if f == "openConsolidation":
            self._open(block, ledger)
            return

        if f == "cancelConsolidation":
            x = self.consolidations.get(c["consolidationId"])
            if x is None or x["groupId"] != c["groupId"] or x["state"] not in ("gathering", "eliminating"):
                self.faults.append("block %d cancelled a consolidation it could not" % idx)
                return
            x["state"] = "cancelled"
            return

        if f == "consolidationSlice":
            self._slice(block, ledger)
            return

    def _open(self, block, ledger):
        c = block["command"]
        fc = c["facts"]
        idx = block["index"]
        g = self.groups.get(fc["groupId"])
        if g is None:
            self.faults.append("block %d consolidated a group that does not exist" % idx)
            return
        bad = None
        if fc["fromDay"] > fc["throughDay"]:
            bad = "a window that ends before it starts"
        elif fc["kind"] != "incomeStatement" and fc["fromDay"] != 0:
            bad = "a cumulative statement with a start"
        elif self.open_of(fc["groupId"]) is not None:
            bad = "a second consolidation while one was being built"
        standing = self.standing(fc["groupId"])
        given = [m["companyId"] for m in fc["members"]]
        if bad is None and sorted(given) != standing:
            bad = "members that are not the group's"
        members = []
        for m in fc["members"]:
            s = ledger.statements.get(m["statementId"])
            if bad is None and (s is None or s["companyId"] != m["companyId"] or s["state"] != "published" or s["kind"] != fc["kind"]
                                or s["fromDay"] != fc["fromDay"] or s["throughDay"] != fc["throughDay"]):
                bad = "a statement that is not the member's, published, of the kind and over the window"
            if s is not None:
                members.append((m["companyId"], m["statementId"], s["atBlock"], s["hash"]))
        if bad is not None:
            self.faults.append("block %d opened a consolidation over %s" % (idx, bad))
            return
        cid = self.next_consolidation
        self.next_consolidation += 1
        self.consolidations[cid] = {
            "groupId": fc["groupId"], "companyId": g["companyId"], "kind": fc["kind"], "fromDay": fc["fromDay"], "throughDay": fc["throughDay"],
            "state": "gathering", "members": sorted(members), "member_index": 0, "consumed": 0,
            "atBlock": 0, "tip": bytes(32), "hash": bytes(32), "lines": None, "eliminations": None, "difference": 0, "publishedBy": block["caller"]}

    # -- the walk, emulated page by page --
    #
    # The contract reads each member's statement lines in pages, then each member's moves over the
    # window in pages, one page per slice; a short page moves to the next member, and past the last
    # member of the eliminations seals. The figures themselves are a fold over a locked window and
    # are computed whole at the seal.

    def _page_total(self, x, ledger):
        company, statement_id, _blk, _h = x["members"][x["member_index"]]
        if x["state"] == "gathering":
            return len(ledger.statement_lines.get(statement_id) or {})
        return sum(1 for m in ledger.moves.values() if m["companyId"] == company and x["fromDay"] <= m["businessDay"] <= x["throughDay"])

    def _slice(self, block, ledger):
        c = block["command"]
        idx = block["index"]
        x = self.consolidations.get(c["consolidationId"])
        if x is None or x["groupId"] != c["groupId"] or x["state"] not in ("gathering", "eliminating") or not 1 <= c["limit"] <= 1000:
            self.faults.append("block %d sliced a consolidation it could not" % idx)
            return
        total = self._page_total(x, ledger)
        taken = min(c["limit"], total - x["consumed"])
        x["consumed"] += taken
        if taken < c["limit"]:
            x["member_index"] += 1
            x["consumed"] = 0
            if x["member_index"] >= len(x["members"]):
                if x["state"] == "gathering":
                    x["state"] = "eliminating"
                    x["member_index"] = 0
                else:
                    self._seal(x, idx, block, ledger)

    def figures(self, x, ledger):
        """The lines by code and the eliminations, the reader's own fold."""
        kind = x["kind"]
        lines = {}
        elims = {}

        def add(code, d, c):
            t = lines.setdefault(code, [0, 0]); t[0] += d; t[1] += c

        # the members' statement lines, by code
        for company, sid, _blk, _h in x["members"]:
            for aid, (d, c) in (ledger.statement_lines.get(sid) or {}).items():
                add(ZERO_CODE if aid == 0 else code_field(ledger.accounts[aid]["code"]), d, c)
        # the reversals
        for company, _sid, _blk, _h in x["members"]:
            for mid, m in ledger.posted():
                if m["companyId"] != company or not (x["fromDay"] <= m["businessDay"] <= x["throughDay"]):
                    continue
                if kind == "incomeStatement" and m["moveType"] == "closing":
                    continue
                for l in ledger.lines[mid]:
                    if not l["partnerId"]:
                        continue
                    _lid, link = self.link_of(x["groupId"], company, l["partnerId"])
                    if link is None:
                        continue
                    a = ledger.accounts[l["accountId"]]
                    pl = a["accountType"] in PROFIT_AND_LOSS
                    if a["accountType"] not in INTERCOMPANY or (kind == "incomeStatement" and not pl):
                        continue
                    code = code_field(a["code"])
                    e = elims.setdefault((company, link["counterpartyId"], code), [0, 0])
                    e[0] += l["credit"]; e[1] += l["debit"]
                    if kind == "trialBalance":
                        add(code, l["credit"], l["debit"])
                    elif kind == "balanceSheet":
                        add(ZERO_CODE if pl else code, l["credit"], l["debit"])
                    else:
                        add(code, l["credit"], l["debit"])
                        add(ZERO_CODE, l["credit"], l["debit"])
        difference = 0
        if kind != "incomeStatement":
            difference = sum(d - c for d, c in lines.values())
            if difference != 0:
                g = self.groups[x["groupId"]]
                add(code_field(ledger.accounts[g["differenceAccountId"]]["code"]), -difference if difference < 0 else 0, difference if difference > 0 else 0)
        return lines, elims, difference

    @staticmethod
    def consolidation_hash(x, at_block, tip, lines, elims):
        chain = bytes(32)
        for company, sid, blk, h in x["members"]:
            chain = hashlib.sha256(chain + company.to_bytes(6, "big") + sid.to_bytes(6, "big") + blk.to_bytes(6, "big") + h).digest()
        echain = bytes(32)
        for (company, counterparty, code) in sorted(elims):
            d, c = elims[(company, counterparty, code)]
            echain = hashlib.sha256(echain + company.to_bytes(6, "big") + counterparty.to_bytes(6, "big") + code + d.to_bytes(8, "big") + c.to_bytes(8, "big")).digest()
        lchain = bytes(32)
        for code in sorted(lines):
            d, c = lines[code]
            lchain = hashlib.sha256(lchain + code + d.to_bytes(8, "big") + c.to_bytes(8, "big")).digest()
        dom = b"MENTAT-CONSOLIDATION-v1"
        return hashlib.sha256(len(dom).to_bytes(4, "big") + dom + x["groupId"].to_bytes(6, "big") + x["companyId"].to_bytes(6, "big")
                              + bytes([KIND_BYTE[x["kind"]]]) + x["fromDay"].to_bytes(3, "big") + x["throughDay"].to_bytes(3, "big")
                              + at_block.to_bytes(6, "big") + tip + chain + echain + lchain).digest()

    def _seal(self, x, idx, block, ledger):
        lines, elims, difference = self.figures(x, ledger)
        x["state"] = "published"
        x["atBlock"] = idx
        x["tip"] = block["parent"] or bytes(32)
        x["publishedBy"] = block["caller"]
        x["lines"] = lines
        x["eliminations"] = elims
        x["difference"] = difference
        x["hash"] = self.consolidation_hash(x, idx, x["tip"], lines, elims)

    # -- what the contract prints, recomputed --

    def consolidation_line(self, cid):
        """id groupId kind state fromDay throughDay members lines eliminations atBlock tip hash debits credits difference,
        then per elimination entry in index order: companyId counterpartyId code debit credit."""
        x = self.consolidations[cid]
        lines = x["lines"] or {}
        elims = x["eliminations"] or {}
        d = sum(v[0] for v in lines.values())
        c = sum(v[1] for v in lines.values())
        entries = tuple((company, counterparty, code.rstrip(b"\0").decode("utf-8"), elims[(company, counterparty, code)][0], elims[(company, counterparty, code)][1])
                        for (company, counterparty, code) in sorted(elims))
        return (x["groupId"], x["kind"], x["state"], x["fromDay"], x["throughDay"], len(x["members"]), len(lines), len(elims), x["atBlock"],
                x["tip"].hex(), x["hash"].hex(), d, c, x["difference"], entries)

    def summary(self):
        return {
            "groups": len(self.groups),
            "members": sum(1 for m in self.member_rows.values() if m["isActive"]),
            "links": sum(1 for l in self.links.values() if l["isActive"]),
            "consolidations": len(self.consolidations),
            "published": sum(1 for x in self.consolidations.values() if x["state"] == "published"),
            "eliminations": sum(len(x["eliminations"] or {}) for x in self.consolidations.values()),
            "faults": len(self.faults),
        }
