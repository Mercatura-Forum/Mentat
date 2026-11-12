"""The point-of-sale families (399 to 406), decoded from their canonical bytes, re-encoded so the
command hash can be re-derived, and folded by rules written from the design:

  * a shop sells from a LIST: the cashier states what and how much; the price, the tax and whether
    the thing comes off the shelf are the list's - one shop per code per company, its shelf an
    internal location, its customer location a customer one, its walk-in customer a customer with a
    receivable and no credit terms, its cash and card accounts assets and distinct, its difference
    account an expense;
  * a till session is THE CASHIER'S: opened by a member with a float, one live per shop; nobody else
    rings up in it or counts it; every sale a sale through this reader's own order fold, the shelf
    read first - what the session sold plus the sale must be on hand - and the tender held to the
    total with the card never over it;
  * THE Z REPORT, posted in slices by somebody else: the receipts through this reader's own ledger,
    the kinds sold off the shelf through its own stock fold, then the takings move - the cash added
    to the drawer, the card takings, the shortfall or the excess, against the receivable - generated
    in the cashier's name and posted in the poster's; the session's totals recomputed from its sales.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text

MAX_PRICE = 1_000_000_000_000
MAX_TAX_RATE = 10_000_000
MAX_LINES = 255
MAX_LINE_QUANTITY = 1_000_000_000
MAX_MONEY = 1_000_000_000_000_000
MAX_SLICE = 255
MAX_QUANTITY = 2 ** 48 - 1


def _bool(b):
    return b"\x01" if b else b"\x00"


def _read_sale(r):
    company = r.nat()
    session = r.nat()
    n = r.nat()
    lines = [{"categoryId": r.nat(), "quantity": r.nat()} for _ in range(n)]
    return {"facts": {"companyId": company, "sessionId": session, "lines": lines, "cashTendered": r.nat(), "cardTendered": r.nat()}}


READERS = {
    399: ("declareShop", lambda r: {"facts": {"companyId": r.nat(), "code": r.text(), "name": r.text(), "stockLocationId": r.nat(), "customerLocationId": r.nat(),
                                              "partnerId": r.nat(), "journalId": r.nat(), "cashAccountId": r.nat(), "cardAccountId": r.nat(), "differenceAccountId": r.nat(),
                                              "currency": r.text()}}),
    400: ("retireShop", lambda r: {"companyId": r.nat(), "shopId": r.nat(), "reason": r.text()}),
    401: ("setShopPrice", lambda r: {"facts": {"companyId": r.nat(), "shopId": r.nat(), "categoryId": r.nat(), "priceUnit": r.nat(), "taxRate": r.nat(), "movesStock": r.bool()}}),
    402: ("withdrawShopPrice", lambda r: {"companyId": r.nat(), "shopId": r.nat(), "categoryId": r.nat()}),
    403: ("openTillSession", lambda r: {"companyId": r.nat(), "shopId": r.nat(), "openingFloat": r.nat()}),
    404: ("ringUpSale", _read_sale),
    405: ("closeTillSession", lambda r: {"companyId": r.nat(), "sessionId": r.nat(), "countedCash": r.nat()}),
    406: ("postTillSession", lambda r: {"companyId": r.nat(), "sessionId": r.nat(), "limit": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_pos_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def _write_sale(c):
    f = c["facts"]
    out = write_nat(f["companyId"]) + write_nat(f["sessionId"]) + write_nat(len(f["lines"]))
    for l in f["lines"]:
        out += write_nat(l["categoryId"]) + write_nat(l["quantity"])
    return out + write_nat(f["cashTendered"]) + write_nat(f["cardTendered"])


ENCODERS = {
    "declareShop": (399, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["code"]) + write_text(c["facts"]["name"]) + write_nat(c["facts"]["stockLocationId"])
                    + write_nat(c["facts"]["customerLocationId"]) + write_nat(c["facts"]["partnerId"]) + write_nat(c["facts"]["journalId"]) + write_nat(c["facts"]["cashAccountId"])
                    + write_nat(c["facts"]["cardAccountId"]) + write_nat(c["facts"]["differenceAccountId"]) + write_text(c["facts"]["currency"])),
    "retireShop": (400, lambda c: write_nat(c["companyId"]) + write_nat(c["shopId"]) + write_text(c["reason"])),
    "setShopPrice": (401, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["shopId"]) + write_nat(c["facts"]["categoryId"]) + write_nat(c["facts"]["priceUnit"])
                     + write_nat(c["facts"]["taxRate"]) + _bool(c["facts"]["movesStock"])),
    "withdrawShopPrice": (402, lambda c: write_nat(c["companyId"]) + write_nat(c["shopId"]) + write_nat(c["categoryId"])),
    "openTillSession": (403, lambda c: write_nat(c["companyId"]) + write_nat(c["shopId"]) + write_nat(c["openingFloat"])),
    "ringUpSale": (404, _write_sale),
    "closeTillSession": (405, lambda c: write_nat(c["companyId"]) + write_nat(c["sessionId"]) + write_nat(c["countedCash"])),
    "postTillSession": (406, lambda c: write_nat(c["companyId"]) + write_nat(c["sessionId"]) + write_nat(c["limit"])),
}


def pos_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


def expected_cash(opening_float, cash_takings):
    return opening_float + cash_takings


def short_by(expected, counted):
    return expected - counted if counted < expected else 0


def over_by(expected, counted):
    return counted - expected if counted > expected else 0


def z_lines(shop, receivable, s):
    """The Z report's lines as the design states them: the cash added to the drawer (the count less
    the float) debits the cash account or, below the float, credits it; the card takings debit the
    card account; the shortfall debits the difference account, the excess credits it; the whole of
    the takings credits the walk-in customer's receivable."""
    out = []
    if s["countedCash"] > s["openingFloat"]:
        out.append({"accountId": shop["cashAccountId"], "partnerId": 0, "name": "cash taken", "debit": s["countedCash"] - s["openingFloat"], "credit": 0, "amountCurrency": 0, "taxId": 0})
    elif s["countedCash"] < s["openingFloat"]:
        out.append({"accountId": shop["cashAccountId"], "partnerId": 0, "name": "cash taken", "debit": 0, "credit": s["openingFloat"] - s["countedCash"], "amountCurrency": 0, "taxId": 0})
    if s["cardTakings"] > 0:
        out.append({"accountId": shop["cardAccountId"], "partnerId": 0, "name": "card takings", "debit": s["cardTakings"], "credit": 0, "amountCurrency": 0, "taxId": 0})
    if s["shortBy"] > 0:
        out.append({"accountId": shop["differenceAccountId"], "partnerId": 0, "name": "cash short", "debit": s["shortBy"], "credit": 0, "amountCurrency": 0, "taxId": 0})
    elif s["overBy"] > 0:
        out.append({"accountId": shop["differenceAccountId"], "partnerId": 0, "name": "cash over", "debit": 0, "credit": s["overBy"], "amountCurrency": 0, "taxId": 0})
    total = s["cashTakings"] + s["cardTakings"]
    if total > 0:
        out.append({"accountId": receivable, "partnerId": shop["partnerId"], "name": "takings", "debit": 0, "credit": total, "amountCurrency": 0, "taxId": 0})
    return out


class Pos:
    def __init__(self):
        self.shops = {}
        self.prices = {}
        self.sessions = {}
        self.sales = {}
        self.kinds = {}
        self.next_shop = 1
        self.next_price = 1
        self.next_session = 1
        self.next_sale = 1
        self.next_kind = 1
        self.totals_recomputed = 0
        self.faults = []

    # -- reads --

    def shop_by_code(self, company, code):
        for sid, x in self.shops.items():
            if x["companyId"] == company and x["code"] == code:
                return sid, x
        return None, None

    def price_of(self, shop, category):
        for pid, p in self.prices.items():
            if p["shopId"] == shop and p["categoryId"] == category:
                return pid, p
        return None, None

    def live_session_of(self, shop):
        for sid, s in sorted(self.sessions.items()):
            if s["shopId"] == shop and s["state"] != "posted":
                return sid
        return None

    def kind_of(self, session, category):
        for kid, k in self.kinds.items():
            if k["sessionId"] == session and k["categoryId"] == category:
                return kid, k
        return None, None

    def unposted_sales(self, session, limit):
        return [(i, x) for i, x in sorted(self.sales.items()) if x["sessionId"] == session and not x["isPosted"]][:limit]

    def unmoved_kinds(self, session, limit):
        return [(i, k) for i, k in sorted(self.kinds.items()) if k["sessionId"] == session and k["pickingId"] == 0][:limit]

    def _account_is(self, ledger, company, aid, kind):
        a = ledger.accounts.get(aid)
        return a is not None and a["companyId"] == company and not a["deprecated"] and a["accountType"] == kind

    def _active_shop(self, company, shop_id):
        x = self.shops.get(shop_id)
        if x is None or x["companyId"] != company or not x["isActive"]:
            return None
        return x

    # -- the fold --

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]
        stock, partners, categories, ledger, credit, hr = store.stock, store.payments.partners, store.payments.categories, store.ledger, store.credit, store.hr

        if f == "declareShop":
            fc = c["facts"]
            co = fc["companyId"]
            shelf = stock.locations.get(fc["stockLocationId"])
            cust = stock.locations.get(fc["customerLocationId"])
            p = partners.get(fc["partnerId"])
            j = ledger.journals.get(fc["journalId"])
            bad = (co not in store.companies or not fc["name"] or not fc["code"] or len(fc["code"].encode("utf-8")) > 16
                   or shelf is None or shelf["companyId"] != co or shelf["usage"] != "internal"
                   or cust is None or cust["companyId"] != co or cust["usage"] != "customer"
                   or p is None or p["companyId"] != co or not p["isCustomer"] or not p["receivableAccountId"]
                   or credit.terms_of(co, fc["partnerId"])[1] is not None
                   or j is None or j["companyId"] != co or not j["isActive"]
                   or not self._account_is(ledger, co, fc["cashAccountId"], "asset") or not self._account_is(ledger, co, fc["cardAccountId"], "asset")
                   or not self._account_is(ledger, co, fc["differenceAccountId"], "expense") or fc["cashAccountId"] == fc["cardAccountId"]
                   or not fc["currency"] or len(fc["currency"].encode("utf-8")) > 4)
            if bad:
                self.faults.append("block %d declared a shop it could not" % idx)
                return
            sid, x = self.shop_by_code(co, fc["code"])
            if x is not None:
                x.update({k: fc[k] for k in ("name", "stockLocationId", "customerLocationId", "partnerId", "journalId", "cashAccountId", "cardAccountId", "differenceAccountId", "currency")})
                x["isActive"] = True
                return
            self.shops[self.next_shop] = {**fc, "isActive": True, "declaredBy": caller}
            self.next_shop += 1
            return

        if f == "retireShop":
            x = self._active_shop(c["companyId"], c["shopId"])
            if x is None or self.live_session_of(c["shopId"]) is not None:
                self.faults.append("block %d retired a shop it could not" % idx)
                return
            x["isActive"] = False
            return

        if f == "setShopPrice":
            fc = c["facts"]
            x = self._active_shop(fc["companyId"], fc["shopId"])
            cat = categories.get(fc["categoryId"])
            if (x is None or cat is None or cat["companyId"] != fc["companyId"] or fc["priceUnit"] == 0 or fc["priceUnit"] > MAX_PRICE or fc["taxRate"] > MAX_TAX_RATE):
                self.faults.append("block %d set a price it could not" % idx)
                return
            pid, p = self.price_of(fc["shopId"], fc["categoryId"])
            if p is not None:
                p.update({"priceUnit": fc["priceUnit"], "taxRate": fc["taxRate"], "movesStock": fc["movesStock"], "isActive": True})
                return
            self.prices[self.next_price] = {"shopId": fc["shopId"], "categoryId": fc["categoryId"], "priceUnit": fc["priceUnit"], "taxRate": fc["taxRate"], "movesStock": fc["movesStock"], "isActive": True}
            self.next_price += 1
            return

        if f == "withdrawShopPrice":
            x = self._active_shop(c["companyId"], c["shopId"])
            pid, p = self.price_of(c["shopId"], c["categoryId"])
            if x is None or p is None or not p["isActive"]:
                self.faults.append("block %d withdrew a price it could not" % idx)
                return
            p["isActive"] = False
            return

        if f == "openTillSession":
            co = c["companyId"]
            x = self._active_shop(co, c["shopId"])
            if x is None or (co, caller) not in hr.members or c["openingFloat"] > MAX_MONEY or self.live_session_of(c["shopId"]) is not None:
                self.faults.append("block %d opened a till it could not" % idx)
                return
            self.sessions[self.next_session] = {"companyId": co, "shopId": c["shopId"], "cashier": caller, "state": "open", "openedDay": day, "closedDay": 0, "postedDay": 0,
                                                "openingFloat": c["openingFloat"], "cashTakings": 0, "cardTakings": 0, "ordersCount": 0, "amountUntaxed": 0, "amountTax": 0,
                                                "amountTotal": 0, "countedCash": 0, "shortBy": 0, "overBy": 0, "postedOrders": 0, "kindsMoved": 0, "zMoveId": 0, "postedBy": None}
            self.next_session += 1
            return

        if f == "ringUpSale":
            fc = c["facts"]
            co = fc["companyId"]
            s = self.sessions.get(fc["sessionId"])
            if s is None or s["companyId"] != co or s["state"] != "open":
                self.faults.append("block %d rang up a sale in a session it could not" % idx)
                return
            if caller != s["cashier"]:
                self.faults.append("block %d LET SOMEBODY OTHER THAN THE CASHIER RING UP" % idx)
                return
            shop = self.shops[s["shopId"]]
            if not fc["lines"] or len(fc["lines"]) > MAX_LINES or fc["cashTendered"] > MAX_MONEY or fc["cardTendered"] > MAX_MONEY:
                self.faults.append("block %d rang up a sale beyond its bounds" % idx)
                return
            untaxed = tax = 0
            order_lines = []
            wanted = {}
            for l in fc["lines"]:
                cat = categories.get(l["categoryId"])
                pid, p = self.price_of(s["shopId"], l["categoryId"])
                if (l["quantity"] == 0 or l["quantity"] > MAX_LINE_QUANTITY or cat is None or cat["companyId"] != co or p is None or not p["isActive"]):
                    self.faults.append("block %d rang up a line it could not" % idx)
                    return
                sub, t = credit.line_amounts_fn(l["quantity"], p["priceUnit"], p["taxRate"])
                untaxed += sub
                tax += t
                order_lines.append({"categoryId": l["categoryId"], "name": cat["name"], "quantity": l["quantity"], "priceUnit": p["priceUnit"], "taxRate": p["taxRate"]})
                if p["movesStock"]:
                    wanted[l["categoryId"]] = wanted.get(l["categoryId"], 0) + l["quantity"]
            total = untaxed + tax
            if fc["cardTendered"] > total or fc["cashTendered"] + fc["cardTendered"] < total or s["amountTotal"] + total > MAX_MONEY:
                self.faults.append("block %d rang up a sale whose tender does not meet its total" % idx)
                return
            for cid, q in wanted.items():
                kid, k = self.kind_of(fc["sessionId"], cid)
                sold = k["quantity"] if k is not None else 0
                if sold + q > MAX_QUANTITY or stock.on_hand(co, shop["stockLocationId"], cid) - store.web.reserved_at(co, shop["stockLocationId"], cid) < sold + q:
                    self.faults.append("block %d SOLD OFF A SHELF THAT DID NOT HOLD IT" % idx)
                    return
            order = {"companyId": co, "partnerId": shop["partnerId"], "direction": "sale", "orderDay": day, "currency": shop["currency"],
                     "clientRef": "till %d sale %d" % (fc["sessionId"], s["ordersCount"] + 1), "lines": order_lines}
            result = store._sale(block, order, shop["journalId"])
            if result is None:
                self.faults.append("block %d rang up a sale this reader's order fold refused" % idx)
                return
            order_id, move_id = result
            cash_paid = total - fc["cardTendered"]
            self.sales[self.next_sale] = {"sessionId": fc["sessionId"], "orderId": order_id, "invoiceMoveId": move_id, "amountTotal": total, "cashPaid": cash_paid,
                                          "cardPaid": fc["cardTendered"], "changeGiven": fc["cashTendered"] + fc["cardTendered"] - total, "day": day, "isPosted": False}
            self.next_sale += 1
            for cid, q in wanted.items():
                kid, k = self.kind_of(fc["sessionId"], cid)
                if k is not None:
                    k["quantity"] += q
                else:
                    self.kinds[self.next_kind] = {"sessionId": fc["sessionId"], "categoryId": cid, "quantity": q, "pickingId": 0}
                    self.next_kind += 1
            s["cashTakings"] += cash_paid
            s["cardTakings"] += fc["cardTendered"]
            s["ordersCount"] += 1
            s["amountUntaxed"] += untaxed
            s["amountTax"] += tax
            s["amountTotal"] += total
            return

        if f == "closeTillSession":
            s = self.sessions.get(c["sessionId"])
            if s is None or s["companyId"] != c["companyId"] or s["state"] != "open" or c["countedCash"] > MAX_MONEY:
                self.faults.append("block %d counted a session it could not" % idx)
                return
            if caller != s["cashier"]:
                self.faults.append("block %d LET SOMEBODY OTHER THAN THE CASHIER COUNT THE DRAWER" % idx)
                return
            expected = expected_cash(s["openingFloat"], s["cashTakings"])
            s.update({"state": "counted", "closedDay": day, "countedCash": c["countedCash"], "shortBy": short_by(expected, c["countedCash"]), "overBy": over_by(expected, c["countedCash"])})
            return

        if f == "postTillSession":
            co = c["companyId"]
            s = self.sessions.get(c["sessionId"])
            if c["limit"] == 0 or c["limit"] > MAX_SLICE or s is None or s["companyId"] != co or s["state"] != "counted" or (co, caller) not in hr.members:
                self.faults.append("block %d posted a session it could not" % idx)
                return
            if caller == s["cashier"]:
                self.faults.append("block %d LET THE CASHIER POST THEIR OWN SESSION" % idx)
                return
            shop = self.shops[s["shopId"]]

            def synth(cmd):
                return {"command": cmd, "index": idx, "caller": caller, "day": day}
            # the receipts, through the ledger reader, which judges each posting by its own rules
            pending = self.unposted_sales(c["sessionId"], c["limit"])
            if pending:
                for sale_id, x in pending:
                    ledger.apply(synth({"family": "postMove", "companyId": co, "moveId": x["invoiceMoveId"], "reason": ""}))
                    if ledger.moves.get(x["invoiceMoveId"], {}).get("state") != "posted":
                        self.faults.append("block %d posted a receipt this reader's ledger refused" % idx)
                        return
                    x["isPosted"] = True
                s["postedOrders"] += len(pending)
                return
            # the goods, through the stock reader
            kinds = self.unmoved_kinds(c["sessionId"], c["limit"])
            if kinds:
                facts = {"companyId": co, "fromLocationId": shop["stockLocationId"], "toLocationId": shop["customerLocationId"], "businessDay": day, "partnerId": shop["partnerId"],
                         "reference": "till %d" % c["sessionId"], "moves": [{"categoryId": k["categoryId"], "lotId": 0, "quantity": k["quantity"], "unitCost": 0} for _kid, k in kinds]}
                pid = store._consume(block, facts, shop["journalId"])
                if pid == 0:
                    self.faults.append("block %d moved goods this reader's stock fold refused" % idx)
                    return
                for kid, k in kinds:
                    k["pickingId"] = pid
                s["kindsMoved"] += len(kinds)
                return
            # the takings, generated in the cashier's name and posted in the poster's
            p = partners.get(shop["partnerId"])
            lines = z_lines(shop, p["receivableAccountId"] if p is not None else 0, s)
            z_id = 0
            if lines:
                if day <= ledger.locks.get(co, 0):
                    self.faults.append("block %d posted a Z report into a locked period" % idx)
                    return
                facts = {"companyId": co, "journalId": shop["journalId"], "businessDay": day, "moveType": "entry", "currency": shop["currency"], "partnerId": shop["partnerId"],
                         "ref": "till %d Z" % c["sessionId"], "lines": lines}
                z_id = ledger._generated(facts, s["cashier"], caller, idx)
            s.update({"state": "posted", "postedDay": day, "zMoveId": z_id, "postedBy": caller})
            return

    # -- what the contract prints, recomputed --

    def shop_line(self, sid):
        """code stockLocationId customerLocationId partnerId journalId cashAccountId cardAccountId differenceAccountId active"""
        x = self.shops[sid]
        return (x["code"], x["stockLocationId"], x["customerLocationId"], x["partnerId"], x["journalId"], x["cashAccountId"], x["cardAccountId"], x["differenceAccountId"], 1 if x["isActive"] else 0)

    def session_line(self, sid, credit):
        """shopId state openedDay closedDay postedDay openingFloat cashTakings cardTakings ordersCount untaxed tax total countedCash shortBy overBy postedOrders kindsMoved zMoveId - 
        the takings, the count of sales and the totals recomputed from the session's sales and their orders, the shortfall and the excess from the count"""
        s = self.sessions[sid]
        mine = [x for x in self.sales.values() if x["sessionId"] == sid]
        cash = sum(x["cashPaid"] for x in mine)
        card = sum(x["cardPaid"] for x in mine)
        total = sum(x["amountTotal"] for x in mine)
        untaxed = tax = 0
        for x in mine:
            o = credit.orders.get(x["orderId"])
            if o is None:
                self.faults.append("till session %d's sale names order %d, which this reader does not hold" % (sid, x["orderId"]))
                continue
            for l in o["facts"]["lines"]:
                sub, t = credit.line_amounts_fn(l["quantity"], l["priceUnit"], l["taxRate"])
                untaxed += sub
                tax += t
        if (cash, card, len(mine), untaxed, tax, total) != (s["cashTakings"], s["cardTakings"], s["ordersCount"], s["amountUntaxed"], s["amountTax"], s["amountTotal"]):
            self.faults.append("till session %d carries takings its sales do not come to" % sid)
        if s["state"] != "open":
            expected = expected_cash(s["openingFloat"], cash)
            if (short_by(expected, s["countedCash"]), over_by(expected, s["countedCash"])) != (s["shortBy"], s["overBy"]):
                self.faults.append("till session %d carries a shortfall or an excess its count does not come to" % sid)
        self.totals_recomputed += 1
        return (s["shopId"], s["state"], s["openedDay"], s["closedDay"], s["postedDay"], s["openingFloat"], s["cashTakings"], s["cardTakings"], s["ordersCount"],
                s["amountUntaxed"], s["amountTax"], s["amountTotal"], s["countedCash"], s["shortBy"], s["overBy"], s["postedOrders"], s["kindsMoved"], s["zMoveId"])

    def sale_line(self, sale_id):
        """sessionId orderId invoiceMoveId amountTotal cashPaid cardPaid changeGiven day posted"""
        x = self.sales[sale_id]
        return (x["sessionId"], x["orderId"], x["invoiceMoveId"], x["amountTotal"], x["cashPaid"], x["cardPaid"], x["changeGiven"], x["day"], 1 if x["isPosted"] else 0)

    def summary(self):
        return {
            "shops": len(self.shops),
            "sessions": len(self.sessions),
            "posted": sum(1 for s in self.sessions.values() if s["state"] == "posted"),
            "sales": len(self.sales),
            "kinds": len(self.kinds),
            "faults": len(self.faults),
        }
