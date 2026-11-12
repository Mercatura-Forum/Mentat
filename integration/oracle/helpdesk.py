"""The helpdesk families (369 to 378), and the four attendance families the helpdesk's clocks read
(the working week, 226; a company holiday declared, amended and withdrawn, 220 to 222), decoded from
their canonical bytes, re-encoded so the command hash can be re-derived, and folded by rules written
from the design:

  * a team is one per code per company, with a lead who is a member; declared again, changed and
    standing again; retired with open tickets, refused; retired, it takes nothing;
  * a board is stages in order, one per code per team; a ticket enters the first that does not
    close; a stage that closes ends the ticket moved into it;
  * a service level is a promise per priority - working days to the first answer and to the
    resolution, within a year, the resolution no sooner than the answer; a priority without one
    takes no ticket;
  * THE CLOCKS ARE SET BY THE CALENDAR: a deadline is so many working days after the opening, a
    working day being one the company's working week includes (Sunday in bit 0; no week declared,
    every day) and that is not a standing holiday - `due_day` is this reader's own walk, and every
    `ticket:` line's two deadlines are recomputed by it;
  * the requester may write on their ticket and nothing more; an agent's first word stops the
    response clock; a closed ticket takes nothing;
  * THE SWEEP: a run one person opens through a day that has come and another slices, each slice
    the head of the open tickets by the deadline they are next held to - response if unanswered and
    not yet escalated, resolution if answered or escalated once, nothing at level 2 or closed - up
    to a limit; each escalated a level, its priority raised a notch, back on the lead's desk, the
    sweep's word written in the opener's name; the last page closes the run.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text

MAX_DAY = 16_777_215
MAX_SLA_DAYS = 365
MAX_ORDINAL = 255
MAX_REST_RUN = 400
MAX_LIMIT = 1000
PRIORITY_OF_BYTE = {1: "low", 2: "normal", 3: "high", 4: "urgent"}
BYTE_OF_PRIORITY = {v: k for k, v in PRIORITY_OF_BYTE.items()}
RAISED = {"low": "normal", "normal": "high", "high": "urgent", "urgent": "urgent"}
HOLIDAY_KIND_OF_BYTE = {1: "publicHoliday", 2: "national", 3: "religious", 4: "bank"}
BYTE_OF_HOLIDAY_KIND = {v: k for k, v in HOLIDAY_KIND_OF_BYTE.items()}


def _priority(r):
    b = r.nat8()
    if b not in PRIORITY_OF_BYTE:
        raise ValueError("a priority byte that is not one: %d" % b)
    return PRIORITY_OF_BYTE[b]


def _holiday_kind(r):
    b = r.nat8()
    if b not in HOLIDAY_KIND_OF_BYTE:
        raise ValueError("a holiday kind byte that is not one: %d" % b)
    return HOLIDAY_KIND_OF_BYTE[b]


def _holiday_facts(r):
    return {"companyId": r.nat(), "name": r.text(), "description": r.text(), "businessDay": r.nat(), "kind": _holiday_kind(r), "isRecurring": r.bool()}


READERS = {
    # the calendar the clocks read
    220: ("createCompanyHoliday", lambda r: {"facts": _holiday_facts(r)}),
    221: ("amendCompanyHoliday", lambda r: {"holidayId": r.nat(), "facts": _holiday_facts(r)}),
    222: ("withdrawCompanyHoliday", lambda r: {"companyId": r.nat(), "holidayId": r.nat()}),
    226: ("setWorkingHours", lambda r: {"facts": {"companyId": r.nat(), "startMinute": r.nat(), "endMinute": r.nat(), "daysMask": r.nat()}}),
    # the desk
    369: ("declareHelpdeskTeam", lambda r: {"facts": {"companyId": r.nat(), "code": r.text(), "name": r.text(), "lead": r.principal()}}),
    370: ("retireHelpdeskTeam", lambda r: {"companyId": r.nat(), "teamId": r.nat(), "reason": r.text()}),
    371: ("declareTicketStage", lambda r: {"facts": {"companyId": r.nat(), "teamId": r.nat(), "code": r.text(), "name": r.text(), "ordinal": r.nat(), "closes": r.bool()}}),
    372: ("setServiceLevel", lambda r: {"facts": {"companyId": r.nat(), "teamId": r.nat(), "priority": _priority(r), "responseDays": r.nat(), "resolveDays": r.nat()}}),
    373: ("openTicket", lambda r: {"facts": {"companyId": r.nat(), "teamId": r.nat(), "partnerId": r.nat(), "subject": r.text(), "description": r.text(), "priority": _priority(r)}}),
    374: ("assignTicket", lambda r: {"companyId": r.nat(), "ticketId": r.nat(), "assignee": r.principal()}),
    375: ("moveTicket", lambda r: {"companyId": r.nat(), "ticketId": r.nat(), "stageId": r.nat(), "reason": r.text()}),
    376: ("postTicketMessage", lambda r: {"facts": {"companyId": r.nat(), "ticketId": r.nat(), "body": r.text()}}),
    377: ("openEscalationSweep", lambda r: {"companyId": r.nat(), "throughDay": r.nat()}),
    378: ("escalationSweepSlice", lambda r: {"companyId": r.nat(), "runId": r.nat(), "limit": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_helpdesk_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def write_principal(p):
    return bytes([len(p)]) + p


def write_bool(b):
    return bytes([1 if b else 0])


def _holiday_bytes(f):
    return write_nat(f["companyId"]) + write_text(f["name"]) + write_text(f["description"]) + write_nat(f["businessDay"]) + bytes([BYTE_OF_HOLIDAY_KIND[f["kind"]]]) + write_bool(f["isRecurring"])


ENCODERS = {
    "createCompanyHoliday": (220, lambda c: _holiday_bytes(c["facts"])),
    "amendCompanyHoliday": (221, lambda c: write_nat(c["holidayId"]) + _holiday_bytes(c["facts"])),
    "withdrawCompanyHoliday": (222, lambda c: write_nat(c["companyId"]) + write_nat(c["holidayId"])),
    "setWorkingHours": (226, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["startMinute"]) + write_nat(c["facts"]["endMinute"]) + write_nat(c["facts"]["daysMask"])),
    "declareHelpdeskTeam": (369, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["code"]) + write_text(c["facts"]["name"]) + write_principal(c["facts"]["lead"])),
    "retireHelpdeskTeam": (370, lambda c: write_nat(c["companyId"]) + write_nat(c["teamId"]) + write_text(c["reason"])),
    "declareTicketStage": (371, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["teamId"]) + write_text(c["facts"]["code"]) + write_text(c["facts"]["name"])
                           + write_nat(c["facts"]["ordinal"]) + write_bool(c["facts"]["closes"])),
    "setServiceLevel": (372, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["teamId"]) + bytes([BYTE_OF_PRIORITY[c["facts"]["priority"]]])
                        + write_nat(c["facts"]["responseDays"]) + write_nat(c["facts"]["resolveDays"])),
    "openTicket": (373, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["teamId"]) + write_nat(c["facts"]["partnerId"]) + write_text(c["facts"]["subject"])
                   + write_text(c["facts"]["description"]) + bytes([BYTE_OF_PRIORITY[c["facts"]["priority"]]])),
    "assignTicket": (374, lambda c: write_nat(c["companyId"]) + write_nat(c["ticketId"]) + write_principal(c["assignee"])),
    "moveTicket": (375, lambda c: write_nat(c["companyId"]) + write_nat(c["ticketId"]) + write_nat(c["stageId"]) + write_text(c["reason"])),
    "postTicketMessage": (376, lambda c: write_nat(c["facts"]["companyId"]) + write_nat(c["facts"]["ticketId"]) + write_text(c["facts"]["body"])),
    "openEscalationSweep": (377, lambda c: write_nat(c["companyId"]) + write_nat(c["throughDay"])),
    "escalationSweepSlice": (378, lambda c: write_nat(c["companyId"]) + write_nat(c["runId"]) + write_nat(c["limit"])),
}


def helpdesk_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


def week_bit(day):
    """Which bit of the working-week mask a day falls on: Sunday in bit 0; day 0 was a Thursday."""
    return (day + 4) % 7


def pending_deadline(t):
    """THE DEADLINE A TICKET IS NEXT HELD TO, as this reader states it."""
    if t["state"] != "open":
        return None
    if t["escalation"] == 0 and t["firstResponseDay"] == 0:
        return t["responseDueDay"]
    if t["escalation"] < 2:
        return t["resolveDueDay"]
    return None


class Helpdesk:
    def __init__(self):
        self.working_week = {}     # company -> mask
        self.holidays = {}         # id -> row
        self.next_holiday = 1
        self.teams = {}
        self.stages = {}
        self.service_levels = {}
        self.tickets = {}
        self.messages = {}
        self.runs = {}
        self.next_team = 1
        self.next_stage = 1
        self.next_sla = 1
        self.next_ticket = 1
        self.next_message = 1
        self.next_run = 1
        self.clocks_recomputed = 0
        self.escalations = 0
        self.faults = []

    # -- the calendar --

    def holiday_on(self, company, day):
        return any(h["companyId"] == company and h["isActive"] and h["businessDay"] == day for h in self.holidays.values())

    def is_working_day(self, company, day):
        mask = self.working_week.get(company)
        in_week = True if mask is None else (mask >> week_bit(day)) & 1 == 1
        return in_week and not self.holiday_on(company, day)

    def due_day(self, company, start, days):
        """The day `days` working days after `start`: each step the next working day, a run of more
        than MAX_REST_RUN rest days crossed by taking the next day regardless."""
        d = start
        for _ in range(days):
            d += 1
            rest = 0
            while not self.is_working_day(company, d) and rest < MAX_REST_RUN:
                d += 1
                rest += 1
        return d

    # -- reads --

    def team_by_code(self, company, code):
        for tid, t in self.teams.items():
            if t["companyId"] == company and t["code"] == code:
                return tid, t
        return None, None

    def stage_by_code(self, team, code):
        for sid, s in self.stages.items():
            if s["teamId"] == team and s["code"] == code:
                return sid, s
        return None, None

    def first_stage(self, team):
        board = sorted(((s["ordinal"], sid) for sid, s in self.stages.items() if s["teamId"] == team and not s["closes"]))
        return board[0][1] if board else None

    def service_level_of(self, team, priority):
        for lid, l in self.service_levels.items():
            if l["teamId"] == team and l["priority"] == priority:
                return lid, l
        return None, None

    def open_run_of(self, company):
        for rid, r in self.runs.items():
            if r["companyId"] == company and r["state"] == "running":
                return rid
        return None

    def active_team(self, company, team_id):
        t = self.teams.get(team_id)
        if t is None or t["companyId"] != company or not t["isActive"]:
            return None
        return t

    def _write(self, company, ticket_id, kind, body, day, author):
        self.messages[self.next_message] = {"companyId": company, "ticketId": ticket_id, "kind": kind, "body": body, "day": day, "author": author}
        self.next_message += 1

    # -- the families --

    def apply(self, block, hr, partners):
        """`hr.members` is the HR reader's set of (company, subject); `partners` the payment
        reader's note of every partner, id -> facts."""
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]

        if f == "setWorkingHours":
            fc = c["facts"]
            if fc["daysMask"] == 0 or fc["daysMask"] > 127 or fc["startMinute"] >= 1440 or fc["endMinute"] >= 1440:
                self.faults.append("block %d set a working week it could not" % idx)
                return
            self.working_week[fc["companyId"]] = fc["daysMask"]
            return

        if f == "createCompanyHoliday":
            fc = c["facts"]
            if not fc["name"] or fc["businessDay"] > MAX_DAY or self.holiday_on(fc["companyId"], fc["businessDay"]):
                self.faults.append("block %d declared a holiday it could not" % idx)
                return
            self.holidays[self.next_holiday] = {**fc, "isActive": True}
            self.next_holiday += 1
            return

        if f == "amendCompanyHoliday":
            h = self.holidays.get(c["holidayId"])
            fc = c["facts"]
            if h is None or h["companyId"] != fc["companyId"] or not fc["name"] or (fc["businessDay"] != h["businessDay"] and self.holiday_on(fc["companyId"], fc["businessDay"])):
                self.faults.append("block %d amended a holiday it could not" % idx)
                return
            h.update({"name": fc["name"], "description": fc["description"], "businessDay": fc["businessDay"], "kind": fc["kind"], "isRecurring": fc["isRecurring"]})
            return

        if f == "withdrawCompanyHoliday":
            h = self.holidays.get(c["holidayId"])
            if h is None or h["companyId"] != c["companyId"] or not h["isActive"]:
                self.faults.append("block %d withdrew a holiday it could not" % idx)
                return
            h["isActive"] = False
            return

        if f == "declareHelpdeskTeam":
            fc = c["facts"]
            if not fc["name"] or not fc["code"] or len(fc["code"].encode("utf-8")) > 16 or (fc["companyId"], fc["lead"]) not in hr.members:
                self.faults.append("block %d declared a helpdesk team it could not" % idx)
                return
            tid, t = self.team_by_code(fc["companyId"], fc["code"])
            if t is not None:
                t.update({"name": fc["name"], "lead": fc["lead"], "isActive": True, "declaredBy": caller})
                return
            self.teams[self.next_team] = {**fc, "isActive": True, "ticketsOpened": 0, "openTickets": 0, "declaredBy": caller}
            self.next_team += 1
            return

        if f == "retireHelpdeskTeam":
            t = self.active_team(c["companyId"], c["teamId"])
            if t is None or t["openTickets"] > 0:
                self.faults.append("block %d retired a helpdesk team it could not" % idx)
                return
            t["isActive"] = False
            return

        if f == "declareTicketStage":
            fc = c["facts"]
            if self.active_team(fc["companyId"], fc["teamId"]) is None or not fc["name"] or not fc["code"] or len(fc["code"].encode("utf-8")) > 16 or fc["ordinal"] > MAX_ORDINAL:
                self.faults.append("block %d declared a ticket stage it could not" % idx)
                return
            sid, s = self.stage_by_code(fc["teamId"], fc["code"])
            if s is not None:
                s.update({"name": fc["name"], "ordinal": fc["ordinal"], "closes": fc["closes"]})
                return
            self.stages[self.next_stage] = dict(fc)
            self.next_stage += 1
            return

        if f == "setServiceLevel":
            fc = c["facts"]
            if (self.active_team(fc["companyId"], fc["teamId"]) is None or not 1 <= fc["responseDays"] <= MAX_SLA_DAYS
                    or not 1 <= fc["resolveDays"] <= MAX_SLA_DAYS or fc["resolveDays"] < fc["responseDays"]):
                self.faults.append("block %d set a service level it could not" % idx)
                return
            lid, l = self.service_level_of(fc["teamId"], fc["priority"])
            if l is not None:
                l.update({"responseDays": fc["responseDays"], "resolveDays": fc["resolveDays"], "setBy": caller})
                return
            self.service_levels[self.next_sla] = {**fc, "setBy": caller}
            self.next_sla += 1
            return

        if f == "openTicket":
            fc = c["facts"]
            t = self.active_team(fc["companyId"], fc["teamId"])
            bad = t is None or (fc["companyId"], caller) not in hr.members or not fc["subject"]
            if fc["partnerId"]:
                p = partners.get(fc["partnerId"])
                bad = bad or p is None or p["companyId"] != fc["companyId"]
            _lid, sla = self.service_level_of(fc["teamId"], fc["priority"])
            stage = self.first_stage(fc["teamId"])
            if bad or sla is None or stage is None:
                self.faults.append("block %d opened a ticket it could not" % idx)
                return
            response_due = self.due_day(fc["companyId"], day, sla["responseDays"])
            resolve_due = self.due_day(fc["companyId"], day, sla["resolveDays"])
            if resolve_due > MAX_DAY:
                self.faults.append("block %d opened a ticket whose clock does not fit" % idx)
                return
            self.tickets[self.next_ticket] = {
                "companyId": fc["companyId"], "teamId": fc["teamId"], "stageId": stage, "partnerId": fc["partnerId"], "subject": fc["subject"],
                "description": fc["description"], "requester": caller, "assignee": t["lead"], "state": "open", "priority": fc["priority"], "escalation": 0,
                "openedDay": day, "responseDueDay": response_due, "resolveDueDay": resolve_due, "firstResponseDay": 0, "closedDay": 0, "closedBy": caller, "messages": 0}
            self.next_ticket += 1
            t["ticketsOpened"] += 1
            t["openTickets"] += 1
            return

        if f == "assignTicket":
            t = self.tickets.get(c["ticketId"])
            if t is None or t["companyId"] != c["companyId"] or t["state"] != "open" or (c["companyId"], c["assignee"]) not in hr.members or c["assignee"] == t["assignee"]:
                self.faults.append("block %d assigned a ticket it could not" % idx)
                return
            if caller == t["requester"]:
                self.faults.append("block %d let the requester assign their own ticket" % idx)
                return
            t["assignee"] = c["assignee"]
            return

        if f == "moveTicket":
            t = self.tickets.get(c["ticketId"])
            s = self.stages.get(c["stageId"])
            if t is None or t["companyId"] != c["companyId"] or t["state"] != "open" or s is None or s["teamId"] != t["teamId"] or c["stageId"] == t["stageId"]:
                self.faults.append("block %d moved a ticket it could not" % idx)
                return
            if caller == t["requester"]:
                self.faults.append("block %d let the requester move their own ticket" % idx)
                return
            t["stageId"] = c["stageId"]
            if s["closes"]:
                t.update({"state": "closed", "closedDay": day, "closedBy": caller})
                team = self.teams[t["teamId"]]
                team["openTickets"] = max(0, team["openTickets"] - 1)
            return

        if f == "postTicketMessage":
            fc = c["facts"]
            t = self.tickets.get(fc["ticketId"])
            if t is None or t["companyId"] != fc["companyId"] or t["state"] != "open" or not fc["body"]:
                self.faults.append("block %d wrote on a ticket it could not" % idx)
                return
            kind = "requester" if caller == t["requester"] else "agent"
            if kind == "agent" and (fc["companyId"], caller) not in hr.members:
                self.faults.append("block %d let a stranger write on a ticket" % idx)
                return
            self._write(fc["companyId"], fc["ticketId"], kind, fc["body"], day, caller)
            if kind == "agent" and t["firstResponseDay"] == 0:
                t["firstResponseDay"] = day
            t["messages"] += 1
            return

        if f == "openEscalationSweep":
            if c["throughDay"] > MAX_DAY or c["throughDay"] > day or self.open_run_of(c["companyId"]) is not None:
                self.faults.append("block %d opened an escalation sweep it could not" % idx)
                return
            self.runs[self.next_run] = {"companyId": c["companyId"], "throughDay": c["throughDay"], "state": "running", "scanned": 0, "escalated": 0, "openedBy": caller}
            self.next_run += 1
            return

        if f == "escalationSweepSlice":
            run = self.runs.get(c["runId"])
            if run is None or run["companyId"] != c["companyId"] or run["state"] != "running" or not 1 <= c["limit"] <= MAX_LIMIT:
                self.faults.append("block %d sliced an escalation sweep it could not" % idx)
                return
            if caller == run["openedBy"]:
                self.faults.append("block %d let the opener of an escalation sweep slice it" % idx)
                return
            due = []
            for tid, t in self.tickets.items():
                if t["companyId"] != c["companyId"]:
                    continue
                d = pending_deadline(t)
                if d is not None and d <= run["throughDay"]:
                    due.append((d, tid))
            page = sorted(due)[:c["limit"]]
            for d, tid in page:
                t = self.tickets[tid]
                level = 1 if (t["escalation"] == 0 and t["firstResponseDay"] == 0) else 2
                which = "response" if level == 1 else "resolution"
                self._write(c["companyId"], tid, "escalation", "escalated to level %d: the %s deadline, day %d, was missed" % (level, which, d), day, run["openedBy"])
                lead = self.teams[t["teamId"]]["lead"] if t["teamId"] in self.teams else t["assignee"]
                t.update({"escalation": level, "priority": RAISED[t["priority"]], "assignee": lead, "messages": t["messages"] + 1})
                self.escalations += 1
            run["scanned"] += len(page)
            run["escalated"] += len(page)
            if len(page) < c["limit"]:
                run["state"] = "done"
            return

    # -- what the contract prints, recomputed --

    def team_line(self, tid):
        """code active ticketsOpened openTickets - both counts also summed again from the tickets"""
        t = self.teams[tid]
        opened = sum(1 for x in self.tickets.values() if x["teamId"] == tid)
        still_open = sum(1 for x in self.tickets.values() if x["teamId"] == tid and x["state"] == "open")
        if opened != t["ticketsOpened"] or still_open != t["openTickets"]:
            self.faults.append("team %d counts %d opened and %d open; its tickets come to %d and %d" % (tid, t["ticketsOpened"], t["openTickets"], opened, still_open))
        return (t["code"], 1 if t["isActive"] else 0, t["ticketsOpened"], t["openTickets"])

    def sla_line(self, lid):
        """teamId priority responseDays resolveDays"""
        l = self.service_levels[lid]
        return (l["teamId"], l["priority"], l["responseDays"], l["resolveDays"])

    def ticket_line(self, tid):
        """teamId stageId state priority escalation openedDay responseDue resolveDue firstResponseDay
        closedDay messages - the two clocks walked again by the calendar, the messages counted again"""
        t = self.tickets[tid]
        _lid, sla = self.service_level_of(t["teamId"], t["priority"])
        words = sum(1 for m in self.messages.values() if m["ticketId"] == tid)
        if words != t["messages"]:
            self.faults.append("ticket %d counts %d words; its thread has %d" % (tid, t["messages"], words))
        self.clocks_recomputed += 2
        return (t["teamId"], t["stageId"], t["state"], t["priority"], t["escalation"], t["openedDay"], t["responseDueDay"], t["resolveDueDay"],
                t["firstResponseDay"], t["closedDay"], t["messages"])

    def summary(self):
        return {
            "teams": len(self.teams),
            "stages": len(self.stages),
            "service_levels": len(self.service_levels),
            "tickets": len(self.tickets),
            "closed": sum(1 for t in self.tickets.values() if t["state"] == "closed"),
            "escalated": sum(1 for t in self.tickets.values() if t["escalation"] > 0),
            "messages": len(self.messages),
            "runs": len(self.runs),
            "faults": len(self.faults),
        }
