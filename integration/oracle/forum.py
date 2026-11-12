"""The forum families (430 to 433, and the ideas 628 to 630), decoded from their canonical bytes, re-encoded so the command hash can
be re-derived, and folded by rules written from the design:

  * a BOARD is declared at a slug (the blog's slug rule) by a member; declared again, its title changes;
  * a TOPIC and a REPLY are a member's word: THE AUTHOR IS THE CALLER and THE DAY IS THE DAY OF THE BLOCK - 
    this reader writes both from the block and holds the contract's figures to them; a word once said
    stands; a locked or a hidden topic takes no reply;
  * a MODERATION IS A RECORDED ACT by A MEMBER WHO IS NOT THE AUTHOR of the word moderated, refused when
    it would change nothing - this reader holds every moderation to a second person;
  * every topic's count of replies and its latest word are RECOUNTED here from the replies on the log;
  * an IDEA is a topic on a board marked for ideas, not hidden: a mark that changes nothing is refused; a vote is
    ONE PER MEMBER AND IDEA, NEVER THE AUTHOR'S, a first vote up and a later one only a change; a decision is
    NEVER THE AUTHOR'S, MOVES FORWARD ONLY (submitted → under review, approved or rejected; under review → approved
    or rejected; approved → implemented), and a rejection or an implementation says why.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text
from blog import slug_ok

TARGETS = {1: "topic", 2: "reply"}
ACTS = {1: "hide", 2: "restore", 3: "lock", 4: "unlock", 5: "pin", 6: "unpin"}
TARGET_BYTES = {v: k for k, v in TARGETS.items()}
ACT_BYTES = {v: k for k, v in ACTS.items()}
IDEA_STATUSES = {1: "submitted", 2: "underReview", 3: "approved", 4: "implemented", 5: "rejected"}
IDEA_STATUS_BYTES = {v: k for k, v in IDEA_STATUSES.items()}
MOVES = {"submitted": {"underReview", "approved", "rejected"}, "underReview": {"approved", "rejected"}, "approved": {"implemented"}}

READERS = {
    430: ("declareBoard", lambda r: {"facts": {"companyId": r.nat(), "slug": r.text(), "title": r.text(), "description": r.text()}}),
    431: ("openTopic", lambda r: {"facts": {"companyId": r.nat(), "boardId": r.nat(), "title": r.text(), "body": r.text()}}),
    432: ("replyToTopic", lambda r: {"facts": {"companyId": r.nat(), "topicId": r.nat(), "body": r.text()}}),
    433: ("moderate", lambda r: {"facts": {"companyId": r.nat(), "target": TARGETS[r.nat8()], "targetId": r.nat(), "act": ACTS[r.nat8()], "reason": r.text()}}),
    628: ("markIdeaBoard", lambda r: {"facts": {"companyId": r.nat(), "boardId": r.nat(), "isIdeas": r.bool()}}),
    629: ("voteTopic", lambda r: {"facts": {"companyId": r.nat(), "topicId": r.nat(), "isUp": r.bool()}}),
    630: ("setIdeaStatus", lambda r: {"facts": {"companyId": r.nat(), "topicId": r.nat(), "status": IDEA_STATUSES[r.nat8()], "note": r.text()}}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_forum_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "declareBoard": (430, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["slug"]) + write_text(c["facts"]["title"]) + write_text(c["facts"]["description"])),
    "openTopic": (431, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["boardId"]) + write_text(c["facts"]["title"]) + write_text(c["facts"]["body"])),
    "replyToTopic": (432, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["topicId"]) + write_text(c["facts"]["body"])),
    "moderate": (433, lambda c: write_nat(c["facts"]["companyId"]) + bytes([TARGET_BYTES[c["facts"]["target"]]]) + write_nat(c["facts"]["targetId"]) + bytes([ACT_BYTES[c["facts"]["act"]]]) + write_text(c["facts"]["reason"])),
    "markIdeaBoard": (628, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["boardId"]) + bytes([1 if c["facts"]["isIdeas"] else 0])),
    "voteTopic": (629, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["topicId"]) + bytes([1 if c["facts"]["isUp"] else 0])),
    "setIdeaStatus": (630, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["topicId"]) + bytes([IDEA_STATUS_BYTES[c["facts"]["status"]]]) + write_text(c["facts"]["note"])),
}


def forum_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


# what each act sets, and on which flag
FLAG_OF = {"hide": ("isHidden", True), "restore": ("isHidden", False), "lock": ("isLocked", True), "unlock": ("isLocked", False), "pin": ("isPinned", True), "unpin": ("isPinned", False)}
TOPIC_ONLY = {"lock", "unlock", "pin", "unpin"}


class Forum:
    def __init__(self):
        self.boards = {}
        self.topics = {}
        self.replies = {}
        self.moderations = {}
        self.next_board = 1
        self.next_topic = 1
        self.next_reply = 1
        self.next_moderation = 1
        self.idea_boards = {}
        self.idea_statuses = {}
        self.votes = {}
        self.next_vote = 1
        self.idea_acts_held = 0
        self.reply_counts_recomputed = 0
        self.four_eyes_held = 0
        self.faults = []

    def board_by_slug(self, company, slug):
        for bid, b in self.boards.items():
            if b["companyId"] == company and b["slug"] == slug:
                return bid, b
        return None, None

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]
        hr = store.hr
        fc = c["facts"]
        co = fc["companyId"]

        if f == "declareBoard":
            if co not in store.companies or (co, caller) not in hr.members or not slug_ok(fc["slug"]) or not fc["title"]:
                self.faults.append("block %d declared a board it could not" % idx)
                return
            bid, b = self.board_by_slug(co, fc["slug"])
            if b is not None:
                b.update({"title": fc["title"], "description": fc["description"]})
                return
            self.boards[self.next_board] = {"companyId": co, "slug": fc["slug"], "title": fc["title"], "description": fc["description"], "topics": 0, "declaredBy": caller}
            self.next_board += 1
            return

        if f == "openTopic":
            b = self.boards.get(fc["boardId"])
            if b is None or b["companyId"] != co or (co, caller) not in hr.members or not fc["title"] or not fc["body"]:
                self.faults.append("block %d opened a topic it could not" % idx)
                return
            self.topics[self.next_topic] = {"companyId": co, "boardId": fc["boardId"], "title": fc["title"], "body": fc["body"], "author": caller,
                                            "openedDay": day, "openedBlock": idx, "lastDay": day, "activityBlock": idx, "replies": 0,
                                            "isLocked": False, "isPinned": False, "isHidden": False}
            self.next_topic += 1
            b["topics"] += 1
            return

        if f == "replyToTopic":
            t = self.topics.get(fc["topicId"])
            if t is None or t["companyId"] != co or (co, caller) not in hr.members or not fc["body"]:
                self.faults.append("block %d replied where it could not" % idx)
                return
            if t["isHidden"] or t["isLocked"]:
                self.faults.append("block %d REPLIED ON A TOPIC THAT IS %s" % (idx, "HIDDEN" if t["isHidden"] else "LOCKED"))
                return
            self.replies[self.next_reply] = {"companyId": co, "topicId": fc["topicId"], "author": caller, "body": fc["body"], "day": day, "block": idx, "isHidden": False}
            self.next_reply += 1
            t.update({"replies": t["replies"] + 1, "lastDay": day, "activityBlock": idx})
            return

        if f == "moderate":
            if co not in store.companies or (co, caller) not in hr.members or not fc["reason"]:
                self.faults.append("block %d moderated where it could not" % idx)
                return
            target = fc["target"]
            row = (self.topics if target == "topic" else self.replies).get(fc["targetId"])
            if row is None or row["companyId"] != co:
                self.faults.append("block %d moderated a %s that is not there" % (idx, target))
                return
            if row["author"] == caller:
                self.faults.append("block %d MODERATED ITS OWN WORD" % idx)
                return
            act = fc["act"]
            if target == "reply" and act in TOPIC_ONLY:
                self.faults.append("block %d %sed a reply" % (idx, act))
                return
            flag, value = FLAG_OF[act]
            if row[flag] == value:
                self.faults.append("block %d RECORDED AN ACT THAT CHANGED NOTHING" % idx)
                return
            self.moderations[self.next_moderation] = {"companyId": co, "target": target, "targetId": fc["targetId"], "act": act, "moderator": caller, "author": row["author"], "reason": fc["reason"], "day": day, "block": idx}
            self.next_moderation += 1
            row[flag] = value
            return

        if f in ("markIdeaBoard", "voteTopic", "setIdeaStatus"):
            self.apply_idea(f, fc, co, caller, day, idx, store)

    def is_idea_board(self, bid):
        return self.idea_boards.get(bid, {}).get("isIdeas", False)

    def apply_idea(self, f, fc, co, caller, day, idx, store):
        if co not in store.companies or (co, caller) not in store.hr.members:
            self.faults.append("block %d acted on an idea where it could not" % idx)
            return
        if f == "markIdeaBoard":
            b = self.boards.get(fc["boardId"])
            if b is None or b["companyId"] != co:
                self.faults.append("block %d marked a board that is not there" % idx)
                return
            if self.is_idea_board(fc["boardId"]) == fc["isIdeas"]:
                self.faults.append("block %d MARKED A BOARD AS IT WAS" % idx)
                return
            self.idea_boards[fc["boardId"]] = {"companyId": co, "isIdeas": fc["isIdeas"], "markedBy": caller, "day": day, "lastBlock": idx}
            self.idea_acts_held += 1
            return
        t = self.topics.get(fc["topicId"])
        if t is None or t["companyId"] != co or not self.is_idea_board(t["boardId"]) or t["isHidden"]:
            self.faults.append("block %d acted on topic %d, which is no idea" % (idx, fc["topicId"]))
            return
        if t["author"] == caller:
            self.faults.append("block %d: THE AUTHOR OF IDEA %d %s IT" % (idx, fc["topicId"], "VOTED ON" if f == "voteTopic" else "DECIDED"))
            return
        if f == "setIdeaStatus":
            now = self.idea_statuses.get(fc["topicId"], {}).get("status", "submitted")
            if fc["status"] not in MOVES.get(now, set()):
                self.faults.append("block %d MOVED IDEA %d FROM %s TO %s" % (idx, fc["topicId"], now, fc["status"]))
                return
            if fc["status"] in ("rejected", "implemented") and not fc["note"]:
                self.faults.append("block %d decided idea %d %s without saying why" % (idx, fc["topicId"], fc["status"]))
                return
            self.idea_statuses[fc["topicId"]] = {"companyId": co, "status": fc["status"], "note": fc["note"], "decidedBy": caller, "day": day, "lastBlock": idx}
            self.idea_acts_held += 1
            return
        mine = [vid for vid, v in self.votes.items() if v["topicId"] == fc["topicId"] and v["voter"] == caller]
        if len(mine) > 1:
            self.faults.append("idea %d holds %d votes of one member" % (fc["topicId"], len(mine)))
            return
        if mine:
            v = self.votes[mine[0]]
            if v["isUp"] == fc["isUp"]:
                self.faults.append("block %d VOTED AS THE VOTE STOOD" % idx)
                return
            v.update({"isUp": fc["isUp"], "lastBlock": idx})
        else:
            if not fc["isUp"]:
                self.faults.append("block %d took back a vote never cast" % idx)
                return
            self.votes[self.next_vote] = {"companyId": co, "topicId": fc["topicId"], "voter": caller, "isUp": True, "lastBlock": idx}
            self.next_vote += 1
        self.idea_acts_held += 1

    def up_votes(self, tid):
        return sum(1 for v in self.votes.values() if v["topicId"] == tid and v["isUp"])

    # -- what the contract prints, recomputed --

    def board_line(self, bid):
        """companyId slug topics - the count recounted from the topics on the log"""
        b = self.boards[bid]
        return (b["companyId"], b["slug"], sum(1 for t in self.topics.values() if t["boardId"] == bid))

    def topic_line(self, tid):
        """companyId boardId openedDay openedBlock lastDay activityBlock replies locked pinned hidden - the day held to the
        block's, the replies RECOUNTED from the replies on the log and the latest word recomputed from them"""
        t = self.topics[tid]
        mine = [r for r in self.replies.values() if r["topicId"] == tid]
        last = max(mine, key=lambda r: r["block"]) if mine else None
        self.reply_counts_recomputed += 1
        return (t["companyId"], t["boardId"], t["openedDay"], t["openedBlock"],
                last["day"] if last else t["openedDay"], last["block"] if last else t["openedBlock"], len(mine),
                1 if t["isLocked"] else 0, 1 if t["isPinned"] else 0, 1 if t["isHidden"] else 0)

    def reply_line(self, rid):
        """topicId day block hidden"""
        r = self.replies[rid]
        return (r["topicId"], r["day"], r["block"], 1 if r["isHidden"] else 0)

    def moderation_line(self, mid):
        """target targetId act day block - and the moderator held to be somebody other than the author"""
        m = self.moderations[mid]
        if m["moderator"] == m["author"]:
            self.faults.append("moderation %d names one person as moderator and author" % mid)
        else:
            self.four_eyes_held += 1
        return (m["target"], m["targetId"], m["act"], m["day"], m["block"])

    def summary(self):
        return {
            "boards": len(self.boards),
            "topics": len(self.topics),
            "replies": len(self.replies),
            "moderations": len(self.moderations),
            "idea boards": sum(1 for b in self.idea_boards.values() if b["isIdeas"]),
            "idea decisions": len(self.idea_statuses),
            "votes up": sum(1 for v in self.votes.values() if v["isUp"]),
            "hidden": sum(1 for t in self.topics.values() if t["isHidden"]) + sum(1 for r in self.replies.values() if r["isHidden"]),
            "faults": len(self.faults),
        }
