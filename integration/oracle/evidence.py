#!/usr/bin/env python3
"""The evidence and signing families, decoded from their canonical bytes, and the two signing
families this extension added re-encoded - written from the specification in `src/Encoding.mo`,
not read off it.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text

SIG_SCHEME = {1: "es256", 2: "mlDsa44", 3: "mayo2"}
DOCUMENT_KIND = {1: "company", 2: "employee", 3: "attachment", 4: "logo", 5: "signatureContent"}
DOCUMENT_CATEGORY = {1: "contract", 2: "policy", 3: "report", 4: "medical", 5: "personal", 6: "identity", 7: "payroll", 8: "certificate", 9: "other"}
EMPLOYEE_DOC_TYPE = {1: "none", 2: "passport", 3: "visa", 4: "workPermit", 5: "nationalId", 6: "drivingLicence", 7: "medicalCertificate", 8: "qualification", 9: "other"}
SIGNATURE_DOC_TYPE = {1: "contract", 2: "policy", 3: "acknowledgement", 4: "offer", 5: "consent", 6: "other"}


def named(table, b, what):
    if b not in table:
        raise ValueError("a %s byte nobody assigned: %d" % (what, b))
    return table[b]


def read_texts(r):
    return [r.text() for _ in range(r.len16())]


def read_wraps(r):
    return [(r.nat(), r.text()) for _ in range(r.len16())]


def read_principals(r):
    return [r.principal() for _ in range(r.len16())]


def read_document(r):
    return {"companyId": r.nat(), "blobId": r.text(), "plainHash": r.text(), "plainSize": r.nat(),
            "kind": named(DOCUMENT_KIND, r.nat8(), "document kind"), "category": named(DOCUMENT_CATEGORY, r.nat8(), "document category"),
            "docType": named(EMPLOYEE_DOC_TYPE, r.nat8(), "document type"),
            "title": r.text(), "description": r.text(), "mime": r.text(), "name": r.text(),
            "subject": r.principal(), "taskId": r.nat(), "expiryDay": r.nat(), "reminderDays": r.nat(),
            "isTemplate": r.bool(), "wrappedFileKey": r.text()}


def read_request(r):
    return {"companyId": r.nat(), "title": r.text(), "description": r.text(),
            "docType": named(SIGNATURE_DOC_TYPE, r.nat8(), "signature document type"),
            "documentId": r.nat(), "deadlineDay": r.nat(), "mandatory": r.bool()}


READERS = {
    113: ("registerDevice", lambda r: {"companyId": r.nat(), "spki": r.text(), "note": r.text()}),
    114: ("revokeDevice", lambda r: {"companyId": r.nat(), "deviceId": r.nat(), "isAdmin": r.bool(), "reason": r.text()}),
    115: ("openRing", lambda r: {"companyId": r.nat(), "personal": r.bool(), "subject": r.principal()}),
    116: ("rotateRing", lambda r: {"companyId": r.nat(), "personal": r.bool(), "subject": r.principal(), "expect": r.nat(),
                                    "wraps": read_wraps(r), "byDevice": r.nat()}),
    117: ("shareRing", lambda r: {"companyId": r.nat(), "personal": r.bool(), "subject": r.principal(), "epoch": r.nat(),
                                   "wraps": read_wraps(r), "byDevice": r.nat()}),
    118: ("beginUpload", lambda r: {"companyId": r.nat(), "facts": {"size": r.nat(), "chunkHashes": read_texts(r)}}),
    119: ("putChunk", lambda r: {"facts": {"blobId": r.text(), "index": r.nat(), "bytes": r.blob()}}),
    120: ("sealUpload", lambda r: {"blobId": r.text()}),
    121: ("abortUpload", lambda r: {"blobId": r.text()}),
    122: ("registerDocument", lambda r: {"facts": read_document(r)}),
    123: ("amendDocument", lambda r: {"companyId": r.nat(), "documentId": r.nat(), "title": r.text(), "description": r.text(),
                                       "expiryDay": r.nat(), "reminderDays": r.nat()}),
    124: ("archiveDocument", lambda r: {"companyId": r.nat(), "documentId": r.nat(), "reason": r.text()}),
    125: ("eraseDocument", lambda r: {"companyId": r.nat(), "documentId": r.nat(), "reason": r.text()}),
    126: ("openDocumentExpirySweep", lambda r: {"companyId": r.nat(), "throughDay": r.nat(), "planHash": r.blob()}),
    127: ("sweepDocumentExpirySlice", lambda r: {"companyId": r.nat(), "runId": r.nat(), "planHash": r.blob(), "limit": r.nat()}),
    128: ("registerSigningKey", lambda r: {"companyId": r.nat(), "scheme": named(SIG_SCHEME, r.nat8(), "signing scheme"),
                                            "credentialId": r.text(), "publicKey": r.text(), "context": r.text(), "note": r.text()}),
    129: ("revokeSigningKey", lambda r: {"companyId": r.nat(), "keyId": r.nat(), "reason": r.text()}),
    130: ("createSignatureRequest", lambda r: {"facts": read_request(r)}),
    131: ("revokeSignatureRequest", lambda r: {"companyId": r.nat(), "requestId": r.nat(), "reason": r.text()}),
    132: ("beginSignature", lambda r: {"companyId": r.nat(), "requestId": r.nat()}),
    133: ("completeSignature", lambda r: {"facts": {"companyId": r.nat(), "requestId": r.nat(), "nonce": r.text(), "credentialId": r.text(),
                                                     "clientDataB64": r.text(), "authDataB64": r.text(), "signatureB64": r.text()}}),
    134: ("completeSignaturePq", lambda r: {"facts": {"companyId": r.nat(), "requestId": r.nat(), "nonce": r.text(), "keyId": r.nat(),
                                                       "signatureB64": r.text()}}),
    135: ("declineSignature", lambda r: {"companyId": r.nat(), "requestId": r.nat(), "reason": r.text()}),
    294: ("nameSigners", lambda r: {"companyId": r.nat(), "requestId": r.nat(), "signers": read_principals(r)}),
    295: ("expireSignatureRequest", lambda r: {"companyId": r.nat(), "requestId": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_evidence_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


# ── encoders, for the two families this extension added ───────────────────────────

def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def write_principal(p: bytes) -> bytes:
    return bytes([len(p)]) + p


def write_principals(ps) -> bytes:
    return len(ps).to_bytes(2, "big") + b"".join(write_principal(p) for p in ps)


ENCODERS = {
    "nameSigners": (294, lambda c: write_nat(c["companyId"]) + write_nat(c["requestId"]) + write_principals(c["signers"])),
    "expireSignatureRequest": (295, lambda c: write_nat(c["companyId"]) + write_nat(c["requestId"])),
}


def evidence_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)
