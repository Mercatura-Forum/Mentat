"""The bank statement families - typed (143 to 150) and the camt.053 import (344) - decoded from
their canonical bytes, re-encoded, and folded by rules written from the design:

  * a statement from a camt.053 message is read AGAIN here with Python's own XML parser: one Stmt,
    the account's IBAN one the company registered, the opening and closing balances signed by
    their indicator, every booked entry a line dated by its booking day, signed by its indicator,
    referenced by its end-to-end id or the bank's entry reference, its partner the one whose
    registered account carries the counterparty's IBAN;
  * the message itself is held to the OFFICIAL camt.053.001.08 schema (lxml, the hub's copy of the
    ISO base schema, where the hub is beside this tree) and required to be, byte for byte, the
    fixture file under test/fixtures/camt053/ it says it is;
  * a typed statement and its lines fold the same way, so the ids agree.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import os
import xml.etree.ElementTree as ET

from canonical import write_nat, write_text

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
FIXTURES = os.path.join(ROOT, "test", "fixtures", "camt053")
HUB = os.environ.get("HUB") or os.path.join(os.path.dirname(ROOT), "thebes-example-open-banking-iso20022")
if not os.environ.get("HUB") and not os.path.isdir(HUB):
    HUB = os.path.join(os.path.dirname(ROOT), "thebes-example-iso20022")
SCHEMA = os.path.join(HUB, "integration-kit", "profile-runner", "official-schemas", "iso-base", "camt.053.001.08.xsd")
NS = "urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"


def zag(n):
    return n // 2 if n % 2 == 0 else -((n + 1) // 2)


def zig(i):
    return i * 2 if i >= 0 else -i * 2 - 1


READERS = {
    143: ("importBankStatement", lambda r: {"facts": {"companyId": r.nat(), "journalId": r.nat(), "name": r.text(), "statementDay": r.nat(), "currency": r.text(),
                                                      "balanceStart": zag(r.nat()), "balanceEndDeclared": zag(r.nat())}}),
    144: ("addStatementLine",    lambda r: {"facts": {"companyId": r.nat(), "statementId": r.nat(), "transactionDay": r.nat(), "paymentRef": r.text(),
                                                      "amount": zag(r.nat()), "foreignAmount": zag(r.nat()), "foreignCurrency": r.text(), "partnerId": r.nat()}}),
    145: ("confirmBankStatement", lambda r: {"companyId": r.nat(), "statementId": r.nat()}),
    146: ("archiveBankStatement", lambda r: {"companyId": r.nat(), "statementId": r.nat(), "reason": r.text()}),
    147: ("reconcileLine",       lambda r: {"companyId": r.nat(), "lineId": r.nat(), "moveId": r.nat(), "amount": r.nat()}),
    148: ("unreconcileLine",     lambda r: {"companyId": r.nat(), "reconciliationId": r.nat(), "reason": r.text()}),
    149: ("openMatchRun",        lambda r: {"companyId": r.nat(), "statementId": r.nat(), "planHash": r.blob()}),
    150: ("matchSlice",          lambda r: {"companyId": r.nat(), "runId": r.nat(), "planHash": r.blob(), "limit": r.nat()}),
    344: ("importCamt053",       lambda r: {"companyId": r.nat(), "journalId": r.nat(), "xml": r.blob()}),
}
FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_statement_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def _blob(b):
    if len(b) > 65535:
        raise ValueError("a blob of %d bytes" % len(b))
    return len(b).to_bytes(2, "big") + bytes(b)


ENCODERS = {
    "importBankStatement":  (143, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["journalId"]) + write_text(c["facts"]["name"]) + write_nat(c["facts"]["statementDay"])
                                            + write_text(c["facts"]["currency"]) + write_nat(zig(c["facts"]["balanceStart"])) + write_nat(zig(c["facts"]["balanceEndDeclared"]))),
    "addStatementLine":     (144, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["statementId"]) + write_nat(c["facts"]["transactionDay"]) + write_text(c["facts"]["paymentRef"])
                                            + write_nat(zig(c["facts"]["amount"])) + write_nat(zig(c["facts"]["foreignAmount"])) + write_text(c["facts"]["foreignCurrency"]) + write_nat(c["facts"]["partnerId"])),
    "confirmBankStatement": (145, lambda c: write_nat(c["companyId"]) + write_nat(c["statementId"])),
    "archiveBankStatement": (146, lambda c: write_nat(c["companyId"]) + write_nat(c["statementId"]) + write_text(c["reason"])),
    "reconcileLine":        (147, lambda c: write_nat(c["companyId"]) + write_nat(c["lineId"]) + write_nat(c["moveId"]) + write_nat(c["amount"])),
    "unreconcileLine":      (148, lambda c: write_nat(c["companyId"]) + write_nat(c["reconciliationId"]) + write_text(c["reason"])),
    "openMatchRun":         (149, lambda c: write_nat(c["companyId"]) + write_nat(c["statementId"]) + _blob(c["planHash"])),
    "matchSlice":           (150, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + _blob(c["planHash"]) + write_nat(c["limit"])),
    "importCamt053":        (344, lambda c: write_nat(c["companyId"]) + write_nat(c["journalId"]) + _blob(c["xml"])),
}


def statement_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


# ── the message, read again ────────────────────────────────────────────────────

def parse_amount(text, exponent):
    text = text.strip()
    if not text or text.count(".") > 1 or not text.replace(".", "").isdigit():
        return None
    whole, _, frac = text.partition(".")
    if len(frac) > exponent:
        return None
    return int(whole or "0") * 10 ** exponent + int((frac or "0").ljust(exponent, "0"))


def day_of(text):
    """Days since 1970-01-01 of a YYYY-MM-DD, strictly."""
    import datetime
    try:
        d = datetime.date.fromisoformat(text.strip())
    except ValueError:
        return None
    if len(text.strip()) != 10:
        return None
    return (d - datetime.date(1970, 1, 1)).days


def q(tag):
    return "{%s}%s" % (NS, tag)


def read_camt053(xml_bytes, exponent):
    """The statement as this reader reads it: (name, currency, iban, day, opening, closing, entries)
    where an entry is (day, signed amount, reference, counterparty IBAN or None), or a string saying
    why the message is not a statement this system reads."""
    text = xml_bytes.decode("utf-8")
    if "<!DOCTYPE" in text or "<!ENTITY" in text:
        return "a document type declaration"
    # a header may precede the document: wrap, and take the last root
    body = text.split("?>", 1)[1] if text.lstrip().startswith("<?xml") else text
    try:
        root = ET.fromstring("<x>" + body + "</x>")
    except ET.ParseError as e:
        return "not well-formed: %s" % e
    doc = list(root)[-1] if len(root) else None
    if doc is None or doc.tag != q("Document"):
        return "the root is not a camt.053 Document"
    stmts = doc.findall("./%s/%s" % (q("BkToCstmrStmt"), q("Stmt")))
    if len(stmts) != 1:
        return "%d Stmt elements" % len(stmts)
    st = stmts[0]
    name = (st.findtext(q("Id")) or "").strip()
    iban = (st.findtext("./%s/%s/%s" % (q("Acct"), q("Id"), q("IBAN"))) or "").strip()
    ccy = (st.findtext("./%s/%s" % (q("Acct"), q("Ccy"))) or "").strip()

    def balance(code):
        for b in st.findall(q("Bal")):
            if (b.findtext("./%s/%s/%s" % (q("Tp"), q("CdOrPrtry"), q("Cd"))) or "").strip() == code:
                amt = b.find(q("Amt"))
                if amt is None or amt.get("Ccy") != ccy:
                    return None
                v = parse_amount(amt.text or "", exponent)
                ind = (b.findtext(q("CdtDbtInd")) or "").strip()
                if v is None or ind not in ("CRDT", "DBIT"):
                    return None
                return (v if ind == "CRDT" else -v, (b.findtext("./%s/%s" % (q("Dt"), q("Dt"))) or "").strip())
        return None

    opening, closing = balance("OPBD"), balance("CLBD")
    if opening is None or closing is None or not name or not iban:
        return "no name, account, opening or closing balance"
    day = day_of(closing[1]) if closing[1] else day_of((st.findtext(q("CreDtTm")) or "")[:10])
    entries = []
    for e in st.findall(q("Ntry")):
        amt = e.find(q("Amt"))
        if amt is None or amt.get("Ccy") != ccy:
            return "an entry in another currency"
        v = parse_amount(amt.text or "", exponent)
        ind = (e.findtext(q("CdtDbtInd")) or "").strip()
        status = e.findtext("./%s/%s" % (q("Sts"), q("Cd")))
        if v is None or v == 0 or ind not in ("CRDT", "DBIT") or (status is not None and status.strip() != "BOOK"):
            return "an entry that is not a booked amount"
        dt = e.findtext("./%s/%s" % (q("BookgDt"), q("Dt"))) or e.findtext("./%s/%s" % (q("ValDt"), q("Dt")))
        eday = day_of(dt) if dt else None
        if eday is None:
            return "an entry without a date"
        tx = e.find("./%s/%s" % (q("NtryDtls"), q("TxDtls")))
        ref = None
        if tx is not None:
            ref = tx.findtext("./%s/%s" % (q("Refs"), q("EndToEndId")))
        if ref is None:
            ref = e.findtext(q("NtryRef")) or ""
        side = "DbtrAcct" if ind == "CRDT" else "CdtrAcct"
        cp = tx.findtext("./%s/%s/%s/%s" % (q("RltdPties"), q(side), q("Id"), q("IBAN"))) if tx is not None else None
        entries.append((eday, v if ind == "CRDT" else -v, ref.strip(), cp.strip() if cp else None))
    if not entries:
        return "no entry"
    return (name, ccy, iban, day, opening[0], closing[0], entries)


def schema_valid(xml_bytes):
    """The Document element of the message against the official camt.053.001.08 schema, where the
    hub's copy is on this machine; None when it is not, so the gate can say so."""
    if not os.path.exists(SCHEMA):
        return None
    from lxml import etree
    text = xml_bytes.decode("utf-8")
    body = text.split("?>", 1)[1] if text.lstrip().startswith("<?xml") else text
    root = etree.fromstring(("<x>" + body + "</x>").encode("utf-8"))
    doc = [c for c in root if c.tag == q("Document")]
    if not doc:
        return False
    return etree.XMLSchema(etree.parse(SCHEMA)).validate(doc[0])


def fixture_named(xml_bytes):
    """The fixture file these bytes are, byte for byte, or None."""
    if not os.path.isdir(FIXTURES):
        return None
    for name in sorted(os.listdir(FIXTURES)):
        if name.endswith(".xml") and open(os.path.join(FIXTURES, name), "rb").read() == xml_bytes:
            return name
    return None


class Statements:
    def __init__(self):
        self.statements = {}   # id -> {name, currency, day, start, declared, computed, state, companyId, fromCamt}
        self.lines = {}        # statement id -> [(day, amount, ref, partnerId)]
        self.next_statement = 1
        self.next_line = 1
        self.camt_messages = []   # (statement id, bytes)
        self.faults = []

    def apply(self, block, ledger, payments):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        if f == "importBankStatement":
            fc = c["facts"]
            self.statements[self.next_statement] = {"name": fc["name"], "currency": fc["currency"], "day": fc["statementDay"], "start": fc["balanceStart"],
                                                    "declared": fc["balanceEndDeclared"], "computed": fc["balanceStart"], "state": "draft", "companyId": fc["companyId"], "fromCamt": False}
            self.lines[self.next_statement] = []
            self.next_statement += 1
            return
        if f == "addStatementLine":
            fc = c["facts"]
            st = self.statements.get(fc["statementId"])
            if st is None or st["state"] != "draft" or fc["amount"] == 0:
                self.faults.append("block %d added a statement line it could not" % idx)
                return
            self.lines[fc["statementId"]].append((fc["transactionDay"], fc["amount"], fc["paymentRef"], fc["partnerId"]))
            self.next_line += 1
            st["computed"] += fc["amount"]
            return
        if f == "confirmBankStatement":
            st = self.statements.get(c["statementId"])
            if st is None or st["state"] != "draft" or st["computed"] != st["declared"]:
                self.faults.append("block %d confirmed a statement it could not" % idx)
                return
            st["state"] = "confirmed"
            return
        if f == "archiveBankStatement":
            st = self.statements.get(c["statementId"])
            if st is not None:
                st["state"] = "archived"
            return
        if f == "importCamt053":
            co = c["companyId"]
            exponent = 2
            # the account's currency, from the payment reader's registered accounts
            acct = next((a for a in payments.bank_accounts.values() if a["companyId"] == co), None)
            matching = [a for a in payments.bank_accounts.values() if a["companyId"] == co]
            parsed = read_camt053(c["xml"], exponent)
            if isinstance(parsed, str):
                self.faults.append("block %d imported a statement this reader cannot read: %s" % (idx, parsed))
                return
            name, ccy, iban, day, opening, closing, entries = parsed
            owned = [a for a in matching if a["iban"] == iban]
            if not owned or owned[0]["currency"] != ccy:
                self.faults.append("block %d imported a statement for an account the company did not register in that currency" % idx)
            cur = ledger.currencies.get((co, ccy))
            if cur is not None and cur["exponent"] != exponent:
                parsed = read_camt053(c["xml"], cur["exponent"])
                name, ccy, iban, day, opening, closing, entries = parsed
            lines = []
            for eday, amount, ref, cp in entries:
                partner = 0
                if cp:
                    for (pco, pid), pb in payments.partner_bank.items():
                        if pco == co and pb["iban"] == cp:
                            partner = pid
                lines.append((eday, amount, ref, partner))
                self.next_line += 1
            sid = self.next_statement
            self.next_statement += 1
            self.statements[sid] = {"name": name, "currency": ccy, "day": day, "start": opening, "declared": closing, "computed": opening + sum(l[1] for l in lines),
                                    "state": "draft", "companyId": co, "fromCamt": True}
            self.lines[sid] = lines
            self.camt_messages.append((sid, bytes(c["xml"])))
            return
        # reconciliations and the match run are the ledger's and the finance fold's; not refolded here

    def camt_line(self, sid):
        st = self.statements[sid]
        return (st["name"], st["state"], st["currency"], st["day"], st["start"], st["declared"], st["computed"], len(self.lines[sid]),
                tuple((n + 1, d, a, r, p) for n, (d, a, r, p) in enumerate(self.lines[sid])))

    def summary(self):
        return {"statements": len(self.statements), "from_camt": sum(1 for s in self.statements.values() if s["fromCamt"]),
                "lines": sum(len(v) for v in self.lines.values()), "faults": len(self.faults)}
