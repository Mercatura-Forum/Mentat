"""The website families (425 and 426), decoded from their canonical bytes, re-encoded so the command
hash can be re-derived, and folded by rules written from the design:

  * a PAGE is a company document the fold read whole from the evidence store and found to be its own
    plaintext - this reader reassembles the chunks the log carries, hashes them itself, and holds the
    declared fingerprint and the published fingerprint to that hash;
  * a publication is a VERSION at a path, at the block it was made; published again, a new version;
    unpublished, served no more with every version on record.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import hashlib

from canonical import write_nat, write_text

MAX_PAGE_BYTES = 262_144
MAX_CONTENT_TYPE = 128
MAX_PATH = 64
PATH_CHARS = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-")

READERS = {
    425: ("publishPage", lambda r: {"facts": {"companyId": r.nat(), "path": r.text(), "documentId": r.nat(), "contentType": r.text()}}),
    426: ("unpublishPage", lambda r: {"companyId": r.nat(), "pageId": r.nat(), "reason": r.text()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}

# the evidence families this reader watches for the bytes and the documents a page is made of
WATCHED = {"putChunk", "registerDocument", "archiveDocument", "eraseDocument"}


def read_site_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "publishPage": (425, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["path"]) + write_nat(c["facts"]["documentId"]) + write_text(c["facts"]["contentType"])),
    "unpublishPage": (426, lambda c: write_nat(c["companyId"]) + write_nat(c["pageId"]) + write_text(c["reason"])),
}


def site_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


def path_ok(path):
    if not path or not path.startswith("/") or len(path.encode("utf-8")) > MAX_PATH or any(ch not in PATH_CHARS for ch in path):
        return False
    if path == "/":
        return True
    return all(seg not in ("", ".", "..") for seg in path[1:].split("/"))


def content_type_ok(value):
    return 0 < len(value) <= MAX_CONTENT_TYPE and all(32 <= ord(ch) <= 126 and ch != '"' for ch in value)


class Site:
    def __init__(self):
        self.chunks = {}          # blobId -> {index: bytes}
        self.documents = {}       # id -> {companyId, blobId, plainHash, kind, state}
        self.next_document = 1
        self.pages = {}
        self.versions = {}
        self.next_page = 1
        self.next_version = 1
        self.fingerprints_recomputed = 0
        self.faults = []

    # -- what the evidence families say about bytes and documents --

    def note(self, block):
        c = block["command"]
        f = c["family"]
        if f == "putChunk":
            fc = c["facts"]
            self.chunks.setdefault(fc["blobId"], {})[fc["index"]] = fc["bytes"]
        elif f == "registerDocument":
            fc = c["facts"]
            self.documents[self.next_document] = {"companyId": fc["companyId"], "blobId": fc["blobId"], "plainHash": fc["plainHash"], "kind": fc["kind"], "state": "active"}
            self.next_document += 1
        elif f in ("archiveDocument", "eraseDocument"):
            d = self.documents.get(c["documentId"])
            if d is not None:
                d["state"] = "archived" if f == "archiveDocument" else "erased"

    def bytes_of(self, blob_id):
        parts = self.chunks.get(blob_id)
        if parts is None:
            return None
        return b"".join(parts[i] for i in sorted(parts))

    def page_by_path(self, company, path):
        for pid, p in self.pages.items():
            if p["companyId"] == company and p["path"] == path:
                return pid, p
        return None, None

    # -- the fold --

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]
        hr = store.hr

        if f == "publishPage":
            fc = c["facts"]
            co = fc["companyId"]
            d = self.documents.get(fc["documentId"])
            if (co not in store.companies or (co, caller) not in hr.members or not path_ok(fc["path"]) or not content_type_ok(fc["contentType"])
                    or d is None or d["companyId"] != co or d["kind"] != "company" or d["state"] != "active"):
                self.faults.append("block %d published a page it could not" % idx)
                return
            data = self.bytes_of(d["blobId"])
            if data is None:
                self.faults.append("block %d published a document whose bytes the log does not carry" % idx)
                return
            if len(data) > MAX_PAGE_BYTES:
                self.faults.append("block %d published a page beyond the bound" % idx)
                return
            digest = hashlib.sha256(data).hexdigest()
            if digest != d["plainHash"]:
                self.faults.append("block %d PUBLISHED A DOCUMENT THAT IS NOT ITS OWN PLAINTEXT" % idx)
                return
            pid, p = self.page_by_path(co, fc["path"])
            if p is None:
                pid = self.next_page
                self.pages[pid] = {"companyId": co, "path": fc["path"], "currentVersion": 0, "versions": 0, "isLive": True, "publishedBy": caller}
                self.next_page += 1
                p = self.pages[pid]
            p["versions"] += 1
            p.update({"currentVersion": p["versions"], "isLive": True, "publishedBy": caller})
            self.versions[self.next_version] = {"pageId": pid, "ordinal": p["versions"], "documentId": fc["documentId"], "contentType": fc["contentType"], "byteSize": len(data),
                                                "fingerprint": digest, "publishedBlock": idx, "publishedDay": day, "publishedBy": caller}
            self.next_version += 1
            return

        if f == "unpublishPage":
            p = self.pages.get(c["pageId"])
            if p is None or p["companyId"] != c["companyId"] or not p["isLive"] or (c["companyId"], caller) not in hr.members:
                self.faults.append("block %d unpublished a page it could not" % idx)
                return
            p["isLive"] = False
            return

    # -- what the contract prints, recomputed --

    def page_line(self, pid):
        """companyId path currentVersion versions live"""
        p = self.pages[pid]
        versions = sum(1 for v in self.versions.values() if v["pageId"] == pid)
        if versions != p["versions"]:
            self.faults.append("page %d counts %d versions; its rows come to %d" % (pid, p["versions"], versions))
        return (p["companyId"], p["path"], p["currentVersion"], p["versions"], 1 if p["isLive"] else 0)

    def version_line(self, vid):
        """pageId ordinal documentId byteSize fingerprint publishedBlock - the fingerprint recomputed from the chunks on the log"""
        v = self.versions[vid]
        d = self.documents.get(v["documentId"])
        data = self.bytes_of(d["blobId"]) if d is not None else None
        if data is None:
            self.faults.append("version %d names a document whose bytes the log does not carry" % vid)
        else:
            digest = hashlib.sha256(data).hexdigest()
            if digest != v["fingerprint"] or digest != d["plainHash"] or len(data) != v["byteSize"]:
                self.faults.append("version %d carries fingerprint %s; the chunks on the log hash to %s" % (vid, v["fingerprint"], digest))
            self.fingerprints_recomputed += 1
        return (v["pageId"], v["ordinal"], v["documentId"], v["byteSize"], v["fingerprint"], v["publishedBlock"])

    def summary(self):
        return {
            "pages": len(self.pages),
            "live": sum(1 for p in self.pages.values() if p["isLive"]),
            "versions": len(self.versions),
            "faults": len(self.faults),
        }
