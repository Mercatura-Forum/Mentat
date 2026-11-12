"""The blog families (427 to 429), decoded from their canonical bytes, re-encoded so the command hash can
be re-derived, and folded by rules written from the design:

  * a POST is a company document the fold found to be its own plaintext - this reader reassembles the
    chunks from the log (through the website reader's notes) and hashes them itself - at a slug of
    lower-case letters, digits and hyphens;
  * THE AUTHOR IS THE CALLER and THE DATE IS THE DAY OF THE BLOCK: this reader writes both from the
    block and holds the contract's figures to them;
  * revised, a further revision under the same slug with the first day kept; withdrawn, served no more;
    published again under its slug, standing again.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import hashlib

from canonical import write_nat, write_text

MAX_SLUG = 64
SLUG_CHARS = set("abcdefghijklmnopqrstuvwxyz0123456789-")

READERS = {
    427: ("publishPost", lambda r: {"facts": {"companyId": r.nat(), "slug": r.text(), "title": r.text(), "documentId": r.nat(), "contentType": r.text()}}),
    428: ("revisePost", lambda r: {"facts": {"companyId": r.nat(), "postId": r.nat(), "documentId": r.nat(), "contentType": r.text()}}),
    429: ("withdrawPost", lambda r: {"companyId": r.nat(), "postId": r.nat(), "reason": r.text()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_blog_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "publishPost": (427, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["slug"]) + write_text(c["facts"]["title"]) + write_nat(c["facts"]["documentId"]) + write_text(c["facts"]["contentType"])),
    "revisePost": (428, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["postId"]) + write_nat(c["facts"]["documentId"]) + write_text(c["facts"]["contentType"])),
    "withdrawPost": (429, lambda c: write_nat(c["companyId"]) + write_nat(c["postId"]) + write_text(c["reason"])),
}


def blog_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


def slug_ok(slug):
    return 0 < len(slug.encode("utf-8")) <= MAX_SLUG and all(ch in SLUG_CHARS for ch in slug) and not slug.startswith("-") and not slug.endswith("-")


def content_type_ok(value):
    return 0 < len(value) <= 128 and all(32 <= ord(ch) <= 126 and ch != '"' for ch in value)


class Blog:
    def __init__(self):
        self.posts = {}
        self.next_post = 1
        self.dates_held = 0
        self.faults = []

    def post_by_slug(self, company, slug):
        for pid, p in self.posts.items():
            if p["companyId"] == company and p["slug"] == slug:
                return pid, p
        return None, None

    def _verified(self, store, company, document_id, content_type):
        """The document's bytes, found to be its own plaintext as the website requires; None if not."""
        d = store.site.documents.get(document_id)
        if d is None or d["companyId"] != company or d["kind"] != "company" or d["state"] != "active" or not content_type_ok(content_type):
            return None
        data = store.site.bytes_of(d["blobId"])
        if data is None or len(data) > 262_144:
            return None
        digest = hashlib.sha256(data).hexdigest()
        if digest != d["plainHash"]:
            return None
        return len(data), digest

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]
        hr = store.hr

        if f == "publishPost":
            fc = c["facts"]
            co = fc["companyId"]
            if co not in store.companies or (co, caller) not in hr.members or not slug_ok(fc["slug"]) or not fc["title"]:
                self.faults.append("block %d published a post it could not" % idx)
                return
            pid, p = self.post_by_slug(co, fc["slug"])
            if p is not None and p["isLive"]:
                self.faults.append("block %d PUBLISHED UNDER A SLUG A LIVE POST HOLDS" % idx)
                return
            v = self._verified(store, co, fc["documentId"], fc["contentType"])
            if v is None:
                self.faults.append("block %d PUBLISHED A DOCUMENT THAT IS NOT ITS OWN PLAINTEXT, or not a company's" % idx)
                return
            size, digest = v
            if p is not None:
                p.update({"title": fc["title"], "revisedDay": day, "revision": p["revision"] + 1, "documentId": fc["documentId"], "contentType": fc["contentType"], "byteSize": size, "fingerprint": digest, "isLive": True})
                return
            self.posts[self.next_post] = {"companyId": co, "slug": fc["slug"], "title": fc["title"], "author": caller, "publishedDay": day, "publishedBlock": idx, "revisedDay": day, "revision": 1,
                                          "documentId": fc["documentId"], "contentType": fc["contentType"], "byteSize": size, "fingerprint": digest, "isLive": True}
            self.next_post += 1
            return

        if f == "revisePost":
            fc = c["facts"]
            co = fc["companyId"]
            p = self.posts.get(fc["postId"])
            if p is None or p["companyId"] != co or (co, caller) not in hr.members or not p["isLive"]:
                self.faults.append("block %d revised a post it could not" % idx)
                return
            v = self._verified(store, co, fc["documentId"], fc["contentType"])
            if v is None:
                self.faults.append("block %d REVISED WITH A DOCUMENT THAT IS NOT ITS OWN PLAINTEXT" % idx)
                return
            size, digest = v
            p.update({"revisedDay": day, "revision": p["revision"] + 1, "documentId": fc["documentId"], "contentType": fc["contentType"], "byteSize": size, "fingerprint": digest})
            return

        if f == "withdrawPost":
            co = c["companyId"]
            p = self.posts.get(c["postId"])
            if p is None or p["companyId"] != co or (co, caller) not in hr.members or not p["isLive"]:
                self.faults.append("block %d withdrew a post it could not" % idx)
                return
            p["isLive"] = False
            return

    # -- what the contract prints, recomputed --

    def post_line(self, pid, store):
        """companyId slug publishedDay publishedBlock revisedDay revision documentId byteSize fingerprint live - 
        the day held to the day of the block it was published at, the fingerprint recomputed from the chunks on the log"""
        p = self.posts[pid]
        d = store.site.documents.get(p["documentId"])
        data = store.site.bytes_of(d["blobId"]) if d is not None else None
        if data is None or hashlib.sha256(data).hexdigest() != p["fingerprint"] or len(data) != p["byteSize"]:
            self.faults.append("post %d carries a fingerprint the chunks on the log do not hash to" % pid)
        self.dates_held += 1
        return (p["companyId"], p["slug"], p["publishedDay"], p["publishedBlock"], p["revisedDay"], p["revision"], p["documentId"], p["byteSize"], p["fingerprint"], 1 if p["isLive"] else 0)

    def summary(self):
        return {
            "posts": len(self.posts),
            "live": sum(1 for p in self.posts.values() if p["isLive"]),
            "revisions": sum(p["revision"] for p in self.posts.values()),
            "faults": len(self.faults),
        }
