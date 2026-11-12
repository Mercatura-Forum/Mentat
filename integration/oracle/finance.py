"""The tax-authority filing families and the credit note, decoded and re-encoded independently.

Families 151 to 155 (the endpoint configuration, a filing prepared, submitted, answered and
abandoned) and 288 to 293 (the credit note, the issuer profile, the receiver's address, the item's
code, the credit note's filing, the seal), as `src/Encoding.mo` specifies them under version 1.
Written from the specification, so a block read off a chain can be decoded here, re-encoded here,
and required to be the very bytes the contract hashed.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text

ETA_DOC_TYPE = {1: "invoice", 2: "creditNote", 3: "debitNote"}


def named(table, b, what):
    if b not in table:
        raise ValueError("unknown %s code %d" % (what, b))
    return table[b]


def code_of(table, name, what):
    for b, n in table.items():
        if n == name:
            return b
    raise ValueError("unknown %s name %r" % (what, name))


def write_blob(b: bytes) -> bytes:
    if len(b) > 65535:
        raise ValueError("a blob of %d bytes" % len(b))
    return len(b).to_bytes(2, "big") + b


def _bool(b):
    return b"\x01" if b else b"\x00"


# ── decoders ────────────────────────────────────────────────────────────────────

def read_config_facts(r):
    return {"companyId": r.nat(), "endpoint": r.text(), "issuerTaxId": r.text(), "issuerName": r.text(),
            "activityCode": r.text(), "keyHandle": r.text()}


def read_filing_facts(r):
    return {"companyId": r.nat(), "orderId": r.nat(), "docType": named(ETA_DOC_TYPE, r.nat8(), "document type"),
            "version": r.text()}


def read_result_facts(r):
    return {"companyId": r.nat(), "filingId": r.nat(), "payloadHash": r.blob(), "accepted": r.bool(),
            "uuid": r.text(), "submissionId": r.text(), "longId": r.text(), "reason": r.text()}


def read_credit_note_facts(r):
    companyId, orderId, journalId, reason = r.nat(), r.nat(), r.nat(), r.text()
    n = r.len16()
    lines = [{"ordinal": r.nat(), "quantity": r.nat()} for _ in range(n)]
    return {"companyId": companyId, "orderId": orderId, "journalId": journalId, "reason": reason, "lines": lines}


def read_issuer_profile(r):
    return {"companyId": r.nat(), "partyType": r.text(), "branchId": r.text(), "country": r.text(),
            "governate": r.text(), "regionCity": r.text(), "street": r.text(), "buildingNumber": r.text(),
            "postalCode": r.text(), "anchorCertificate": r.blob()}


def read_partner_address(r):
    return {"companyId": r.nat(), "partnerId": r.nat(), "partyType": r.text(), "country": r.text(),
            "governate": r.text(), "regionCity": r.text(), "street": r.text(), "buildingNumber": r.text(),
            "postalCode": r.text()}


def read_category_tax_profile(r):
    return {"companyId": r.nat(), "categoryId": r.nat(), "itemType": r.text(), "itemCode": r.text(),
            "unitType": r.text(), "taxType": r.text(), "taxSubType": r.text()}


READERS = {
    151: ("configureEtaEndpoint",   lambda r: {"facts": read_config_facts(r)}),
    152: ("prepareEtaFiling",       lambda r: {"facts": read_filing_facts(r)}),
    153: ("recordEtaSubmission",    lambda r: {"companyId": r.nat(), "filingId": r.nat(), "payloadHash": r.blob()}),
    154: ("recordEtaResult",        lambda r: {"facts": read_result_facts(r)}),
    155: ("abandonEtaFiling",       lambda r: {"companyId": r.nat(), "filingId": r.nat(), "reason": r.text()}),
    288: ("issueCreditNote",        lambda r: {"facts": read_credit_note_facts(r)}),
    289: ("setIssuerProfile",       lambda r: {"facts": read_issuer_profile(r)}),
    290: ("setPartnerAddress",      lambda r: {"facts": read_partner_address(r)}),
    291: ("setCategoryTaxProfile",  lambda r: {"facts": read_category_tax_profile(r)}),
    292: ("prepareEtaCreditNote",   lambda r: {"facts": {"companyId": r.nat(), "creditNoteId": r.nat(), "version": r.text()}}),
    293: ("sealEtaFiling",          lambda r: {"facts": {"companyId": r.nat(), "filingId": r.nat(), "seal": r.blob()}}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_finance_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


# ── encoders ────────────────────────────────────────────────────────────────────

def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def write_texts(*ts):
    return b"".join(write_text(t) for t in ts)


ENCODERS = {
    "configureEtaEndpoint": (151, lambda c: write_nat(c["facts"]["companyId"]) + write_texts(
        c["facts"]["endpoint"], c["facts"]["issuerTaxId"], c["facts"]["issuerName"], c["facts"]["activityCode"], c["facts"]["keyHandle"])),
    "prepareEtaFiling": (152, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["orderId"])
                         + bytes([code_of(ETA_DOC_TYPE, c["facts"]["docType"], "document type")]) + write_text(c["facts"]["version"])),
    "recordEtaSubmission": (153, lambda c: write_nat(c["companyId"]) + write_nat(c["filingId"]) + write_blob(c["payloadHash"])),
    "recordEtaResult": (154, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["filingId"]) + write_blob(c["facts"]["payloadHash"])
                        + _bool(c["facts"]["accepted"]) + write_texts(c["facts"]["uuid"], c["facts"]["submissionId"], c["facts"]["longId"], c["facts"]["reason"])),
    "abandonEtaFiling": (155, lambda c: write_nat(c["companyId"]) + write_nat(c["filingId"]) + write_text(c["reason"])),
    "issueCreditNote": (288, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["orderId"]) + write_nat(c["facts"]["journalId"])
                        + write_text(c["facts"]["reason"]) + len(c["facts"]["lines"]).to_bytes(2, "big")
                        + b"".join(write_nat(l["ordinal"]) + write_nat(l["quantity"]) for l in c["facts"]["lines"])),
    "setIssuerProfile": (289, lambda c: write_nat(c["facts"]["companyId"]) + write_texts(
        c["facts"]["partyType"], c["facts"]["branchId"], c["facts"]["country"], c["facts"]["governate"], c["facts"]["regionCity"],
        c["facts"]["street"], c["facts"]["buildingNumber"], c["facts"]["postalCode"]) + write_blob(c["facts"]["anchorCertificate"])),
    "setPartnerAddress": (290, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["partnerId"]) + write_texts(
        c["facts"]["partyType"], c["facts"]["country"], c["facts"]["governate"], c["facts"]["regionCity"],
        c["facts"]["street"], c["facts"]["buildingNumber"], c["facts"]["postalCode"])),
    "setCategoryTaxProfile": (291, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["categoryId"]) + write_texts(
        c["facts"]["itemType"], c["facts"]["itemCode"], c["facts"]["unitType"], c["facts"]["taxType"], c["facts"]["taxSubType"])),
    "prepareEtaCreditNote": (292, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["creditNoteId"]) + write_text(c["facts"]["version"])),
    "sealEtaFiling": (293, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["filingId"]) + write_blob(c["facts"]["seal"])),
}


def finance_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)
