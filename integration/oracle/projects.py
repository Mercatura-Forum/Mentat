"""The project families (72 to 81), decoded from their canonical bytes, re-encoded so the command
hash can be re-derived, and folded by rules written from the design:

  * a project with a code, a customer, a manager and a cost account; a task in ONE table whatever its
    origin - HR, project, onboarding, offboarding, or a field-service visit - on a member's desk,
    closed by its state; time logged against an open task by a member, a minute to a day of it;
  * a timesheet as the draft entries of one person in a range, submitted whole; decided by somebody
    other than the person; rejected, the entries go back to drafts; approved, THE TIME COSTS: each
    entry's minutes over sixty at the person's hourly rate from their compensation, to the minor unit
    half to even, debited to the task's project's cost account (or the company's first expense
    account) and credited to the company's first payable account, as one entry THROUGH THE LEDGER
    READER dated the last day of the sheet - which is the move the contract proposed in that block.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from decimal import Decimal, ROUND_HALF_EVEN

from canonical import write_nat, write_text

MAX_DAY = 16_777_215
MINUTES_IN_DAY = 1440
ORIGIN_OF_BYTE = {1: "hr", 2: "project", 3: "onboarding", 4: "offboarding", 5: "fieldService"}
BYTE_OF_ORIGIN = {v: k for k, v in ORIGIN_OF_BYTE.items()}
PRIORITY_OF_BYTE = {1: "low", 2: "normal", 3: "high", 4: "urgent"}
BYTE_OF_PRIORITY = {v: k for k, v in PRIORITY_OF_BYTE.items()}
TASK_STATE_OF_BYTE = {1: "todo", 2: "inProgress", 3: "changesRequested", 4: "done", 5: "cancelled"}
BYTE_OF_TASK_STATE = {v: k for k, v in TASK_STATE_OF_BYTE.items()}
PROJECT_STATE_OF_BYTE = {1: "draft", 2: "open", 3: "paused", 4: "done", 5: "cancelled"}
BYTE_OF_PROJECT_STATE = {v: k for k, v in PROJECT_STATE_OF_BYTE.items()}
CLOSED = ("done", "cancelled")


def _named(table, r, what):
    b = r.nat8()
    if b not in table:
        raise ValueError("a %s byte that is not one: %d" % (what, b))
    return table[b]


def _project(r):
    return {"companyId": r.nat(), "code": r.text(), "name": r.text(), "partnerId": r.nat(), "managerEmployeeId": r.nat(),
            "startDay": r.nat(), "endDay": r.nat(), "costAccountId": r.nat()}


def _task(r):
    return {"companyId": r.nat(), "projectId": r.nat(), "origin": _named(ORIGIN_OF_BYTE, r, "task origin"), "title": r.text(),
            "assignee": r.principal(), "priority": _named(PRIORITY_OF_BYTE, r, "priority"), "dueDay": r.nat()}


def _time(r):
    return {"companyId": r.nat(), "taskId": r.nat(), "subject": r.principal(), "businessDay": r.nat(), "minutes": r.nat(), "note": r.text()}


READERS = {
    72: ("createProject", lambda r: {"facts": _project(r)}),
    73: ("amendProject", lambda r: {"projectId": r.nat(), "facts": _project(r)}),
    74: ("setProjectState", lambda r: {"companyId": r.nat(), "projectId": r.nat(), "state": _named(PROJECT_STATE_OF_BYTE, r, "project state"), "reason": r.text()}),
    75: ("createTask", lambda r: {"facts": _task(r)}),
    76: ("amendTask", lambda r: {"taskId": r.nat(), "facts": _task(r)}),
    77: ("setTaskState", lambda r: {"companyId": r.nat(), "taskId": r.nat(), "state": _named(TASK_STATE_OF_BYTE, r, "task state"), "reason": r.text()}),
    78: ("logTime", lambda r: {"facts": _time(r)}),
    79: ("voidTimeEntry", lambda r: {"companyId": r.nat(), "entryId": r.nat(), "reason": r.text()}),
    80: ("submitTimesheet", lambda r: {"companyId": r.nat(), "subject": r.principal(), "fromDay": r.nat(), "toDay": r.nat()}),
    81: ("decideTimesheet", lambda r: {"companyId": r.nat(), "timesheetId": r.nat(), "approve": r.bool(), "journalId": r.nat(), "reason": r.text()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_project_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def _principal(p):
    return bytes([len(p)]) + p


def _project_bytes(f):
    return (write_nat(f["companyId"]) + write_text(f["code"]) + write_text(f["name"]) + write_nat(f["partnerId"]) + write_nat(f["managerEmployeeId"])
            + write_nat(f["startDay"]) + write_nat(f["endDay"]) + write_nat(f["costAccountId"]))


def _task_bytes(f):
    return (write_nat(f["companyId"]) + write_nat(f["projectId"]) + bytes([BYTE_OF_ORIGIN[f["origin"]]]) + write_text(f["title"])
            + _principal(f["assignee"]) + bytes([BYTE_OF_PRIORITY[f["priority"]]]) + write_nat(f["dueDay"]))


def _time_bytes(f):
    return write_nat(f["companyId"]) + write_nat(f["taskId"]) + _principal(f["subject"]) + write_nat(f["businessDay"]) + write_nat(f["minutes"]) + write_text(f["note"])


ENCODERS = {
    "createProject": (72, lambda c: _project_bytes(c["facts"])),
    "amendProject": (73, lambda c: write_nat(c["projectId"]) + _project_bytes(c["facts"])),
    "setProjectState": (74, lambda c: write_nat(c["companyId"]) + write_nat(c["projectId"]) + bytes([BYTE_OF_PROJECT_STATE[c["state"]]]) + write_text(c["reason"])),
    "createTask": (75, lambda c: _task_bytes(c["facts"])),
    "amendTask": (76, lambda c: write_nat(c["taskId"]) + _task_bytes(c["facts"])),
    "setTaskState": (77, lambda c: write_nat(c["companyId"]) + write_nat(c["taskId"]) + bytes([BYTE_OF_TASK_STATE[c["state"]]]) + write_text(c["reason"])),
    "logTime": (78, lambda c: _time_bytes(c["facts"])),
    "voidTimeEntry": (79, lambda c: write_nat(c["companyId"]) + write_nat(c["entryId"]) + write_text(c["reason"])),
    "submitTimesheet": (80, lambda c: write_nat(c["companyId"]) + _principal(c["subject"]) + write_nat(c["fromDay"]) + write_nat(c["toDay"])),
    "decideTimesheet": (81, lambda c: write_nat(c["companyId"]) + write_nat(c["timesheetId"]) + bytes([1 if c["approve"] else 0]) + write_nat(c["journalId"]) + write_text(c["reason"])),
}


def project_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return bytes([tag]) + fn(cmd)


def first_account_of_type(ledger, company, account_type):
    """The contract pages its by-type index and takes the first: the lowest id of that type."""
    candidates = sorted(aid for aid, a in ledger.accounts.items() if a["companyId"] == company and a["accountType"] == account_type)
    return candidates[0] if candidates else 0


def time_cost(minutes, hourly_rate):
    """minutes ÷ 60 × the hourly rate, to a whole minor unit half to even - exactly."""
    exact = Decimal(minutes) / Decimal(60) * Decimal(hourly_rate)
    return int(exact.to_integral_value(rounding=ROUND_HALF_EVEN))


class Projects:
    def __init__(self):
        self.projects = {}
        self.tasks = {}
        self.entries = {}
        self.timesheets = {}
        self.next_project = 1
        self.next_task = 1
        self.next_entry = 1
        self.next_sheet = 1
        self.faults = []

    def task_minutes(self, task_id):
        """The minutes on a task by their standing: approved, and pending (draft or submitted)."""
        approved = pending = 0
        for e in self.entries.values():
            if e["taskId"] != task_id:
                continue
            if e["state"] == "approved":
                approved += e["minutes"]
            elif e["state"] in ("draft", "submitted"):
                pending += e["minutes"]
        return approved, pending

    def apply(self, block, hr, pay, ledger):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = block["caller"]

        if f == "createProject":
            fc = c["facts"]
            self.projects[self.next_project] = {**fc, "state": "draft"}
            self.next_project += 1
            return
        if f == "amendProject":
            p = self.projects.get(c["projectId"])
            if p is not None:
                p.update(c["facts"])
            return
        if f == "setProjectState":
            p = self.projects.get(c["projectId"])
            if p is not None:
                p["state"] = c["state"]
            return

        if f == "createTask":
            fc = c["facts"]
            bad = not fc["title"] or (fc["companyId"], fc["assignee"]) not in hr.members or fc["dueDay"] > MAX_DAY
            if fc["projectId"]:
                p = self.projects.get(fc["projectId"])
                bad = bad or p is None or p["companyId"] != fc["companyId"] or p["state"] in CLOSED
            if bad:
                self.faults.append("block %d created a task it could not" % idx)
                return
            self.tasks[self.next_task] = {**fc, "createdBy": caller, "state": "todo", "createdDay": day, "closedDay": 0}
            self.next_task += 1
            return
        if f == "amendTask":
            t = self.tasks.get(c["taskId"])
            if t is None or t["state"] in CLOSED:
                self.faults.append("block %d amended a task it could not" % idx)
                return
            t.update({k: c["facts"][k] for k in ("projectId", "origin", "title", "assignee", "priority", "dueDay")})
            return
        if f == "setTaskState":
            t = self.tasks.get(c["taskId"])
            if t is None or t["companyId"] != c["companyId"] or t["state"] in CLOSED:
                self.faults.append("block %d moved a task it could not" % idx)
                return
            t["state"] = c["state"]
            t["closedDay"] = day if c["state"] in CLOSED else 0
            return

        if f == "logTime":
            fc = c["facts"]
            t = self.tasks.get(fc["taskId"])
            if (not 1 <= fc["minutes"] <= MINUTES_IN_DAY or fc["businessDay"] > MAX_DAY or (fc["companyId"], fc["subject"]) not in hr.members
                    or t is None or t["companyId"] != fc["companyId"] or t["state"] in CLOSED):
                self.faults.append("block %d logged time it could not" % idx)
                return
            self.entries[self.next_entry] = {**fc, "timesheetId": 0, "state": "draft", "costApplied": 0}
            self.next_entry += 1
            return
        if f == "voidTimeEntry":
            e = self.entries.get(c["entryId"])
            if e is None or e["companyId"] != c["companyId"] or e["state"] in ("approved", "voided"):
                self.faults.append("block %d voided a time entry it could not" % idx)
                return
            e["state"] = "voided"
            return

        if f == "submitTimesheet":
            if c["toDay"] < c["fromDay"] or c["toDay"] > MAX_DAY or (c["companyId"], c["subject"]) not in hr.members:
                self.faults.append("block %d submitted a timesheet it could not" % idx)
                return
            drafts = [(eid, e) for eid, e in sorted(self.entries.items())
                      if e["companyId"] == c["companyId"] and e["subject"] == c["subject"] and e["state"] == "draft" and e["timesheetId"] == 0
                      and c["fromDay"] <= e["businessDay"] <= c["toDay"]]
            if not drafts:
                self.faults.append("block %d submitted a timesheet with nothing on it" % idx)
                return
            sid = self.next_sheet
            self.timesheets[sid] = {"companyId": c["companyId"], "subject": c["subject"], "fromDay": c["fromDay"], "toDay": c["toDay"], "state": "submitted",
                                    "minutes": sum(e["minutes"] for _eid, e in drafts), "decidedBy": c["subject"], "costMoveId": 0}
            self.next_sheet += 1
            for _eid, e in drafts:
                e["timesheetId"] = sid
                e["state"] = "submitted"
            return

        if f == "decideTimesheet":
            sheet = self.timesheets.get(c["timesheetId"])
            if sheet is None or sheet["companyId"] != c["companyId"] or sheet["state"] != "submitted":
                self.faults.append("block %d decided a timesheet it could not" % idx)
                return
            if caller == sheet["subject"]:
                self.faults.append("block %d let a person approve their own timesheet" % idx)
                return
            mine = [(eid, e) for eid, e in sorted(self.entries.items()) if e["timesheetId"] == c["timesheetId"]]
            if not c["approve"]:
                sheet.update({"state": "rejected", "decidedBy": caller})
                for _eid, e in mine:
                    e.update({"state": "draft", "timesheetId": 0})
                return
            comp = pay.comp.get((c["companyId"], sheet["subject"]))
            if comp is None or comp["hourlyRate"] == 0:
                self.faults.append("block %d approved time for somebody whose time has no cost" % idx)
                return
            # THE COST, computed before anything is written
            costed = []
            total = 0
            for eid, e in mine:
                t = self.tasks[e["taskId"]]
                account = 0
                if t["projectId"]:
                    account = self.projects[t["projectId"]]["costAccountId"]
                cost = time_cost(e["minutes"], comp["hourlyRate"])
                total += cost
                costed.append((eid, e, cost, account))
            move_id = 0
            if total > 0:
                payable = first_account_of_type(ledger, c["companyId"], "payable")
                expense = first_account_of_type(ledger, c["companyId"], "expense")
                lines = []
                for _eid, _e, cost, account in costed:
                    if cost > 0:
                        lines.append({"accountId": account or expense, "partnerId": 0, "name": "time", "debit": cost, "credit": 0, "amountCurrency": 0, "taxId": 0})
                lines.append({"accountId": payable, "partnerId": 0, "name": "time payable", "debit": 0, "credit": total, "amountCurrency": 0, "taxId": 0})
                facts = {"companyId": c["companyId"], "journalId": c["journalId"], "businessDay": sheet["toDay"], "moveType": "entry", "currency": comp["currency"],
                         "partnerId": 0, "ref": "timesheet %d" % c["timesheetId"], "lines": lines}
                # THE COST GOES THROUGH THE LEDGER READER, as the move the contract proposed inside this block
                ledger.apply({"command": {"family": "proposeMove", "facts": facts}, "index": idx, "caller": caller, "day": day})
                move_id = ledger.next_move - 1
            sheet.update({"state": "approved", "decidedBy": caller, "costMoveId": move_id})
            for _eid, e, cost, _account in costed:
                e.update({"state": "approved", "costApplied": cost})
            return

    def summary(self):
        return {
            "tasks": len(self.tasks),
            "entries": len(self.entries),
            "timesheets": len(self.timesheets),
            "approved_minutes": sum(e["minutes"] for e in self.entries.values() if e["state"] == "approved"),
            "faults": len(self.faults),
        }
