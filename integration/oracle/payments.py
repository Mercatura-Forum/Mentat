"""The payment families (338 to 343) and the three-way match's (285 to 287), decoded from their
canonical bytes, re-encoded so the command hash can be re-derived, and folded by rules written from
the design:

  * a bank account's IBAN passes ISO 13616's MOD 97-10 and the Egyptian shape under EG, its BIC is
    ISO 9362's shape, and it stands on an asset account;
  * a supplier bill's total is its lines' quantity × price over a thousand, summed; the match posts
    the lines to their categories' expense accounts and the total to the partner's payable, as a
    move proposed in the matcher's name - handed to the ledger reader, so the posting that follows
    finds it;
  * a payment pays a matched bill whose liability is posted, once, in its currency, for its amount;
    the reader REBUILDS the pacs.008 from the same rows with its own writer and requires the same
    bytes under the same SHA-256;
  * the acceptance, by somebody who is not the preparer, posts the payable against the bank's
    account through the ledger reader; the rejection posts nothing.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import hashlib

from accounting import civil_from_days
from canonical import write_nat, write_text


def read_bill_lines(r):
    return [{"categoryId": r.nat(), "quantity": r.nat(), "priceUnit": r.nat()} for _ in range(r.len16())]


READERS = {
    285: ("assignReceiptToOrder",    lambda r: {"companyId": r.nat(), "pickingId": r.nat(), "orderId": r.nat()}),
    286: ("recordSupplierBill",      lambda r: {"facts": {"companyId": r.nat(), "orderId": r.nat(), "billDay": r.nat(), "currency": r.text(),
                                                          "supplierRef": r.text(), "lines": read_bill_lines(r)}}),
    287: ("matchSupplierBill",       lambda r: {"companyId": r.nat(), "billId": r.nat(), "journalId": r.nat(), "reason": r.text()}),
    338: ("registerBankAccount",     lambda r: {"facts": {"companyId": r.nat(), "name": r.text(), "iban": r.text(), "bic": r.text(),
                                                          "currency": r.text(), "ledgerAccountId": r.nat()}}),
    339: ("setPartnerBankAccount",   lambda r: {"facts": {"companyId": r.nat(), "partnerId": r.nat(), "holderName": r.text(), "iban": r.text(), "bic": r.text()}}),
    340: ("preparePayment",          lambda r: {"facts": {"companyId": r.nat(), "billId": r.nat(), "bankAccountId": r.nat(), "remittance": r.text()}}),
    341: ("recordPaymentSubmission", lambda r: {"companyId": r.nat(), "paymentId": r.nat(), "payloadHash": r.blob()}),
    342: ("recordPaymentResult",     lambda r: {"facts": {"companyId": r.nat(), "paymentId": r.nat(), "payloadHash": r.blob(), "accepted": r.bool(),
                                                          "hubReference": r.text(), "reason": r.text()}}),
    343: ("cancelPayment",           lambda r: {"companyId": r.nat(), "paymentId": r.nat(), "reason": r.text()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}
# the families this module notes without owning: partners, categories and orders, which the bill and the payment read
NOTED_FAMILIES = {"createPartner", "amendPartner", "createCategory", "amendCategory", "placeOrder", "confirmOrder"}


def read_payment_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def _write_blob(b):
    return len(b).to_bytes(2, "big") + bytes(b)


def _write_bill(f):
    out = write_nat(f["companyId"]) + write_nat(f["orderId"]) + write_nat(f["billDay"]) + write_text(f["currency"]) + write_text(f["supplierRef"])
    out += len(f["lines"]).to_bytes(2, "big")
    for l in f["lines"]:
        out += write_nat(l["categoryId"]) + write_nat(l["quantity"]) + write_nat(l["priceUnit"])
    return out


ENCODERS = {
    "assignReceiptToOrder":    (285, lambda c: write_nat(c["companyId"]) + write_nat(c["pickingId"]) + write_nat(c["orderId"])),
    "recordSupplierBill":      (286, lambda c: _write_bill(c["facts"])),
    "matchSupplierBill":       (287, lambda c: write_nat(c["companyId"]) + write_nat(c["billId"]) + write_nat(c["journalId"]) + write_text(c["reason"])),
    "registerBankAccount":     (338, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["name"]) + write_text(c["facts"]["iban"]) + write_text(c["facts"]["bic"])
                                               + write_text(c["facts"]["currency"]) + write_nat(c["facts"]["ledgerAccountId"])),
    "setPartnerBankAccount":   (339, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["partnerId"]) + write_text(c["facts"]["holderName"])
                                               + write_text(c["facts"]["iban"]) + write_text(c["facts"]["bic"])),
    "preparePayment":          (340, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["billId"]) + write_nat(c["facts"]["bankAccountId"]) + write_text(c["facts"]["remittance"])),
    "recordPaymentSubmission": (341, lambda c: write_nat(c["companyId"]) + write_nat(c["paymentId"]) + _write_blob(c["payloadHash"])),
    "recordPaymentResult":     (342, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["paymentId"]) + _write_blob(c["facts"]["payloadHash"])
                                               + bytes([1 if c["facts"]["accepted"] else 0]) + write_text(c["facts"]["hubReference"]) + write_text(c["facts"]["reason"])),
    "cancelPayment":           (343, lambda c: write_nat(c["companyId"]) + write_nat(c["paymentId"]) + write_text(c["reason"])),
}


def payment_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


# ── the identifiers and the message, by this reader's own rules ───────────────

SWIFT_X = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 \n\r'()+,-./:?")


def swift_x(t):
    return all(ch in SWIFT_X for ch in t)


def text_fits(t, maximum):
    return 0 < len(t) <= maximum and swift_x(t)


def mod97(s):
    r = 0
    for ch in s:
        if ch.isdigit():
            r = (r * 10 + int(ch)) % 97
        elif "A" <= ch <= "Z":
            r = (r * 100 + ord(ch) - 55) % 97
        else:
            return None
    return r


def valid_iban(iban):
    if not 15 <= len(iban) <= 34 or not (iban[0].isupper() and iban[1].isupper() and iban[2].isdigit() and iban[3].isdigit()):
        return False
    return mod97(iban[4:] + iban[:4]) == 1


def egyptian_shape(iban):
    return len(iban) == 29 and iban[:2] == "EG" and iban[2:].isdigit()


def valid_bic(bic):
    if len(bic) not in (8, 11):
        return False
    return (bic[:6].isalpha() and bic[:6].isupper() and all(c.isupper() or c.isdigit() for c in bic[6:]))


def derive_uetr(company, payment):
    h = bytearray(hashlib.sha256(("MENTAT-UETR-v1:%d:%d" % (company, payment)).encode()).digest()[:16])
    h[6] = (h[6] & 0x0F) | 0x40
    h[8] = (h[8] & 0x3F) | 0x80
    hx = h.hex()
    return "%s-%s-%s-%s-%s" % (hx[:8], hx[8:12], hx[12:16], hx[16:20], hx[20:])


def iso_datetime(day):
    y, m, d = civil_from_days(day)
    return "%04d-%02d-%02dT00:00:00Z" % (y, m, d)


def amount_text(minor):
    return "%d.%02d" % (minor // 100, minor % 100)


def escape(v):
    return v.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;").replace("'", "&apos;")


def elem(indent, tag, value):
    return " " * indent + "<%s>%s</%s>\n" % (tag, escape(value), tag)


def build_pacs008(i):
    """The hub's compact pacs.008, element for element as the contract writes it, from a dict of
    the same fields: messageId, endToEndId, uetr, businessDay, currency, minorUnits, debtorName,
    debtorIban, debtorBic, creditorName, creditorIban, creditorBic, remittance, creditorReference."""
    created = iso_datetime(i["businessDay"])

    def agent(tag, bic):
        return " " * 6 + "<%s><FinInstnId>\n" % tag + elem(8, "BICFI", bic) + " " * 6 + "</FinInstnId></%s>\n" % tag

    def party(tag, name):
        return " " * 6 + "<%s>\n" % tag + elem(8, "Nm", name) + " " * 6 + "</%s>\n" % tag

    def account(tag, iban, ccy):
        return (" " * 6 + "<%s>\n" % tag + " " * 8 + "<Id>\n" + elem(10, "IBAN", iban) + " " * 8 + "</Id>\n" + elem(8, "Ccy", ccy) + " " * 6 + "</%s>\n" % tag)

    return ("<AppHdr xmlns=\"urn:iso:std:iso:20022:tech:xsd:head.001.001.02\">\n"
            + "  <Fr><FIId><FinInstnId><BICFI>%s</BICFI></FinInstnId></FIId></Fr>\n" % escape(i["debtorBic"])
            + "  <To><FIId><FinInstnId><BICFI>%s</BICFI></FinInstnId></FIId></To>\n" % escape(i["creditorBic"])
            + elem(2, "BizMsgIdr", i["messageId"]) + elem(2, "MsgDefIdr", "pacs.008.001.08") + elem(2, "CreDt", created) + elem(2, "UETR", i["uetr"])
            + "</AppHdr>\n"
            + "<Document xmlns=\"urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08\">\n"
            + "  <FIToFICstmrCdtTrf>\n    <GrpHdr>\n"
            + elem(6, "MsgId", i["messageId"]) + elem(6, "CreDtTm", created) + elem(6, "NbOfTxs", "1")
            + "      <SttlmInf>\n" + elem(8, "SttlmMtd", "CLRG") + "      </SttlmInf>\n    </GrpHdr>\n    <CdtTrfTxInf>\n      <PmtId>\n"
            + elem(8, "EndToEndId", i["endToEndId"]) + elem(8, "UETR", i["uetr"]) + "      </PmtId>\n      <PmtTpInf>\n" + elem(8, "CtgyPurp", "SUPP") + "      </PmtTpInf>\n"
            + "      <Amt><InstdAmt Ccy=\"%s\">%s</InstdAmt></Amt>\n" % (escape(i["currency"]), amount_text(i["minorUnits"]))
            + agent("DbtrAgt", i["debtorBic"]) + party("Dbtr", i["debtorName"]) + account("DbtrAcct", i["debtorIban"], i["currency"])
            + agent("CdtrAgt", i["creditorBic"]) + party("Cdtr", i["creditorName"]) + account("CdtrAcct", i["creditorIban"], i["currency"])
            + "      <RmtInf>\n" + elem(8, "Ustrd", i["remittance"])
            + "        <Strd><CdtrRefInf>" + elem(0, "Ref", i["creditorReference"]) + "</CdtrRefInf></Strd>\n"
            + "      </RmtInf>\n    </CdtTrfTxInf>\n  </FIToFICstmrCdtTrf>\n</Document>\n")


LIVE = {"prepared", "submitted", "accepted"}


class Payments:
    def __init__(self):
        self.partners = {}        # id -> facts
        self.categories = {}      # id -> facts
        self.orders = {}          # id -> {companyId, partnerId, currency, state}
        self.bills = {}           # id -> {companyId, orderId, partnerId, currency, supplierRef, total, state, moveId}
        self.bank_accounts = {}   # id -> facts
        self.partner_bank = {}    # (company, partner) -> {holderName, iban, bic}
        self.payments = {}        # id -> the payment
        self.companies = None     # set by the store: id -> company row
        self.next_partner = 1
        self.next_category = 1
        self.next_order = 1
        self.next_bill = 1
        self.next_bank_account = 1
        self.next_payment = 1
        self.faults = []

    # -- what the order families say, noted --

    def note(self, block):
        c = block["command"]
        f = c["family"]
        if f == "createPartner":
            self.partners[self.next_partner] = c["facts"]
            self.next_partner += 1
        elif f == "amendPartner":
            if c["partnerId"] in self.partners:
                self.partners[c["partnerId"]] = c["facts"]
        elif f == "createCategory":
            self.categories[self.next_category] = c["facts"]
            self.next_category += 1
        elif f == "amendCategory":
            if c["categoryId"] in self.categories:
                self.categories[c["categoryId"]] = c["facts"]
        elif f == "placeOrder":
            fc = c["facts"]
            self.orders[self.next_order] = {"companyId": fc["companyId"], "partnerId": fc["partnerId"], "currency": fc["currency"], "direction": fc["direction"], "state": "draft"}
            self.next_order += 1
        elif f == "confirmOrder":
            o = self.orders.get(c["orderId"])
            if o is not None:
                o["state"] = "confirmed"

    # -- the fold --

    def apply(self, block, ledger):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        caller = block["caller"]
        day = block["day"]

        if f == "assignReceiptToOrder":
            return
        if f == "recordSupplierBill":
            fc = c["facts"]
            o = self.orders.get(fc["orderId"])
            if o is None or o["companyId"] != fc["companyId"] or o["state"] != "confirmed" or o["direction"] != "purchase" or o["currency"] != fc["currency"] or not fc["lines"]:
                self.faults.append("block %d recorded a bill it could not" % idx)
            total = sum(l["quantity"] * l["priceUnit"] // 1000 for l in fc["lines"])
            self.bills[self.next_bill] = {"companyId": fc["companyId"], "orderId": fc["orderId"], "partnerId": o["partnerId"] if o else 0, "currency": fc["currency"],
                                          "supplierRef": fc["supplierRef"], "lines": fc["lines"], "total": total, "state": "recorded", "moveId": 0, "recordedBy": caller,
                                          "billDay": fc["billDay"], "matchedBy": caller}
            self.next_bill += 1
            return
        if f == "matchSupplierBill":
            b = self.bills.get(c["billId"])
            if b is None or b["companyId"] != c["companyId"] or b["state"] != "recorded" or b["recordedBy"] == caller:
                self.faults.append("block %d matched a bill it could not" % idx)
                return
            lines = []
            for n, l in enumerate(b["lines"], 1):
                cat = self.categories.get(l["categoryId"], {})
                lines.append({"accountId": cat.get("expenseAccountId", 0), "partnerId": b["partnerId"], "name": "bill line %d" % (n - 1),
                              "debit": l["quantity"] * l["priceUnit"] // 1000, "credit": 0, "amountCurrency": 0, "taxId": 0})
            payable = self.partners.get(b["partnerId"], {}).get("payableAccountId", 0)
            lines.append({"accountId": payable, "partnerId": b["partnerId"], "name": "supplier bill %d" % c["billId"], "debit": 0, "credit": b["total"], "amountCurrency": 0, "taxId": 0})
            # THE MATCH PROPOSES through the ledger: a move in the matcher's name, posted later by a postMove block like any other
            ledger.apply({"command": {"family": "proposeMove", "facts": {"companyId": b["companyId"], "journalId": c["journalId"], "businessDay": day, "moveType": "entry",
                                                                       "currency": b["currency"], "partnerId": b["partnerId"], "ref": "bill %d" % c["billId"], "lines": lines}},
                          "index": idx, "caller": caller, "day": day})
            b["state"], b["moveId"], b["payableAccountId"], b["matchedBy"] = "matched", ledger.next_move - 1, payable, caller
            return

        if f == "registerBankAccount":
            fc = c["facts"]
            a = ledger.accounts.get(fc["ledgerAccountId"])
            taken = any(x["companyId"] == fc["companyId"] and x["iban"] == fc["iban"] for x in self.bank_accounts.values())
            if (not fc["name"] or not valid_iban(fc["iban"]) or (fc["iban"].startswith("EG") and not egyptian_shape(fc["iban"])) or not valid_bic(fc["bic"])
                    or not (len(fc["currency"]) == 3 and fc["currency"].isupper()) or a is None or a["companyId"] != fc["companyId"] or a["accountType"] != "asset" or taken):
                self.faults.append("block %d registered a bank account it could not" % idx)
            self.bank_accounts[self.next_bank_account] = dict(fc)
            self.next_bank_account += 1
            return
        if f == "setPartnerBankAccount":
            fc = c["facts"]
            p = self.partners.get(fc["partnerId"])
            if (p is None or p["companyId"] != fc["companyId"] or not (p["isSupplier"] or p["isCustomer"]) or not text_fits(fc["holderName"], 140) or not valid_iban(fc["iban"])
                    or (fc["iban"].startswith("EG") and not egyptian_shape(fc["iban"])) or not valid_bic(fc["bic"])):
                self.faults.append("block %d set a partner's bank account it could not" % idx)
            self.partner_bank[(fc["companyId"], fc["partnerId"])] = {"holderName": fc["holderName"], "iban": fc["iban"], "bic": fc["bic"]}
            return

        if f == "preparePayment":
            fc = c["facts"]
            b = self.bills.get(fc["billId"])
            acct = self.bank_accounts.get(fc["bankAccountId"])
            bad = None
            if b is None or b["companyId"] != fc["companyId"] or b["state"] != "matched":
                bad = "a bill that is not matched"
            elif ledger.moves.get(b["moveId"], {}).get("state") != "posted":
                bad = "a bill whose liability is not posted"
            elif any(p["billId"] == fc["billId"] and p["state"] in LIVE for p in self.payments.values()):
                bad = "a bill with a payment live"
            elif acct is None or acct["companyId"] != fc["companyId"] or acct["currency"] != b["currency"]:
                bad = "an account it could not pay from"
            elif (fc["companyId"], b["partnerId"]) not in self.partner_bank:
                bad = "a supplier whose account is not known"
            elif not text_fits(fc["remittance"], 140):
                bad = "a remittance the hub would refuse"
            if bad is not None:
                self.faults.append("block %d prepared a payment of %s" % (idx, bad))
            pid = self.next_payment
            self.next_payment += 1
            pba = self.partner_bank.get((fc["companyId"], b["partnerId"] if b else 0), {"holderName": "", "iban": "", "bic": ""})
            company_name = self.companies.get(fc["companyId"], {}).get("name", "") if self.companies else ""
            instruction = {"messageId": "MENTAT-%d-%d" % (fc["companyId"], pid), "endToEndId": "BILL-%d-%d" % (fc["billId"], pid), "uetr": derive_uetr(fc["companyId"], pid),
                           "businessDay": day, "currency": b["currency"] if b else "", "minorUnits": b["total"] if b else 0,
                           "debtorName": company_name, "debtorIban": acct["iban"] if acct else "", "debtorBic": acct["bic"] if acct else "",
                           "creditorName": pba["holderName"], "creditorIban": pba["iban"], "creditorBic": pba["bic"],
                           "remittance": fc["remittance"], "creditorReference": b["supplierRef"] if b else ""}
            message = build_pacs008(instruction)
            self.payments[pid] = {"companyId": fc["companyId"], "billId": fc["billId"], "partnerId": b["partnerId"] if b else 0, "bankAccountId": fc["bankAccountId"],
                                  "payableAccountId": b.get("payableAccountId", 0) if b else 0, "amount": b["total"] if b else 0, "currency": b["currency"] if b else "",
                                  "uetr": instruction["uetr"], "message": message, "hash": hashlib.sha256(message.encode("utf-8")).digest(),
                                  "state": "prepared", "moveId": 0, "preparedBy": caller, "journalId": ledger.moves.get(b["moveId"], {}).get("journalId", 0) if b else 0}
            return

        p = self.payments.get(c.get("paymentId", c.get("facts", {}).get("paymentId")))
        company = c.get("companyId", c.get("facts", {}).get("companyId"))
        if p is None or p["companyId"] != company:
            self.faults.append("block %d acted on a payment it could not" % idx)
            return

        if f == "recordPaymentSubmission":
            if p["state"] != "prepared" or c["payloadHash"] != p["hash"] or caller == p["preparedBy"]:
                self.faults.append("block %d recorded a submission it could not" % idx)
                return
            p["state"] = "submitted"
            return
        if f == "cancelPayment":
            if p["state"] != "prepared":
                self.faults.append("block %d withdrew a payment it could not" % idx)
                return
            p["state"] = "cancelled"
            return
        if f == "recordPaymentResult":
            fc = c["facts"]
            if p["state"] != "submitted" or fc["payloadHash"] != p["hash"] or caller == p["preparedBy"]:
                self.faults.append("block %d recorded the hub's word it could not" % idx)
                return
            if not fc["accepted"]:
                if not fc["reason"]:
                    self.faults.append("block %d rejected a payment with no reason" % idx)
                p["state"] = "rejected"
                return
            acct = self.bank_accounts[p["bankAccountId"]]
            if day <= ledger.locks.get(p["companyId"], 0):
                self.faults.append("block %d posted a payment into a locked period" % idx)
            lines = [{"accountId": p["payableAccountId"], "partnerId": p["partnerId"], "name": "paid", "debit": p["amount"], "credit": 0, "amountCurrency": 0, "taxId": 0},
                     {"accountId": acct["ledgerAccountId"], "partnerId": p["partnerId"], "name": "paid", "debit": 0, "credit": p["amount"], "amountCurrency": 0, "taxId": 0}]
            mid = ledger._generated({"companyId": p["companyId"], "journalId": p["journalId"], "businessDay": day, "moveType": "entry", "currency": p["currency"],
                                     "partnerId": p["partnerId"], "ref": "payment %d of bill %d" % (c["facts"]["paymentId"], p["billId"]), "lines": lines},
                                    p["preparedBy"], caller, idx)
            p["state"], p["moveId"] = "accepted", mid
            return

    # -- what the contract prints, recomputed --

    def payment_line(self, pid):
        """state, billId, amount, currency, the UETR, the SHA-256 of the rebuilt message in hex, posted."""
        p = self.payments[pid]
        return (p["state"], p["billId"], p["amount"], p["currency"], p["uetr"], p["hash"].hex(), 1 if p["moveId"] else 0)

    def summary(self):
        return {
            "bills": len(self.bills),
            "matched": sum(1 for b in self.bills.values() if b["state"] == "matched"),
            "bank_accounts": len(self.bank_accounts),
            "payments": len(self.payments),
            "accepted": sum(1 for p in self.payments.values() if p["state"] == "accepted"),
            "rejected": sum(1 for p in self.payments.values() if p["state"] == "rejected"),
            "faults": len(self.faults),
        }
