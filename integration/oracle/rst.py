"""The restaurant families (407 to 414), decoded from their canonical bytes, re-encoded so the command
hash can be re-derived, and folded by rules written from the design:

  * a TABLE is a shop's, seats so many, and holds at most one open tab;
  * a TAB is opened by a member inside the shop's live till session, for covers the table seats;
    courses are ordered against it under their ordinal, each line a category on the shop's list;
    a course is sent to the kitchen once and takes no more; a line is voided by anyone while its
    course is unsent and, once the kitchen has it, only by somebody other than the one who ordered
    it; a tab is cancelled only with nothing cooked standing;
  * THE BILL IS SPLIT BY A RECORDED RULE: the lines standing priced by the shop's list, the total
    divided into as many shares as tenders - evenly or by weights - by the largest-remainder rule,
    every share's tender held to it, and the whole rung up as ONE SALE through this reader's own
    till fold by the session's cashier. This reader recomputes every share from the sale's total.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text

MAX_SEATS = 1_000
MAX_COURSES = 12
MAX_COURSE_LINES = 50
MAX_TAB_LINES = 200
MAX_LINE_QUANTITY = 1_000_000_000
MAX_SHARES = 50
MAX_WEIGHT = 1_000_000
MAX_MONEY = 1_000_000_000_000_000

SPLIT_RULES = {1: "evenly", 2: "by-weights"}


def _read_course(r):
    company = r.nat()
    tab = r.nat()
    course = r.nat()
    n = r.nat()
    lines = [{"categoryId": r.nat(), "quantity": r.nat()} for _ in range(n)]
    return {"facts": {"companyId": company, "tabId": tab, "course": course, "lines": lines}}


def _read_settle(r):
    company = r.nat()
    tab = r.nat()
    rule_byte = r.nat8()
    if rule_byte not in SPLIT_RULES:
        raise ValueError("a split rule byte nobody defined: %d" % rule_byte)
    rule = SPLIT_RULES[rule_byte]
    nw = r.nat()
    weights = [r.nat() for _ in range(nw)]
    nt = r.nat()
    tenders = [{"cash": r.nat(), "card": r.nat()} for _ in range(nt)]
    return {"facts": {"companyId": company, "tabId": tab, "rule": rule, "weights": weights, "tenders": tenders}}


READERS = {
    407: ("declareTable", lambda r: {"facts": {"companyId": r.nat(), "shopId": r.nat(), "code": r.text(), "name": r.text(), "seats": r.nat()}}),
    408: ("retireTable", lambda r: {"companyId": r.nat(), "tableId": r.nat(), "reason": r.text()}),
    409: ("openTab", lambda r: {"facts": {"companyId": r.nat(), "sessionId": r.nat(), "tableId": r.nat(), "covers": r.nat()}}),
    410: ("orderCourse", _read_course),
    411: ("voidTabLine", lambda r: {"companyId": r.nat(), "tabId": r.nat(), "lineId": r.nat(), "reason": r.text()}),
    412: ("sendCourse", lambda r: {"companyId": r.nat(), "tabId": r.nat(), "course": r.nat()}),
    413: ("cancelTab", lambda r: {"companyId": r.nat(), "tabId": r.nat(), "reason": r.text()}),
    414: ("settleTab", _read_settle),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_rst_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def _write_course(c):
    f = c["facts"]
    out = write_nat(f["companyId"]) + write_nat(f["tabId"]) + write_nat(f["course"]) + write_nat(len(f["lines"]))
    for l in f["lines"]:
        out += write_nat(l["categoryId"]) + write_nat(l["quantity"])
    return out


def _write_settle(c):
    f = c["facts"]
    rule_byte = {v: k for k, v in SPLIT_RULES.items()}[f["rule"]]
    out = write_nat(f["companyId"]) + write_nat(f["tabId"]) + bytes([rule_byte]) + write_nat(len(f["weights"]))
    for w in f["weights"]:
        out += write_nat(w)
    out += write_nat(len(f["tenders"]))
    for t in f["tenders"]:
        out += write_nat(t["cash"]) + write_nat(t["card"])
    return out


ENCODERS = {
    "declareTable": (407, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["shopId"]) + write_text(c["facts"]["code"]) + write_text(c["facts"]["name"]) + write_nat(c["facts"]["seats"])),
    "retireTable": (408, lambda c: write_nat(c["companyId"]) + write_nat(c["tableId"]) + write_text(c["reason"])),
    "openTab": (409, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["sessionId"]) + write_nat(c["facts"]["tableId"]) + write_nat(c["facts"]["covers"])),
    "orderCourse": (410, _write_course),
    "voidTabLine": (411, lambda c: write_nat(c["companyId"]) + write_nat(c["tabId"]) + write_nat(c["lineId"]) + write_text(c["reason"])),
    "sendCourse": (412, lambda c: write_nat(c["companyId"]) + write_nat(c["tabId"]) + write_nat(c["course"])),
    "cancelTab": (413, lambda c: write_nat(c["companyId"]) + write_nat(c["tabId"]) + write_text(c["reason"])),
    "settleTab": (414, _write_settle),
}


def rst_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


def split(total, weights):
    """THE SPLIT, by the largest-remainder rule: every share its whole part of total × weight over the
    weights' sum; the minor units left over, one each, to the shares with the largest remainders,
    an earlier share before a later one where they tie."""
    n = len(weights)
    s = sum(weights)
    if n == 0 or s == 0:
        return []
    base = [total * w // s for w in weights]
    rem = [total * w % s for w in weights]
    leftover = total - sum(base)
    order = sorted(range(n), key=lambda i: (-rem[i], i))
    for i in order[:leftover]:
        base[i] += 1
    return base


class Rst:
    def __init__(self):
        self.tables = {}
        self.tabs = {}
        self.courses = {}
        self.lines = {}
        self.shares = {}
        self.next_table = 1
        self.next_tab = 1
        self.next_course = 1
        self.next_line = 1
        self.next_share = 1
        self.shares_recomputed = 0
        self.faults = []

    # -- reads --

    def table_by_code(self, company, code):
        for tid, t in self.tables.items():
            if t["companyId"] == company and t["code"] == code:
                return tid, t
        return None, None

    def open_tab_of(self, table_id):
        for xid, x in sorted(self.tabs.items()):
            if x["tableId"] == table_id and x["state"] == "open":
                return xid
        return None

    def course_of(self, tab_id, ordinal):
        for kid, k in self.courses.items():
            if k["tabId"] == tab_id and k["ordinal"] == ordinal:
                return kid, k
        return None, None

    def courses_of(self, tab_id):
        return [k for _kid, k in sorted(self.courses.items()) if k["tabId"] == tab_id]

    def lines_of(self, tab_id):
        return [l for _lid, l in sorted(self.lines.items()) if l["tabId"] == tab_id]

    def shares_of(self, tab_id):
        return [(sid, x) for sid, x in sorted(self.shares.items()) if x["tabId"] == tab_id]

    def bill_lines(self, tab_id):
        out = []
        for l in self.lines_of(tab_id):
            if l["isVoided"]:
                continue
            for x in out:
                if x["categoryId"] == l["categoryId"]:
                    x["quantity"] += l["quantity"]
                    break
            else:
                out.append({"categoryId": l["categoryId"], "quantity": l["quantity"]})
        return out

    def _open_tab(self, company, tab_id):
        x = self.tabs.get(tab_id)
        if x is None or x["companyId"] != company or x["state"] != "open":
            return None
        return x

    # -- the fold --

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]
        pos, categories, hr, credit = store.pos, store.payments.categories, store.hr, store.credit

        if f == "declareTable":
            fc = c["facts"]
            co = fc["companyId"]
            shop = pos.shops.get(fc["shopId"])
            if (co not in store.companies or shop is None or shop["companyId"] != co or not shop["isActive"] or not fc["name"] or not fc["code"]
                    or len(fc["code"].encode("utf-8")) > 16 or fc["seats"] == 0 or fc["seats"] > MAX_SEATS):
                self.faults.append("block %d declared a table it could not" % idx)
                return
            tid, t = self.table_by_code(co, fc["code"])
            if t is not None:
                t.update({"shopId": fc["shopId"], "name": fc["name"], "seats": fc["seats"], "isActive": True})
                return
            self.tables[self.next_table] = {**fc, "isActive": True}
            self.next_table += 1
            return

        if f == "retireTable":
            t = self.tables.get(c["tableId"])
            if t is None or t["companyId"] != c["companyId"] or not t["isActive"] or self.open_tab_of(c["tableId"]) is not None:
                self.faults.append("block %d retired a table it could not" % idx)
                return
            t["isActive"] = False
            return

        if f == "openTab":
            fc = c["facts"]
            co = fc["companyId"]
            s = pos.sessions.get(fc["sessionId"])
            t = self.tables.get(fc["tableId"])
            if (s is None or s["companyId"] != co or s["state"] != "open" or t is None or t["companyId"] != co or not t["isActive"] or t["shopId"] != s["shopId"]
                    or (co, caller) not in hr.members or fc["covers"] == 0 or fc["covers"] > t["seats"]):
                self.faults.append("block %d opened a tab it could not" % idx)
                return
            if self.open_tab_of(fc["tableId"]) is not None:
                self.faults.append("block %d OPENED A SECOND TAB AT A TABLE WITH ONE OPEN" % idx)
                return
            self.tabs[self.next_tab] = {"companyId": co, "sessionId": fc["sessionId"], "tableId": fc["tableId"], "state": "open", "covers": fc["covers"], "openedBy": caller,
                                        "openedDay": day, "courses": 0, "liveLines": 0, "saleId": 0, "orderId": 0, "rule": "evenly", "ways": 0, "amountTotal": 0}
            self.next_tab += 1
            return

        if f == "orderCourse":
            fc = c["facts"]
            co = fc["companyId"]
            x = self._open_tab(co, fc["tabId"])
            if (x is None or (co, caller) not in hr.members or fc["course"] == 0 or fc["course"] > MAX_COURSES or not fc["lines"] or len(fc["lines"]) > MAX_COURSE_LINES
                    or x["liveLines"] + len(fc["lines"]) > MAX_TAB_LINES):
                self.faults.append("block %d ordered a course it could not" % idx)
                return
            s = pos.sessions[x["sessionId"]]
            for l in fc["lines"]:
                cat = categories.get(l["categoryId"])
                pid, p = pos.price_of(s["shopId"], l["categoryId"])
                if l["quantity"] == 0 or l["quantity"] > MAX_LINE_QUANTITY or cat is None or cat["companyId"] != co or p is None or not p["isActive"]:
                    self.faults.append("block %d ordered a line it could not" % idx)
                    return
            kid, k = self.course_of(fc["tabId"], fc["course"])
            if k is not None and k["state"] == "sent":
                self.faults.append("block %d ADDED TO A COURSE THE KITCHEN HAS" % idx)
                return
            for l in fc["lines"]:
                self.lines[self.next_line] = {"tabId": fc["tabId"], "course": fc["course"], "categoryId": l["categoryId"], "quantity": l["quantity"], "isVoided": False, "orderedBy": caller}
                self.next_line += 1
            if k is not None:
                k["lines"] += len(fc["lines"])
            else:
                self.courses[self.next_course] = {"tabId": fc["tabId"], "ordinal": fc["course"], "state": "ordered", "lines": len(fc["lines"]), "sentBy": None}
                self.next_course += 1
                x["courses"] += 1
            x["liveLines"] += len(fc["lines"])
            return

        if f == "voidTabLine":
            co = c["companyId"]
            x = self._open_tab(co, c["tabId"])
            l = self.lines.get(c["lineId"])
            if x is None or (co, caller) not in hr.members or l is None or l["tabId"] != c["tabId"] or l["isVoided"]:
                self.faults.append("block %d voided a line it could not" % idx)
                return
            kid, k = self.course_of(c["tabId"], l["course"])
            if k is None:
                self.faults.append("block %d voided a line of no course" % idx)
                return
            if k["state"] == "sent" and caller == l["orderedBy"]:
                self.faults.append("block %d LET A WAITER VOID THEIR OWN LINE ONCE THE KITCHEN HAD IT" % idx)
                return
            l["isVoided"] = True
            k["lines"] = max(0, k["lines"] - 1)
            x["liveLines"] = max(0, x["liveLines"] - 1)
            return

        if f == "sendCourse":
            co = c["companyId"]
            x = self._open_tab(co, c["tabId"])
            kid, k = self.course_of(c["tabId"], c["course"])
            if x is None or (co, caller) not in hr.members or k is None or k["state"] == "sent" or k["lines"] == 0:
                self.faults.append("block %d sent a course it could not" % idx)
                return
            k["state"], k["sentBy"] = "sent", caller
            return

        if f == "cancelTab":
            co = c["companyId"]
            x = self._open_tab(co, c["tabId"])
            if x is None or (co, caller) not in hr.members or any(k["state"] == "sent" and k["lines"] > 0 for k in self.courses_of(c["tabId"])):
                self.faults.append("block %d cancelled a tab it could not" % idx)
                return
            x["state"] = "cancelled"
            return

        if f == "settleTab":
            fc = c["facts"]
            co = fc["companyId"]
            x = self._open_tab(co, fc["tabId"])
            if x is None or x["liveLines"] == 0 or any(k["state"] != "sent" and k["lines"] > 0 for k in self.courses_of(fc["tabId"])):
                self.faults.append("block %d settled a tab it could not" % idx)
                return
            n = len(fc["tenders"])
            if n == 0 or n > MAX_SHARES:
                self.faults.append("block %d split a bill into shares it could not" % idx)
                return
            if fc["rule"] == "evenly":
                weights = [1] * n
            else:
                weights = fc["weights"]
                if len(weights) != n or any(w == 0 or w > MAX_WEIGHT for w in weights):
                    self.faults.append("block %d split a bill by weights it could not" % idx)
                    return
            if any(t["cash"] > MAX_MONEY or t["card"] > MAX_MONEY for t in fc["tenders"]):
                self.faults.append("block %d settled with a tender beyond its field" % idx)
                return
            s = pos.sessions[x["sessionId"]]
            bill = self.bill_lines(fc["tabId"])
            # the bill priced by the shop's list, as the till prices it
            total = 0
            for l in bill:
                pid, p = pos.price_of(s["shopId"], l["categoryId"])
                if p is None or not p["isActive"]:
                    self.faults.append("block %d settled a bill with a line off the list" % idx)
                    return
                sub, t = credit.line_amounts_fn(l["quantity"], p["priceUnit"], p["taxRate"])
                total += sub + t
            shares = split(total, weights)
            for i, t in enumerate(fc["tenders"]):
                if t["card"] > shares[i] or t["cash"] + t["card"] < shares[i]:
                    self.faults.append("block %d SETTLED A SHARE ITS TENDER DOES NOT MEET" % idx)
                    return
            # THE SALE, through this reader's own till fold, in the caller's name
            sale_before = pos.next_sale
            pos.apply({"command": {"family": "ringUpSale", "facts": {"companyId": co, "sessionId": x["sessionId"], "lines": bill,
                                                                      "cashTendered": sum(t["cash"] for t in fc["tenders"]), "cardTendered": sum(t["card"] for t in fc["tenders"])}},
                       "index": idx, "caller": caller, "day": day}, store)
            if pos.next_sale == sale_before:
                self.faults.append("block %d settled a bill this reader's till refused" % idx)
                return
            sale_id = pos.next_sale - 1
            for i, t in enumerate(fc["tenders"]):
                self.shares[self.next_share] = {"tabId": fc["tabId"], "ordinal": i + 1, "weight": weights[i], "amount": shares[i], "cash": t["cash"], "card": t["card"],
                                                "change": t["cash"] + t["card"] - shares[i]}
                self.next_share += 1
            x.update({"state": "paid", "saleId": sale_id, "orderId": pos.sales[sale_id]["orderId"], "rule": fc["rule"], "ways": n, "amountTotal": total})
            return

    # -- what the contract prints, recomputed --

    def table_line(self, tid):
        """shopId code seats active"""
        t = self.tables[tid]
        return (t["shopId"], t["code"], t["seats"], 1 if t["isActive"] else 0)

    def tab_line(self, xid, pos):
        """sessionId tableId state covers courses liveLines saleId orderId rule ways amountTotal - the courses and the lines standing
        recounted from the rows; a paid tab's total the till's sale's"""
        x = self.tabs[xid]
        live = sum(1 for l in self.lines.values() if l["tabId"] == xid and not l["isVoided"])
        courses = len(self.courses_of(xid))
        if (live, courses) != (x["liveLines"], x["courses"]):
            self.faults.append("tab %d counts %d courses and %d lines standing; its rows come to %d and %d" % (xid, x["courses"], x["liveLines"], courses, live))
        if x["state"] == "paid":
            sale = pos.sales.get(x["saleId"])
            if sale is None or sale["amountTotal"] != x["amountTotal"]:
                self.faults.append("tab %d carries a total its sale does not" % xid)
        return (x["sessionId"], x["tableId"], x["state"], x["covers"], x["courses"], x["liveLines"], x["saleId"], x["orderId"], x["rule"], x["ways"], x["amountTotal"])

    def share_line(self, sid, pos):
        """tabId ordinal weight amount cash card change - the amount recomputed by the rule from the sale's total and every share's weight"""
        x = self.shares[sid]
        tab = self.tabs[x["tabId"]]
        weights = [y["weight"] for _sid, y in self.shares_of(x["tabId"])]
        sale = pos.sales.get(tab["saleId"], {})
        mine = split(sale.get("amountTotal", tab["amountTotal"]), weights)
        if mine[x["ordinal"] - 1] != x["amount"]:
            self.faults.append("share %d of tab %d carries %d; the rule comes to %d" % (x["ordinal"], x["tabId"], x["amount"], mine[x["ordinal"] - 1]))
        if x["cash"] + x["card"] - x["amount"] != x["change"]:
            self.faults.append("share %d of tab %d carries change its tender does not come to" % (x["ordinal"], x["tabId"]))
        self.shares_recomputed += 1
        return (x["tabId"], x["ordinal"], x["weight"], x["amount"], x["cash"], x["card"], x["change"])

    def summary(self):
        return {
            "tables": len(self.tables),
            "tabs": len(self.tabs),
            "paid": sum(1 for x in self.tabs.values() if x["state"] == "paid"),
            "shares": len(self.shares),
            "faults": len(self.faults),
        }
