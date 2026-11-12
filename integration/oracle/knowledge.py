"""The knowledge families (569 to 574), decoded from their canonical bytes, re-encoded so the command hash can be
re-derived, and folded by rules written from the design:

  * AN ARTICLE IS ITS VERSIONS, each a DOCUMENT IN THE EVIDENCE STORE - the company's, under its ring (a company
    document), still active, registered by the author, and the words of no other version - with a title, a
    category and at most four tags, each normalised, at most sixteen bytes and named once; the first version
    opens the article as a draft, any member writes the next, and an archived article takes no more;
  * A VERSION IS PUBLISHED BY SOMEBODY WHO DID NOT WRITE IT, its document still active - the latest or an earlier
    one brought back - and the article then carries that version's category and tags; a draft takes a new
    version's at once, a published article keeps its own until a second person publishes the new one;
  * an article ARCHIVED by a member stands for no reader and comes back only by being published again;
  * a VIEW is a member's, once, of a published article, with the version read; a VOTE is a member's, never the
    published version's author's, one per member and moved when they change their mind - this reader re-adds
    every article's views and both sides of its votes from the rows it folded, and re-reads every published
    article's category and tags from the version it names.

The documents are watched here from the evidence families on their way to the evidence reader: a registration
by its caller, of a kind, active until it is archived or erased. The memberships are the discussion reader's.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text

CATEGORIES = {1: "finance", 2: "general", 3: "hr", 4: "it", 5: "legal", 6: "operations", 7: "product"}
STATES = {1: "archived", 2: "draft", 3: "published"}
STATE_BYTE = {v: k for k, v in STATES.items()}
DOCUMENT_COMPANY = "company"
MAX_TAGS = 4
TAG_BYTES = 16
MAX_TEXT = 4_000


def write_bool(b):
    return b"\x01" if b else b"\x00"


def write_len16(n):
    return n.to_bytes(2, "big")


def read_list(r, fn):
    return [fn() for _ in range(r.len16())]


def read_version(r):
    return {"companyId": r.nat(), "title": r.text(), "category": r.nat8(), "tags": read_list(r, r.text), "documentId": r.nat()}


def write_version(f):
    return (write_nat(f["companyId"]) + write_text(f["title"]) + bytes([f["category"]])
            + write_len16(len(f["tags"])) + b"".join(write_text(t) for t in f["tags"]) + write_nat(f["documentId"]))


READERS = {
    569: ("createKbArticle", lambda r: {"facts": read_version(r)}),
    570: ("reviseKbArticle", lambda r: {"articleId": r.nat(), "facts": read_version(r)}),
    571: ("publishKbVersion", lambda r: {"companyId": r.nat(), "articleId": r.nat(), "number": r.nat()}),
    572: ("archiveKbArticle", lambda r: {"companyId": r.nat(), "articleId": r.nat()}),
    573: ("recordKbView", lambda r: {"companyId": r.nat(), "articleId": r.nat()}),
    574: ("voteKbArticle", lambda r: {"companyId": r.nat(), "articleId": r.nat(), "isHelpful": r.bool()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}

# the evidence families whose documents a version is held to
WATCHED = {"registerDocument", "archiveDocument", "eraseDocument"}


def read_knowledge_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "createKbArticle": (569, lambda c: write_version(c["facts"])),
    "reviseKbArticle": (570, lambda c: write_nat(c["articleId"]) + write_version(c["facts"])),
    "publishKbVersion": (571, lambda c: write_nat(c["companyId"]) + write_nat(c["articleId"]) + write_nat(c["number"])),
    "archiveKbArticle": (572, lambda c: write_nat(c["companyId"]) + write_nat(c["articleId"])),
    "recordKbView": (573, lambda c: write_nat(c["companyId"]) + write_nat(c["articleId"])),
    "voteKbArticle": (574, lambda c: write_nat(c["companyId"]) + write_nat(c["articleId"]) + write_bool(c["isHelpful"])),
}


def knowledge_command_bytes(cmd):
    tag, enc = ENCODERS[cmd["family"]]
    return put_tag(tag) + enc(cmd)


def normalise(name):
    """Lower-case ASCII only and trim spaces, tabs and line ends - the contract's rule, restated."""
    lowered = "".join(chr(ord(ch) + 32) if "A" <= ch <= "Z" else ch for ch in name)
    return lowered.strip(" \t\n\r")


def tags_of(tags):
    """The tags as the contract keeps them, or None where it refuses them: at most four, each normalised, a word,
    at most sixteen bytes with no NUL (a field read back must be the tag written), named once."""
    if len(tags) > MAX_TAGS:
        return None
    out = []
    for t in tags:
        n = normalise(t)
        b = n.encode("utf-8")
        if not n or len(b) > TAG_BYTES or b"\x00" in b or n in out:
            return None
        out.append(n)
    return out


class Knowledge:
    def __init__(self):
        self.documents = {}       # document id -> {companyId, kind, active, uploadedBy}
        self.next_document = 1
        self.articles = {}
        self.versions = {}        # version id -> row
        self.version_of = {}      # (articleId, number) -> version id
        self.version_of_document = {}
        self.views = {}
        self.view_of = {}         # (articleId, principal) -> view id
        self.votes = {}
        self.vote_of = {}
        self.next_article = 1
        self.next_version = 1
        self.next_view = 1
        self.next_vote = 1
        self.counts_readded = 0
        self.published_reread = 0
        self.faults = []

    def observe(self, block):
        c = block["command"]
        f = c["family"]
        if f == "registerDocument":
            self.documents[self.next_document] = {"companyId": c["facts"]["companyId"], "kind": c["facts"]["kind"], "active": True,
                                                  "uploadedBy": bytes(block["caller"])}
            self.next_document += 1
        elif f in ("archiveDocument", "eraseDocument"):
            d = self.documents.get(c["documentId"])
            if d is not None:
                d["active"] = False

    def document_ok(self, co, doc_id, caller):
        d = self.documents.get(doc_id)
        return (d is not None and d["companyId"] == co and d["kind"] == DOCUMENT_COMPANY and d["active"]
                and d["uploadedBy"] == caller and doc_id not in self.version_of_document)

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = bytes(block["caller"])

        def fault(what):
            self.faults.append("block %d %s" % (idx, what))

        def member(co):
            return co in store.companies and store.discuss.is_member(co, caller)

        def article(co, aid):
            a = self.articles.get(aid)
            return a if a is not None and a["companyId"] == co and member(co) else None

        def version_ok(fc):
            return (bool(fc["title"]) and len(fc["title"]) <= MAX_TEXT and fc["category"] in CATEGORIES
                    and tags_of(fc["tags"]) is not None and self.document_ok(fc["companyId"], fc["documentId"], caller))

        def write_version(aid, number, fc):
            vid = self.next_version
            self.next_version += 1
            self.versions[vid] = {"companyId": fc["companyId"], "articleId": aid, "number": number, "documentId": fc["documentId"],
                                  "category": fc["category"], "tags": tags_of(fc["tags"]), "author": caller, "day": day}
            self.version_of[(aid, number)] = vid
            self.version_of_document[fc["documentId"]] = vid

        if f == "createKbArticle":
            fc = c["facts"]
            if not member(fc["companyId"]) or not version_ok(fc):
                fault("opened an article it could not")
                return
            aid = self.next_article
            self.next_article += 1
            self.articles[aid] = {"companyId": fc["companyId"], "category": fc["category"], "tags": tags_of(fc["tags"]), "state": "draft",
                                  "createdBy": caller, "versions": 1, "publishedVersion": 0, "publishedDay": 0,
                                  "views": 0, "helpful": 0, "notHelpful": 0}
            write_version(aid, 1, fc)
            return

        if f == "reviseKbArticle":
            fc = c["facts"]
            a = article(fc["companyId"], c["articleId"])
            if a is None or a["state"] == "archived" or not version_ok(fc):
                fault("revised an article it could not")
                return
            a["versions"] += 1
            write_version(c["articleId"], a["versions"], fc)
            if a["state"] == "draft":
                a["category"] = fc["category"]
                a["tags"] = tags_of(fc["tags"])
            return

        if f == "publishKbVersion":
            a = article(c["companyId"], c["articleId"])
            vid = self.version_of.get((c["articleId"], c["number"]))
            if a is None or vid is None:
                fault("published a version that is not there")
                return
            v = self.versions[vid]
            d = self.documents.get(v["documentId"])
            if ((a["state"] == "published" and a["publishedVersion"] == c["number"]) or v["author"] == caller
                    or d is None or not d["active"]):
                fault("published a version it could not")
                return
            a.update(state="published", publishedVersion=c["number"], publishedDay=day, category=v["category"], tags=list(v["tags"]))
            return

        if f == "archiveKbArticle":
            a = article(c["companyId"], c["articleId"])
            if a is None or a["state"] == "archived":
                fault("archived an article it could not")
                return
            a["state"] = "archived"
            return

        if f == "recordKbView":
            a = article(c["companyId"], c["articleId"])
            if a is None or a["state"] != "published" or (c["articleId"], caller) in self.view_of:
                fault("recorded a view it could not")
                return
            vid = self.next_view
            self.next_view += 1
            self.views[vid] = {"companyId": c["companyId"], "articleId": c["articleId"], "viewer": caller, "version": a["publishedVersion"], "day": day}
            self.view_of[(c["articleId"], caller)] = vid
            a["views"] += 1
            return

        if f == "voteKbArticle":
            a = article(c["companyId"], c["articleId"])
            if a is None or a["state"] != "published":
                fault("voted on an article that is not published")
                return
            pv = self.versions[self.version_of[(c["articleId"], a["publishedVersion"])]]
            if pv["author"] == caller:
                fault("let the published version's author vote on it")
                return
            key = (c["articleId"], caller)
            if key in self.vote_of:
                x = self.votes[self.vote_of[key]]
                if x["isHelpful"] == c["isHelpful"]:
                    fault("took the same vote twice")
                    return
                x["isHelpful"] = c["isHelpful"]
                if c["isHelpful"]:
                    a["helpful"] += 1
                    a["notHelpful"] -= 1
                else:
                    a["helpful"] -= 1
                    a["notHelpful"] += 1
                return
            vid = self.next_vote
            self.next_vote += 1
            self.votes[vid] = {"companyId": c["companyId"], "articleId": c["articleId"], "voter": caller, "isHelpful": c["isHelpful"]}
            self.vote_of[key] = vid
            if c["isHelpful"]:
                a["helpful"] += 1
            else:
                a["notHelpful"] += 1
            return

    # -- what the contract prints, recomputed --

    def article_line(self, aid):
        """companyId category state versions publishedVersion views helpful notHelpful tagCount - the counts
        re-added from the rows, a published article's category and tags re-read from the version it names"""
        a = self.articles[aid]
        self.counts_readded += 1
        views = sum(1 for v in self.views.values() if v["articleId"] == aid)
        helpful = sum(1 for v in self.votes.values() if v["articleId"] == aid and v["isHelpful"])
        not_helpful = sum(1 for v in self.votes.values() if v["articleId"] == aid and not v["isHelpful"])
        category, tags = a["category"], a["tags"]
        if a["publishedVersion"] != 0 and a["state"] != "draft":
            self.published_reread += 1
            pv = self.versions[self.version_of[(aid, a["publishedVersion"])]]
            if (pv["category"], pv["tags"]) != (category, tags):
                self.faults.append("article %d carries a category or tags other than its published version's" % aid)
            category, tags = pv["category"], pv["tags"]
        return (a["companyId"], category, STATE_BYTE[a["state"]], a["versions"], a["publishedVersion"], views, helpful, not_helpful, len(tags))

    def version_line(self, vid, store):
        v = self.versions[vid]
        return (v["articleId"], v["number"], v["documentId"], v["category"], len(v["tags"]), store.discuss.membership_id(v["companyId"], v["author"]), v["day"])

    def view_line(self, vid, store):
        v = self.views[vid]
        return (v["articleId"], store.discuss.membership_id(v["companyId"], v["viewer"]), v["version"], v["day"])

    def vote_line(self, vid, store):
        v = self.votes[vid]
        return (v["articleId"], store.discuss.membership_id(v["companyId"], v["voter"]), 1 if v["isHelpful"] else 0)

    def summary(self):
        return {"articles": len(self.articles), "versions": len(self.versions), "views": len(self.views), "votes": len(self.votes),
                "published": sum(1 for a in self.articles.values() if a["state"] == "published"), "faults": len(self.faults)}
