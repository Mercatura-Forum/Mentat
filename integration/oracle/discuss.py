"""The discussion families (549 to 568), decoded from their canonical bytes, re-encoded so the command hash can be
re-derived, and folded by rules written from the design:

  * a CHANNEL is one per name, case and surrounding space aside; its creator is in it with the members named; a
    private one is entered only by being added; A CHANNEL KEEPS ONE MEMBER until it is archived - this reader
    re-counts every channel's members and messages from the rows it folded;
  * a MESSAGE is spoken only by somebody in the channel and DELETED BY ITS SENDER ALONE; THE READ MARK ONLY MOVES
    FORWARD, to a message of that channel;
  * an ANNOUNCEMENT has an audience of roles, departments and job titles, NOBODY SUSPENDED IN IT, and STANDS from its
    start to its end - this reader reads it on the day the contract names, and re-adds every reaction;
  * THE SWEEP walks the company's members in the order they were admitted, a slice at a time, and tells each one the
    audience names, the author aside - THIS READER COMPUTES EVERY AUDIENCE ITSELF from the memberships, roles,
    suspensions, departments and job titles it watched go by, and re-counts every announcement's notified;
  * a NOTIFICATION of a kind that reports a record is HELD TO THE RECORD - this reader reads the leave from the HR
    reader with the decider it watched, the task from the projects reader, the review from the appraisal reader, the
    booking from the appointments reader, the payslip from the payroll reader (which creates one exactly where the
    contract numbers one, so the n-th it holds is payslip n); READ AND DISMISSED BY ITS RECIPIENT ALONE; marking all
    read is the head of the unread.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text

MAX_DAY = 2 ** 24
MAX_TEXT = 4000
MAX_INITIAL_MEMBERS = 32
MAX_SLICE = 500
AUDIENCE_SLOTS = 8
CODE_BYTES = 16
CATEGORIES = {1: "company", 2: "events", 3: "finance", 4: "general", 5: "hr", 6: "it"}
KINDS = {1: "announcement", 2: "leaveApproved", 3: "leaveRejected", 4: "leaveRequest", 5: "meetingInvite",
         6: "payrollProcessed", 7: "performanceReview", 8: "system", 9: "taskAssigned"}
PRIORITIES = {1: "low", 2: "normal", 3: "high", 4: "urgent"}
ROLES = {1: "CompanyAdmin", 2: "HR", 3: "Director", 4: "Manager", 5: "Employee"}
ROLE_BYTE = {v: k for k, v in ROLES.items()}


def write_principal(p):
    return bytes([len(p)]) + bytes(p)


def write_bool(b):
    return b"\x01" if b else b"\x00"


def write_len16(n):
    return n.to_bytes(2, "big")


def read_list(r, fn):
    return [fn() for _ in range(r.len16())]


def read_audience(r):
    return {"roles": read_list(r, r.nat8), "departmentIds": read_list(r, r.nat), "jobTitleIds": read_list(r, r.nat),
            "locations": read_list(r, r.text), "nationalities": read_list(r, r.text)}


def read_announcement(r):
    return {"companyId": r.nat(), "title": r.text(), "body": r.text(), "category": r.nat8(), "isPinned": r.bool(),
            "audience": read_audience(r), "startDay": r.nat(), "endDay": r.nat(), "notify": r.bool()}


READERS = {
    549: ("createChannel", lambda r: {"facts": {"companyId": r.nat(), "name": r.text(), "description": r.text(), "isPrivate": r.bool(), "members": read_list(r, r.principal)}}),
    550: ("archiveChannel", lambda r: {"companyId": r.nat(), "channelId": r.nat()}),
    551: ("joinChannel", lambda r: {"companyId": r.nat(), "channelId": r.nat()}),
    552: ("addChannelMember", lambda r: {"companyId": r.nat(), "channelId": r.nat(), "subject": r.principal()}),
    553: ("leaveChannel", lambda r: {"companyId": r.nat(), "channelId": r.nat()}),
    554: ("removeChannelMember", lambda r: {"companyId": r.nat(), "channelId": r.nat(), "subject": r.principal()}),
    555: ("sendChannelMessage", lambda r: {"companyId": r.nat(), "channelId": r.nat(), "body": r.text()}),
    556: ("deleteChannelMessage", lambda r: {"companyId": r.nat(), "messageId": r.nat()}),
    557: ("markChannelRead", lambda r: {"companyId": r.nat(), "channelId": r.nat(), "messageId": r.nat()}),
    558: ("createAnnouncement", lambda r: {"facts": read_announcement(r)}),
    559: ("amendAnnouncement", lambda r: {"facts": {"companyId": r.nat(), "announcementId": r.nat(), "title": r.text(), "body": r.text(), "category": r.nat8(), "endDay": r.nat()}}),
    560: ("pinAnnouncement", lambda r: {"companyId": r.nat(), "announcementId": r.nat(), "isPinned": r.bool()}),
    561: ("withdrawAnnouncement", lambda r: {"companyId": r.nat(), "announcementId": r.nat()}),
    562: ("toggleReaction", lambda r: {"companyId": r.nat(), "announcementId": r.nat(), "emoji": r.text()}),
    563: ("openAnnouncementSweep", lambda r: {"companyId": r.nat(), "announcementId": r.nat(), "planHash": r.blob()}),
    564: ("sweepAnnouncementSlice", lambda r: {"companyId": r.nat(), "runId": r.nat(), "planHash": r.blob(), "limit": r.nat()}),
    565: ("createNotification", lambda r: {"facts": {"companyId": r.nat(), "recipient": r.principal(), "title": r.text(), "message": r.text(), "kind": r.nat8(), "priority": r.nat8(), "relatedId": r.nat(), "actionUrl": r.text()}}),
    566: ("markNotificationRead", lambda r: {"companyId": r.nat(), "notificationId": r.nat()}),
    567: ("markAllNotificationsRead", lambda r: {"companyId": r.nat(), "limit": r.nat()}),
    568: ("dismissNotification", lambda r: {"companyId": r.nat(), "notificationId": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}

# The HR families this reader watches on their way to the HR reader: who is a member in what order and role, who is
# suspended, which department and job title each employee holds, which departments and titles stand, who decided a leave.
WATCHED = {"admitMember", "setMemberRole", "suspendMember", "reinstateMember", "registerEmployee", "amendEmployeeStanding",
           "createDepartment", "closeDepartment", "declareJobTitle", "retireJobTitle", "decideLeave"}


def read_discuss_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def _announcement_bytes(f):
    a = f["audience"]
    return (write_nat(f["companyId"]) + write_text(f["title"]) + write_text(f["body"]) + bytes([f["category"]]) + write_bool(f["isPinned"])
            + write_len16(len(a["roles"])) + bytes(a["roles"])
            + write_len16(len(a["departmentIds"])) + b"".join(write_nat(x) for x in a["departmentIds"])
            + write_len16(len(a["jobTitleIds"])) + b"".join(write_nat(x) for x in a["jobTitleIds"])
            + write_len16(len(a["locations"])) + b"".join(write_text(x) for x in a["locations"])
            + write_len16(len(a["nationalities"])) + b"".join(write_text(x) for x in a["nationalities"])
            + write_nat(f["startDay"]) + write_nat(f["endDay"]) + write_bool(f["notify"]))


ENCODERS = {
    "createChannel": (549, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["name"]) + write_text(c["facts"]["description"]) + write_bool(c["facts"]["isPrivate"])
                      + write_len16(len(c["facts"]["members"])) + b"".join(write_principal(p) for p in c["facts"]["members"])),
    "archiveChannel": (550, lambda c: write_nat(c["companyId"]) + write_nat(c["channelId"])),
    "joinChannel": (551, lambda c: write_nat(c["companyId"]) + write_nat(c["channelId"])),
    "addChannelMember": (552, lambda c: write_nat(c["companyId"]) + write_nat(c["channelId"]) + write_principal(c["subject"])),
    "leaveChannel": (553, lambda c: write_nat(c["companyId"]) + write_nat(c["channelId"])),
    "removeChannelMember": (554, lambda c: write_nat(c["companyId"]) + write_nat(c["channelId"]) + write_principal(c["subject"])),
    "sendChannelMessage": (555, lambda c: write_nat(c["companyId"]) + write_nat(c["channelId"]) + write_text(c["body"])),
    "deleteChannelMessage": (556, lambda c: write_nat(c["companyId"]) + write_nat(c["messageId"])),
    "markChannelRead": (557, lambda c: write_nat(c["companyId"]) + write_nat(c["channelId"]) + write_nat(c["messageId"])),
    "createAnnouncement": (558, lambda c: _announcement_bytes(c["facts"])),
    "amendAnnouncement": (559, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["announcementId"]) + write_text(c["facts"]["title"]) + write_text(c["facts"]["body"])
                          + bytes([c["facts"]["category"]]) + write_nat(c["facts"]["endDay"])),
    "pinAnnouncement": (560, lambda c: write_nat(c["companyId"]) + write_nat(c["announcementId"]) + write_bool(c["isPinned"])),
    "withdrawAnnouncement": (561, lambda c: write_nat(c["companyId"]) + write_nat(c["announcementId"])),
    "toggleReaction": (562, lambda c: write_nat(c["companyId"]) + write_nat(c["announcementId"]) + write_text(c["emoji"])),
    "openAnnouncementSweep": (563, lambda c: write_nat(c["companyId"]) + write_nat(c["announcementId"]) + write_len16(len(c["planHash"])) + bytes(c["planHash"])),
    "sweepAnnouncementSlice": (564, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_len16(len(c["planHash"])) + bytes(c["planHash"]) + write_nat(c["limit"])),
    "createNotification": (565, lambda c: write_nat(c["facts"]["companyId"]) + write_principal(c["facts"]["recipient"]) + write_text(c["facts"]["title"]) + write_text(c["facts"]["message"])
                           + bytes([c["facts"]["kind"], c["facts"]["priority"]]) + write_nat(c["facts"]["relatedId"]) + write_text(c["facts"]["actionUrl"])),
    "markNotificationRead": (566, lambda c: write_nat(c["companyId"]) + write_nat(c["notificationId"])),
    "markAllNotificationsRead": (567, lambda c: write_nat(c["companyId"]) + write_nat(c["limit"])),
    "dismissNotification": (568, lambda c: write_nat(c["companyId"]) + write_nat(c["notificationId"])),
}


def discuss_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


def normalise(name):
    """Lower-case ASCII only and trim spaces, tabs and line ends - the contract's rule, restated."""
    lowered = "".join(chr(ord(ch) + 32) if "A" <= ch <= "Z" else ch for ch in name)
    return lowered.strip(" \t\n\r")


def plan_hash(company, announcement):
    import hashlib
    return hashlib.sha256(company.to_bytes(6, "big") + announcement.to_bytes(6, "big")).digest()


def stands_on(a, day):
    return not a["withdrawn"] and a["startDay"] <= day and (a["endDay"] == 0 or day <= a["endDay"])


class Discuss:
    def __init__(self):
        # what this reader watched of HR
        self.memberships = []          # (membership id, company, subject) in admission order
        self.next_membership = 1
        self.roles = {}                # (company, subject) -> role name
        self.suspended = set()
        self.employees = {}            # (company, subject) -> (departmentId, jobTitleId)
        self.departments = {}          # id -> {"companyId", "open"}
        self.next_department = 1
        self.titles = {}               # id -> {"companyId", "active"}
        self.next_title = 1
        self.leave_decider = {}        # leave request id -> the principal who decided it
        # the tables
        self.channels = {}
        self.members = {}
        self.member_of = {}            # (channel, subject) -> member row id
        self.messages = {}
        self.announcements = {}
        self.reactions = {}
        self.reaction_of = {}          # (announcement, subject, emoji) -> reaction row id
        self.notifications = {}
        self.sweeps = {}
        self.next_channel = 1
        self.next_member = 1
        self.next_message = 1
        self.next_announcement = 1
        self.next_reaction = 1
        self.next_notification = 1
        self.next_sweep = 1
        self.audiences_computed = 0
        self.counts_recomputed = 0
        self.reactions_readded = 0
        self.standing_read = 0
        self.faults = []

    # -- what this reader watches of HR --

    def observe(self, block):
        c = block["command"]
        f = c["family"]
        if f == "admitMember":
            self.memberships.append((self.next_membership, c["companyId"], bytes(c["subject"])))
            self.next_membership += 1
            self.roles[(c["companyId"], bytes(c["subject"]))] = c["companyRole"]
        elif f == "setMemberRole":
            self.roles[(c["companyId"], bytes(c["subject"]))] = c["companyRole"]
        elif f == "suspendMember":
            self.suspended.add((c["companyId"], bytes(c["subject"])))
        elif f == "reinstateMember":
            self.suspended.discard((c["companyId"], bytes(c["subject"])))
        elif f == "registerEmployee":
            fc = c["facts"]
            self.employees[(fc["companyId"], bytes(fc["subject"]))] = (fc["standing"]["departmentId"], fc["standing"]["jobTitleId"])
        elif f == "amendEmployeeStanding":
            self.employees[(c["companyId"], bytes(c["subject"]))] = (c["standing"]["departmentId"], c["standing"]["jobTitleId"])
        elif f == "createDepartment":
            self.departments[self.next_department] = {"companyId": c["facts"]["companyId"], "open": True}
            self.next_department += 1
        elif f == "closeDepartment":
            d = self.departments.get(c["departmentId"])
            if d is not None:
                d["open"] = False
        elif f == "declareJobTitle":
            self.titles[self.next_title] = {"companyId": c["facts"]["companyId"], "active": True}
            self.next_title += 1
        elif f == "retireJobTitle":
            t = self.titles.get(c["jobTitleId"])
            if t is not None:
                t["active"] = False
        elif f == "decideLeave":
            self.leave_decider[c["requestId"]] = bytes(block["caller"])

    # -- the rules, restated --

    def is_member(self, co, p):
        return (co, bytes(p)) in self.roles

    def in_audience(self, a, co, p):
        """Not suspended, and named by every field of the audience that names anything."""
        self.audiences_computed += 1
        p = bytes(p)
        if (co, p) in self.suspended:
            return False
        if a["roles"] and self.roles.get((co, p)) not in a["roles"]:
            return False
        dept, title = self.employees.get((co, p), (0, 0))
        if a["departmentIds"] and dept not in a["departmentIds"]:
            return False
        if a["jobTitleIds"] and title not in a["jobTitleIds"]:
            return False
        return True

    def active_member(self, ch, p):
        mid = self.member_of.get((ch, bytes(p)))
        return mid is not None and self.members[mid]["active"]

    def put_member(self, co, ch, p):
        key = (ch, bytes(p))
        mid = self.member_of.get(key)
        if mid is None:
            mid = self.next_member
            self.next_member += 1
            self.member_of[key] = mid
            self.members[mid] = {"companyId": co, "channelId": ch, "subject": bytes(p), "active": True, "readUpTo": 0}
        else:
            self.members[mid]["active"] = True
        return mid

    def related_ok(self, fc, caller, day, store):
        kind = KINDS.get(fc["kind"])
        rid = fc["relatedId"]
        co = fc["companyId"]
        to = bytes(fc["recipient"])
        if kind == "system":
            return rid == 0
        if rid == 0 or kind is None:
            return False
        if kind == "announcement":
            a = self.announcements.get(rid)
            self.standing_read += 1
            return a is not None and a["companyId"] == co and stands_on(a, day) and self.in_audience(a, co, to)
        if kind in ("leaveApproved", "leaveRejected", "leaveRequest"):
            lv = store.hr.requests.get(rid)
            if lv is None or lv["companyId"] != co:
                return False
            subject = bytes(lv["subject"])
            if kind == "leaveRequest":
                return lv["state"] == "Pending" and subject == caller and subject != to
            wanted = "Approved" if kind == "leaveApproved" else "Rejected"
            return lv["state"] == wanted and self.leave_decider.get(rid) == caller and subject == to
        if kind == "taskAssigned":
            t = store.projects.tasks.get(rid)
            return t is not None and t["companyId"] == co and bytes(t["assignee"]) == to
        if kind == "performanceReview":
            rv = store.appraisals.reviews.get(rid)
            return rv is not None and rv["companyId"] == co and bytes(rv["subject"]) == to
        if kind == "meetingInvite":
            b = store.appointments.bookings.get(rid)
            return b is not None and b["companyId"] == co and b["state"] == "confirmed" and bytes(b["bookedBy"]) == caller
        if kind == "payrollProcessed":
            slips = list(store.pay.payslips.items())
            if not 1 <= rid <= len(slips):
                return False
            (run_id, subject), _slip = slips[rid - 1]
            run = store.pay.runs.get(run_id)
            return run is not None and run["companyId"] == co and bytes(subject) == to
        return False

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = bytes(block["caller"])

        def member(co):
            return co in store.companies and self.is_member(co, caller)

        def fault(what):
            self.faults.append("block %d %s" % (idx, what))

        def channel(co, ch, open_only=True):
            x = self.channels.get(ch)
            if x is None or x["companyId"] != co or not member(co) or (open_only and x["archived"]):
                return None
            return x

        if f == "createChannel":
            fc = c["facts"]
            co = fc["companyId"]
            key = normalise(fc["name"])
            ms = [bytes(p) for p in fc["members"]]
            ok = member(co) and key and len(fc["name"]) <= MAX_TEXT and len(fc["description"]) <= MAX_TEXT \
                and not any(x["companyId"] == co and x["nameKey"] == key for x in self.channels.values()) \
                and len(ms) <= MAX_INITIAL_MEMBERS and caller not in ms and len(set(ms)) == len(ms) and all(self.is_member(co, p) for p in ms)
            if not ok:
                fault("OPENED A CHANNEL IT COULD NOT")
                return
            ch = self.next_channel
            self.next_channel += 1
            self.channels[ch] = {"companyId": co, "nameKey": key, "private": fc["isPrivate"], "archived": False, "createdBy": caller}
            self.put_member(co, ch, caller)
            for p in ms:
                self.put_member(co, ch, p)
            return

        if f == "archiveChannel":
            x = channel(c["companyId"], c["channelId"])
            if x is None or x["createdBy"] != caller:
                fault("archived a channel it could not")
                return
            x["archived"] = True
            return

        if f in ("joinChannel", "addChannelMember"):
            co, ch = c["companyId"], c["channelId"]
            x = channel(co, ch)
            subject = caller if f == "joinChannel" else bytes(c["subject"])
            if f == "joinChannel":
                ok = x is not None and not x["private"]
            else:
                ok = x is not None and self.active_member(ch, caller) and self.is_member(co, subject)
            if not ok or self.active_member(ch, subject):
                fault("PUT SOMEBODY IN A CHANNEL IT COULD NOT")
                return
            self.put_member(co, ch, subject)
            return

        if f in ("leaveChannel", "removeChannelMember"):
            co, ch = c["companyId"], c["channelId"]
            x = channel(co, ch, open_only=(f == "removeChannelMember"))
            subject = caller if f == "leaveChannel" else bytes(c["subject"])
            ok = x is not None and self.active_member(ch, subject)
            if ok and f == "removeChannelMember":
                ok = x["createdBy"] == caller and subject != caller
            if ok and not x["archived"]:
                ok = sum(1 for m in self.members.values() if m["channelId"] == ch and m["active"]) > 1
            if not ok:
                fault("TOOK SOMEBODY OUT OF A CHANNEL IT COULD NOT")
                return
            self.members[self.member_of[(ch, subject)]]["active"] = False
            return

        if f == "sendChannelMessage":
            co, ch = c["companyId"], c["channelId"]
            x = channel(co, ch)
            if x is None or not self.active_member(ch, caller) or not c["body"] or len(c["body"]) > MAX_TEXT:
                fault("SPOKE IN A CHANNEL IT COULD NOT")
                return
            self.messages[self.next_message] = {"companyId": co, "channelId": ch, "sender": caller, "day": day, "deleted": False}
            self.next_message += 1
            return

        if f == "deleteChannelMessage":
            m = self.messages.get(c["messageId"])
            if not member(c["companyId"]) or m is None or m["companyId"] != c["companyId"] or m["sender"] != caller or m["deleted"]:
                fault("DELETED A MESSAGE IT COULD NOT")
                return
            m["deleted"] = True
            return

        if f == "markChannelRead":
            co, ch = c["companyId"], c["channelId"]
            x = channel(co, ch, open_only=False)
            mid = self.member_of.get((ch, caller))
            m = self.messages.get(c["messageId"])
            if x is None or mid is None or not self.members[mid]["active"] or m is None or m["channelId"] != ch or c["messageId"] <= self.members[mid]["readUpTo"]:
                fault("MOVED A READ MARK IT COULD NOT")
                return
            self.members[mid]["readUpTo"] = c["messageId"]
            return

        if f == "createAnnouncement":
            fc = c["facts"]
            co = fc["companyId"]
            a = fc["audience"]
            start = day if fc["startDay"] == 0 else fc["startDay"]
            roles = [ROLES.get(b) for b in a["roles"]]
            ok = member(co) and fc["title"] and fc["body"] and len(fc["title"]) <= MAX_TEXT and len(fc["body"]) <= MAX_TEXT \
                and start < MAX_DAY and start >= day and fc["endDay"] < MAX_DAY and (fc["endDay"] == 0 or fc["endDay"] >= start) \
                and not a["locations"] and not a["nationalities"] and None not in roles and len(set(roles)) == len(roles) \
                and len(a["departmentIds"]) <= AUDIENCE_SLOTS and len(set(a["departmentIds"])) == len(a["departmentIds"]) \
                and all(d in self.departments and self.departments[d]["companyId"] == co and self.departments[d]["open"] for d in a["departmentIds"]) \
                and len(a["jobTitleIds"]) <= AUDIENCE_SLOTS and len(set(a["jobTitleIds"])) == len(a["jobTitleIds"]) \
                and all(t in self.titles and self.titles[t]["companyId"] == co and self.titles[t]["active"] for t in a["jobTitleIds"]) \
                and fc["category"] in CATEGORIES
            if not ok:
                fault("MADE AN ANNOUNCEMENT IT COULD NOT")
                return
            self.announcements[self.next_announcement] = {"companyId": co, "roles": roles, "departmentIds": sorted(a["departmentIds"]), "jobTitleIds": sorted(a["jobTitleIds"]),
                                                          "startDay": start, "endDay": fc["endDay"], "notify": fc["notify"], "withdrawn": False, "pinned": fc["isPinned"],
                                                          "author": caller, "category": CATEGORIES[fc["category"]]}
            self.next_announcement += 1
            return

        def live(co, aid):
            a = self.announcements.get(aid)
            return a if a is not None and a["companyId"] == co and member(co) and not a["withdrawn"] else None

        if f == "amendAnnouncement":
            fc = c["facts"]
            a = live(fc["companyId"], fc["announcementId"])
            ok = a is not None and a["author"] == caller and fc["title"] and fc["body"] and fc["endDay"] < MAX_DAY \
                and (fc["endDay"] == 0 or (fc["endDay"] >= a["startDay"] and fc["endDay"] >= day)) and fc["category"] in CATEGORIES
            if not ok:
                fault("AMENDED AN ANNOUNCEMENT IT COULD NOT")
                return
            a["endDay"] = fc["endDay"]
            a["category"] = CATEGORIES[fc["category"]]
            return

        if f == "pinAnnouncement":
            a = live(c["companyId"], c["announcementId"])
            if a is None or a["pinned"] == c["isPinned"]:
                fault("pinned an announcement it could not")
                return
            a["pinned"] = c["isPinned"]
            return

        if f == "withdrawAnnouncement":
            a = live(c["companyId"], c["announcementId"])
            running = any(s["announcementId"] == c["announcementId"] and s["companyId"] == c["companyId"] and s["state"] == "running" for s in self.sweeps.values())
            if a is None or a["author"] != caller or running:
                fault("WITHDREW AN ANNOUNCEMENT IT COULD NOT")
                return
            a["withdrawn"] = True
            return

        if f == "toggleReaction":
            co, aid = c["companyId"], c["announcementId"]
            a = live(co, aid)
            self.standing_read += 1
            emoji = c["emoji"]
            if a is None or not stands_on(a, day) or not self.in_audience(a, co, caller) or not emoji or len(emoji.encode("utf-8")) > CODE_BYTES:
                fault("REACTED WHERE IT COULD NOT")
                return
            key = (aid, caller, emoji)
            rid = self.reaction_of.get(key)
            if rid is None:
                self.reaction_of[key] = self.next_reaction
                self.reactions[self.next_reaction] = {"announcementId": aid, "active": True}
                self.next_reaction += 1
            else:
                self.reactions[rid]["active"] = not self.reactions[rid]["active"]
            return

        if f == "openAnnouncementSweep":
            co, aid = c["companyId"], c["announcementId"]
            a = live(co, aid)
            self.standing_read += 1
            ok = a is not None and a["notify"] and stands_on(a, day) and bytes(c["planHash"]) == plan_hash(co, aid) \
                and not any(s["companyId"] == co and s["announcementId"] == aid for s in self.sweeps.values())
            if not ok:
                fault("OPENED A SWEEP IT COULD NOT")
                return
            self.sweeps[self.next_sweep] = {"companyId": co, "announcementId": aid, "state": "running", "cursor": 0, "scanned": 0, "acted": 0}
            self.next_sweep += 1
            return

        if f == "sweepAnnouncementSlice":
            co = c["companyId"]
            s = self.sweeps.get(c["runId"])
            ok = 0 < c["limit"] <= MAX_SLICE and member(co) and s is not None and s["companyId"] == co and s["state"] == "running" \
                and bytes(c["planHash"]) == plan_hash(co, s["announcementId"])
            if not ok:
                fault("RAN A SWEEP SLICE IT COULD NOT")
                return
            a = self.announcements[s["announcementId"]]
            walked = [(mid, p) for mid, mco, p in self.memberships if mco == co and mid > s["cursor"]][:c["limit"]]
            told = 0
            for mid, p in walked:
                if p != a["author"] and self.in_audience(a, co, p):
                    self.notifications[self.next_notification] = {"companyId": co, "recipient": p, "kind": "announcement", "priority": "high" if a["pinned"] else "normal",
                                                                  "relatedId": s["announcementId"], "read": False, "dismissed": False, "runId": c["runId"], "day": day}
                    self.next_notification += 1
                    told += 1
                s["cursor"] = mid
            s["scanned"] += len(walked)
            s["acted"] += told
            if len(walked) < c["limit"]:
                s["state"] = "done"
            return

        if f == "createNotification":
            fc = c["facts"]
            co = fc["companyId"]
            ok = member(co) and self.is_member(co, fc["recipient"]) and fc["title"] and len(fc["title"]) <= MAX_TEXT and len(fc["message"]) <= MAX_TEXT \
                and len(fc["actionUrl"]) <= MAX_TEXT and fc["priority"] in PRIORITIES and self.related_ok(fc, caller, day, store)
            if not ok:
                fault("SENT A NOTIFICATION IT COULD NOT")
                return
            self.notifications[self.next_notification] = {"companyId": co, "recipient": bytes(fc["recipient"]), "kind": KINDS[fc["kind"]], "priority": PRIORITIES[fc["priority"]],
                                                          "relatedId": fc["relatedId"], "read": False, "dismissed": False, "runId": 0, "day": day}
            self.next_notification += 1
            return

        def own(co, nid):
            n = self.notifications.get(nid)
            return n if n is not None and n["companyId"] == co and member(co) and n["recipient"] == caller and not n["dismissed"] else None

        if f == "markNotificationRead":
            n = own(c["companyId"], c["notificationId"])
            if n is None or n["read"]:
                fault("READ A NOTIFICATION IT COULD NOT")
                return
            n["read"] = True
            return

        if f == "markAllNotificationsRead":
            co = c["companyId"]
            if not 0 < c["limit"] <= MAX_SLICE or not member(co):
                fault("marked notifications read where it could not")
                return
            head = [n for _nid, n in sorted(self.notifications.items()) if n["companyId"] == co and n["recipient"] == caller and not n["read"] and not n["dismissed"]][:c["limit"]]
            for n in head:
                n["read"] = True
            return

        if f == "dismissNotification":
            n = own(c["companyId"], c["notificationId"])
            if n is None:
                fault("DISMISSED A NOTIFICATION IT COULD NOT")
                return
            n["dismissed"] = True
            return

    # -- what the contract prints, recomputed --

    def membership_id(self, co, p):
        for mid, mco, q in self.memberships:
            if mco == co and q == bytes(p):
                return mid
        return 0

    def channel_line(self, ch):
        """companyId private archived members messages lastMessageId - the last three recomputed from the rows"""
        x = self.channels[ch]
        self.counts_recomputed += 1
        said = [mid for mid, m in self.messages.items() if m["channelId"] == ch]
        return (x["companyId"], 1 if x["private"] else 0, 1 if x["archived"] else 0,
                sum(1 for m in self.members.values() if m["channelId"] == ch and m["active"]), len(said), max(said) if said else 0)

    def member_line(self, mid):
        m = self.members[mid]
        return (m["channelId"], self.membership_id(m["companyId"], m["subject"]), 1 if m["active"] else 0, m["readUpTo"])

    def message_line(self, mid):
        m = self.messages[mid]
        return (m["channelId"], self.membership_id(m["companyId"], m["sender"]), 1 if m["deleted"] else 0, m["day"])

    def announcement_line(self, aid, on_day):
        """companyId start end withdrawn pinned reactions notified onDay stands - the reactions re-added, the notified re-counted, the standing read"""
        a = self.announcements[aid]
        self.reactions_readded += 1
        self.standing_read += 1
        reactions = sum(1 for r in self.reactions.values() if r["announcementId"] == aid and r["active"])
        notified = sum(1 for n in self.notifications.values() if n["relatedId"] == aid and n["runId"] != 0 and n["kind"] == "announcement")
        return (a["companyId"], a["startDay"], a["endDay"], 1 if a["withdrawn"] else 0, 1 if a["pinned"] else 0, a["category"], reactions, notified, on_day, 1 if stands_on(a, on_day) else 0)

    def reaction_line(self, rid):
        r = self.reactions[rid]
        return (r["announcementId"], 1 if r["active"] else 0)

    def notification_line(self, nid):
        n = self.notifications[nid]
        return (self.membership_id(n["companyId"], n["recipient"]), n["kind"], n["priority"], n["relatedId"], 1 if n["read"] else 0, 1 if n["dismissed"] else 0, n["runId"], n["day"])

    def sweep_line(self, sid):
        """announcementId state cursor scanned acted - acted re-counted from the notifications the sweep wrote"""
        s = self.sweeps[sid]
        acted = sum(1 for n in self.notifications.values() if n["runId"] == sid)
        return (s["announcementId"], s["state"], s["cursor"], s["scanned"], acted)

    def summary(self):
        return {"channels": len(self.channels), "channel members": len(self.members), "messages": len(self.messages), "announcements": len(self.announcements),
                "reactions": len(self.reactions), "notifications": len(self.notifications), "sweeps": len(self.sweeps), "faults": len(self.faults)}
