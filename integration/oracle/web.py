"""The web-shop families (415 to 424), decoded from their canonical bytes, re-encoded so the command hash
can be re-derived, and folded by rules written from the design:

  * a STOREFRONT is a shop's, one per shop; its catalogue is the shop's list as listed - a listing
    names a category the list prices live and nothing else;
  * a CART is a draft order of the order fold, the shopper's own - anybody's - placed on the first
    line and amended on every change, every line priced by the shop's list and never by the shopper;
  * CHECKOUT re-prices the cart, holds the payment to that total, requires every kind off the shelf
    AVAILABLE - on hand less what other web orders hold - confirms the order through this reader's own
    order fold, holds the goods and records the payment;
  * FULFILMENT, a member's and not the shopper's, ships the held goods through this reader's own stock
    fold, issues the invoice through its order fold and posts the payment in the shopper's name and
    the member's hand; a cancelled order frees its hold and refunds on record.

This reader holds every web payment to its order's total and every hold to its order's lines.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text

MAX_CART_LINES = 50
MAX_LINE_QUANTITY = 1_000_000_000
MAX_MONEY = 1_000_000_000_000_000


READERS = {
    415: ("openStorefront", lambda r: {"facts": {"companyId": r.nat(), "shopId": r.nat(), "slug": r.text(), "name": r.text()}}),
    416: ("closeStorefront", lambda r: {"companyId": r.nat(), "storefrontId": r.nat(), "reason": r.text()}),
    417: ("listOnline", lambda r: {"facts": {"companyId": r.nat(), "storefrontId": r.nat(), "categoryId": r.nat(), "title": r.text()}}),
    418: ("delist", lambda r: {"companyId": r.nat(), "storefrontId": r.nat(), "categoryId": r.nat()}),
    419: ("addToCart", lambda r: {"facts": {"companyId": r.nat(), "storefrontId": r.nat(), "categoryId": r.nat(), "quantity": r.nat()}}),
    420: ("removeFromCart", lambda r: {"companyId": r.nat(), "cartId": r.nat(), "categoryId": r.nat()}),
    421: ("abandonCart", lambda r: {"companyId": r.nat(), "cartId": r.nat()}),
    422: ("checkout", lambda r: {"facts": {"companyId": r.nat(), "cartId": r.nat(), "cardTendered": r.nat(), "paymentReference": r.text()}}),
    423: ("fulfilWebOrder", lambda r: {"companyId": r.nat(), "webOrderId": r.nat(), "journalId": r.nat()}),
    424: ("cancelWebOrder", lambda r: {"companyId": r.nat(), "webOrderId": r.nat(), "reason": r.text()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_web_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "openStorefront": (415, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["shopId"]) + write_text(c["facts"]["slug"]) + write_text(c["facts"]["name"])),
    "closeStorefront": (416, lambda c: write_nat(c["companyId"]) + write_nat(c["storefrontId"]) + write_text(c["reason"])),
    "listOnline": (417, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["storefrontId"]) + write_nat(c["facts"]["categoryId"]) + write_text(c["facts"]["title"])),
    "delist": (418, lambda c: write_nat(c["companyId"]) + write_nat(c["storefrontId"]) + write_nat(c["categoryId"])),
    "addToCart": (419, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["storefrontId"]) + write_nat(c["facts"]["categoryId"]) + write_nat(c["facts"]["quantity"])),
    "removeFromCart": (420, lambda c: write_nat(c["companyId"]) + write_nat(c["cartId"]) + write_nat(c["categoryId"])),
    "abandonCart": (421, lambda c: write_nat(c["companyId"]) + write_nat(c["cartId"])),
    "checkout": (422, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["cartId"]) + write_nat(c["facts"]["cardTendered"]) + write_text(c["facts"]["paymentReference"])),
    "fulfilWebOrder": (423, lambda c: write_nat(c["companyId"]) + write_nat(c["webOrderId"]) + write_nat(c["journalId"])),
    "cancelWebOrder": (424, lambda c: write_nat(c["companyId"]) + write_nat(c["webOrderId"]) + write_text(c["reason"])),
}


def web_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


class Web:
    def __init__(self):
        self.storefronts = {}
        self.listings = {}
        self.carts = {}
        self.orders = {}
        self.reservations = {}
        self.next_storefront = 1
        self.next_listing = 1
        self.next_cart = 1
        self.next_order = 1
        self.next_reservation = 1
        self.payments_held = 0
        self.faults = []

    # -- reads --

    def storefront_by_slug(self, company, slug):
        for sid, x in self.storefronts.items():
            if x["companyId"] == company and x["slug"] == slug:
                return sid, x
        return None, None

    def storefront_of_shop(self, shop):
        for sid, x in self.storefronts.items():
            if x["shopId"] == shop:
                return sid
        return None

    def listing_of(self, storefront, category):
        for lid, l in self.listings.items():
            if l["storefrontId"] == storefront and l["categoryId"] == category:
                return lid, l
        return None, None

    def open_cart_of(self, storefront, shopper):
        for cid, x in sorted(self.carts.items()):
            if x["storefrontId"] == storefront and x["shopper"] == shopper and x["state"] == "open":
                return cid, x
        return None, None

    def reserved_at(self, company, location, category):
        return sum(r["quantity"] for r in self.reservations.values() if r["isLive"] and (r["companyId"], r["locationId"], r["categoryId"]) == (company, location, category))

    def reservations_of(self, order_id):
        return [(rid, r) for rid, r in sorted(self.reservations.items()) if r["orderId"] == order_id]

    def _open_storefront(self, store, company, storefront_id):
        sf = self.storefronts.get(storefront_id)
        if sf is None or sf["companyId"] != company or not sf["isOpen"]:
            return None, None
        shop = store.pos.shops.get(sf["shopId"])
        if shop is None or not shop["isActive"]:
            return None, None
        return sf, shop

    def _cart_lines(self, store, order_id):
        o = store.credit.orders.get(order_id)
        if o is None:
            return []
        return [{"categoryId": l["categoryId"], "quantity": l["quantity"]} for l in o["facts"]["lines"]]

    def _price(self, store, company, shop_id, shop, lines, ref, day):
        """The cart as an order of the shop's walk-in customer, priced by the list today; None if a line is off the list."""
        untaxed = tax = 0
        order_lines = []
        wanted = {}
        for l in lines:
            pid, p = store.pos.price_of(shop_id, l["categoryId"])
            cat = store.payments.categories.get(l["categoryId"])
            if p is None or not p["isActive"] or cat is None or l["quantity"] == 0:
                return None
            sub, t = store.credit.line_amounts_fn(l["quantity"], p["priceUnit"], p["taxRate"])
            untaxed += sub
            tax += t
            order_lines.append({"categoryId": l["categoryId"], "name": cat["name"], "quantity": l["quantity"], "priceUnit": p["priceUnit"], "taxRate": p["taxRate"]})
            if p["movesStock"]:
                wanted[l["categoryId"]] = wanted.get(l["categoryId"], 0) + l["quantity"]
        facts = {"companyId": company, "partnerId": shop["partnerId"], "direction": "sale", "orderDay": day, "currency": shop["currency"], "clientRef": ref, "lines": order_lines}
        return facts, untaxed + tax, wanted

    # -- the fold --

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]
        pos, categories, hr, credit, ledger, stock = store.pos, store.payments.categories, store.hr, store.credit, store.ledger, store.stock

        def synth(cmd):
            return {"command": cmd, "index": idx, "caller": caller, "day": day}

        def order_act(cmd):
            b = synth(cmd)
            store.payments.note(b)
            credit.watch(b, ledger, store.payments)

        if f == "openStorefront":
            fc = c["facts"]
            co = fc["companyId"]
            shop = pos.shops.get(fc["shopId"])
            if (co not in store.companies or (co, caller) not in hr.members or shop is None or shop["companyId"] != co or not shop["isActive"] or not fc["name"]
                    or not fc["slug"] or len(fc["slug"].encode("utf-8")) > 16):
                self.faults.append("block %d opened a storefront it could not" % idx)
                return
            sid, x = self.storefront_by_slug(co, fc["slug"])
            other = self.storefront_of_shop(fc["shopId"])
            if other is not None and other != sid:
                self.faults.append("block %d OPENED A SECOND STOREFRONT OVER ONE SHOP" % idx)
                return
            if x is not None:
                x.update({"shopId": fc["shopId"], "name": fc["name"], "isOpen": True, "openedBy": caller})
                return
            self.storefronts[self.next_storefront] = {**fc, "isOpen": True, "openedBy": caller}
            self.next_storefront += 1
            return

        if f == "closeStorefront":
            sf = self.storefronts.get(c["storefrontId"])
            if sf is None or sf["companyId"] != c["companyId"] or not sf["isOpen"] or (c["companyId"], caller) not in hr.members:
                self.faults.append("block %d closed a storefront it could not" % idx)
                return
            sf["isOpen"] = False
            return

        if f == "listOnline":
            fc = c["facts"]
            co = fc["companyId"]
            sf, shop = self._open_storefront(store, co, fc["storefrontId"])
            cat = categories.get(fc["categoryId"])
            pid, p = pos.price_of(sf["shopId"], fc["categoryId"]) if sf is not None else (None, None)
            if sf is None or (co, caller) not in hr.members or cat is None or cat["companyId"] != co or p is None or not p["isActive"] or not fc["title"]:
                self.faults.append("block %d listed a category it could not" % idx)
                return
            lid, l = self.listing_of(fc["storefrontId"], fc["categoryId"])
            if l is not None:
                l.update({"title": fc["title"], "isActive": True})
                return
            self.listings[self.next_listing] = {"storefrontId": fc["storefrontId"], "categoryId": fc["categoryId"], "title": fc["title"], "isActive": True}
            self.next_listing += 1
            return

        if f == "delist":
            co = c["companyId"]
            sf, shop = self._open_storefront(store, co, c["storefrontId"])
            lid, l = self.listing_of(c["storefrontId"], c["categoryId"])
            if sf is None or (co, caller) not in hr.members or l is None or not l["isActive"]:
                self.faults.append("block %d delisted a category it could not" % idx)
                return
            l["isActive"] = False
            return

        if f == "addToCart":
            fc = c["facts"]
            co = fc["companyId"]
            sf, shop = self._open_storefront(store, co, fc["storefrontId"])
            cat = categories.get(fc["categoryId"])
            lid, l = self.listing_of(fc["storefrontId"], fc["categoryId"])
            if sf is None or fc["quantity"] == 0 or fc["quantity"] > MAX_LINE_QUANTITY or cat is None or cat["companyId"] != co or l is None or not l["isActive"]:
                self.faults.append("block %d put a line into a cart it could not" % idx)
                return
            cid, x = self.open_cart_of(fc["storefrontId"], caller)
            if x is not None:
                lines = self._cart_lines(store, x["orderId"])
                for ln in lines:
                    if ln["categoryId"] == fc["categoryId"]:
                        ln["quantity"] += fc["quantity"]
                        break
                else:
                    lines.append({"categoryId": fc["categoryId"], "quantity": fc["quantity"]})
                if len(lines) > MAX_CART_LINES:
                    self.faults.append("block %d filled a cart beyond its bound" % idx)
                    return
                priced = self._price(store, co, sf["shopId"], shop, lines, "web cart %d" % cid, day)
                if priced is None:
                    self.faults.append("block %d priced a cart it could not" % idx)
                    return
                order_act({"family": "amendOrder", "orderId": x["orderId"], "facts": priced[0]})
                x["lines"] = len(lines)
                return
            cid = self.next_cart
            priced = self._price(store, co, sf["shopId"], shop, [{"categoryId": fc["categoryId"], "quantity": fc["quantity"]}], "web cart %d" % cid, day)
            if priced is None:
                self.faults.append("block %d priced a cart it could not" % idx)
                return
            order_act({"family": "placeOrder", "facts": priced[0]})
            order_id = credit.next_order - 1
            self.carts[cid] = {"companyId": co, "storefrontId": fc["storefrontId"], "shopper": caller, "state": "open", "orderId": order_id, "lines": 1, "openedDay": day}
            self.next_cart += 1
            return

        if f in ("removeFromCart", "abandonCart"):
            co = c["companyId"]
            x = self.carts.get(c["cartId"])
            if x is None or x["companyId"] != co or x["state"] != "open":
                self.faults.append("block %d touched a cart it could not" % idx)
                return
            if caller != x["shopper"]:
                self.faults.append("block %d LET SOMEBODY ELSE TOUCH A SHOPPER'S CART" % idx)
                return
            if f == "abandonCart":
                order_act({"family": "cancelOrder", "companyId": co, "orderId": x["orderId"], "reason": ""})
                x["state"] = "abandoned"
                return
            sf, shop = self._open_storefront(store, co, x["storefrontId"])
            if sf is None:
                self.faults.append("block %d took from a cart at a closed storefront" % idx)
                return
            lines = [ln for ln in self._cart_lines(store, x["orderId"]) if ln["categoryId"] != c["categoryId"]]
            if len(lines) == len(self._cart_lines(store, x["orderId"])):
                self.faults.append("block %d took out a kind not in the cart" % idx)
                return
            if not lines:
                order_act({"family": "cancelOrder", "companyId": co, "orderId": x["orderId"], "reason": ""})
                x.update({"state": "abandoned", "lines": 0})
                return
            priced = self._price(store, co, sf["shopId"], shop, lines, "web cart %d" % c["cartId"], day)
            if priced is None:
                self.faults.append("block %d priced a cart it could not" % idx)
                return
            order_act({"family": "amendOrder", "orderId": x["orderId"], "facts": priced[0]})
            x["lines"] = len(lines)
            return

        if f == "checkout":
            fc = c["facts"]
            co = fc["companyId"]
            x = self.carts.get(fc["cartId"])
            if x is None or x["companyId"] != co or x["state"] != "open":
                self.faults.append("block %d checked out a cart it could not" % idx)
                return
            if caller != x["shopper"]:
                self.faults.append("block %d LET SOMEBODY ELSE CHECK OUT A SHOPPER'S CART" % idx)
                return
            sf, shop = self._open_storefront(store, co, x["storefrontId"])
            lines = self._cart_lines(store, x["orderId"])
            if sf is None or fc["cardTendered"] > MAX_MONEY or not fc["paymentReference"] or not lines:
                self.faults.append("block %d checked out a cart it could not" % idx)
                return
            priced = self._price(store, co, sf["shopId"], shop, lines, "web order %d" % fc["cartId"], day)
            if priced is None:
                self.faults.append("block %d priced a cart it could not" % idx)
                return
            facts, total, wanted = priced
            if fc["cardTendered"] != total:
                self.faults.append("block %d TOOK A PAYMENT THAT IS NOT THE CART'S TOTAL" % idx)
                return
            for cat_id, q in wanted.items():
                if stock.on_hand(co, shop["stockLocationId"], cat_id) - self.reserved_at(co, shop["stockLocationId"], cat_id) < q:
                    self.faults.append("block %d SOLD WHAT WAS NOT AVAILABLE" % idx)
                    return
            order_act({"family": "amendOrder", "orderId": x["orderId"], "facts": facts})
            order_act({"family": "confirmOrder", "companyId": co, "orderId": x["orderId"], "reason": ""})
            wid = self.next_order
            for cat_id, q in wanted.items():
                self.reservations[self.next_reservation] = {"companyId": co, "locationId": shop["stockLocationId"], "categoryId": cat_id, "orderId": x["orderId"], "quantity": q, "isLive": True}
                self.next_reservation += 1
            self.orders[wid] = {"companyId": co, "storefrontId": x["storefrontId"], "cartId": fc["cartId"], "orderId": x["orderId"], "shopper": caller, "state": "paid",
                                "paymentReference": fc["paymentReference"], "amountPaid": total, "amountRefunded": 0, "checkoutDay": day, "fulfilledDay": 0,
                                "pickingId": 0, "invoiceMoveId": 0, "paymentMoveId": 0, "fulfilledBy": None}
            self.next_order += 1
            x["state"] = "checked-out"
            return

        if f == "fulfilWebOrder":
            co = c["companyId"]
            o = self.orders.get(c["webOrderId"])
            if o is None or o["companyId"] != co or o["state"] != "paid":
                self.faults.append("block %d fulfilled an order it could not" % idx)
                return
            if caller == o["shopper"]:
                self.faults.append("block %d LET THE SHOPPER FULFIL THEIR OWN ORDER" % idx)
                return
            j = ledger.journals.get(c["journalId"])
            if (co, caller) not in hr.members or j is None or j["companyId"] != co or not j["isActive"]:
                self.faults.append("block %d fulfilled an order it could not" % idx)
                return
            sf = self.storefronts[o["storefrontId"]]
            shop = pos.shops[sf["shopId"]]
            p = store.payments.partners.get(shop["partnerId"], {})
            held = [(rid, r) for rid, r in self.reservations_of(o["orderId"]) if r["isLive"]]
            picking_id = 0
            if held:
                facts = {"companyId": co, "fromLocationId": shop["stockLocationId"], "toLocationId": shop["customerLocationId"], "businessDay": day, "partnerId": shop["partnerId"],
                         "reference": "web order %d" % c["webOrderId"], "moves": [{"categoryId": r["categoryId"], "lotId": 0, "quantity": r["quantity"], "unitCost": 0} for _rid, r in held]}
                picking_id = store._consume(block, facts, c["journalId"])
                if picking_id == 0:
                    self.faults.append("block %d shipped goods this reader's stock fold refused" % idx)
                    return
            order_act({"family": "issueInvoice", "companyId": co, "orderId": o["orderId"], "journalId": c["journalId"]})
            inv = credit.orders.get(o["orderId"], {})
            if inv.get("state") != "invoiced":
                self.faults.append("block %d fulfilled an order this reader's order fold would not invoice" % idx)
                return
            if day <= ledger.locks.get(co, 0):
                self.faults.append("block %d posted a web payment into a locked period" % idx)
                return
            payment = {"companyId": co, "journalId": c["journalId"], "businessDay": day, "moveType": "entry", "currency": shop["currency"], "partnerId": shop["partnerId"],
                       "ref": "web order %d paid" % c["webOrderId"],
                       "lines": [{"accountId": shop["cardAccountId"], "partnerId": 0, "name": "card captured", "debit": o["amountPaid"], "credit": 0, "amountCurrency": 0, "taxId": 0},
                                 {"accountId": p.get("receivableAccountId", 0), "partnerId": shop["partnerId"], "name": "web order", "debit": 0, "credit": o["amountPaid"], "amountCurrency": 0, "taxId": 0}]}
            pay_id = ledger._generated(payment, o["shopper"], caller, idx)
            for rid, r in held:
                r["isLive"] = False
            o.update({"state": "fulfilled", "fulfilledDay": day, "pickingId": picking_id, "invoiceMoveId": inv["moveId"], "paymentMoveId": pay_id, "fulfilledBy": caller})
            return

        if f == "cancelWebOrder":
            co = c["companyId"]
            o = self.orders.get(c["webOrderId"])
            if o is None or o["companyId"] != co or o["state"] != "paid" or (caller != o["shopper"] and (co, caller) not in hr.members):
                self.faults.append("block %d cancelled a web order it could not" % idx)
                return
            order_act({"family": "cancelOrder", "companyId": co, "orderId": o["orderId"], "reason": ""})
            for rid, r in self.reservations_of(o["orderId"]):
                r["isLive"] = False
            o.update({"state": "cancelled", "amountRefunded": o["amountPaid"]})
            return

    # -- what the contract prints, recomputed --

    def storefront_line(self, sid):
        """shopId slug open"""
        x = self.storefronts[sid]
        return (x["shopId"], x["slug"], 1 if x["isOpen"] else 0)

    def order_line(self, wid, credit):
        """storefrontId cartId orderId state amountPaid amountRefunded checkoutDay fulfilledDay pickingId invoiceMoveId paymentMoveId - 
        the payment held to the order's total as this reader priced it, the refund to the payment"""
        o = self.orders[wid]
        order = credit.orders.get(o["orderId"])
        if order is None:
            self.faults.append("web order %d names order %d, which this reader does not hold" % (wid, o["orderId"]))
        else:
            total = 0
            for l in order["facts"]["lines"]:
                sub, t = credit.line_amounts_fn(l["quantity"], l["priceUnit"], l["taxRate"])
                total += sub + t
            if total != o["amountPaid"]:
                self.faults.append("web order %d paid %d; its order comes to %d" % (wid, o["amountPaid"], total))
        if o["state"] == "cancelled" and o["amountRefunded"] != o["amountPaid"]:
            self.faults.append("web order %d refunded %d of %d paid" % (wid, o["amountRefunded"], o["amountPaid"]))
        self.payments_held += 1
        return (o["storefrontId"], o["cartId"], o["orderId"], o["state"], o["amountPaid"], o["amountRefunded"], o["checkoutDay"], o["fulfilledDay"], o["pickingId"], o["invoiceMoveId"], o["paymentMoveId"])

    def reservation_line(self, rid, credit, pos):
        """locationId categoryId orderId quantity live - the quantity held to the order's line of that kind"""
        r = self.reservations[rid]
        order = credit.orders.get(r["orderId"])
        if order is not None:
            want = sum(l["quantity"] for l in order["facts"]["lines"] if l["categoryId"] == r["categoryId"])
            if want != r["quantity"]:
                self.faults.append("hold %d holds %d of category %d; the order wants %d" % (rid, r["quantity"], r["categoryId"], want))
        return (r["locationId"], r["categoryId"], r["orderId"], r["quantity"], 1 if r["isLive"] else 0)

    def summary(self):
        return {
            "storefronts": len(self.storefronts),
            "listings": len(self.listings),
            "carts": len(self.carts),
            "orders": len(self.orders),
            "fulfilled": sum(1 for o in self.orders.values() if o["state"] == "fulfilled"),
            "holds": len(self.reservations),
            "faults": len(self.faults),
        }
