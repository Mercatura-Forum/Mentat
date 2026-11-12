"""The approval-workflow families (586 to 592), decoded from their canonical bytes, re-encoded so the command hash
can be re-derived, and folded by rules written from the design - together with THE GATE every domain decision
about a record of a chained kind passes, which this reader holds every such block to before the domain's own
reader folds it:

  * A CYCLE, defined by a company administrator or HR: a name and one to six steps, each a company role; one active
    per kind, a new one retiring the old; a request keeps the steps it started with;
  * A REQUEST through the kind's active cycle: a general request or a business trip names no record and says what it
    is about; any other kind names A PENDING RECORD OF ITS OWN DOMAIN, IN THE COMPANY, ASKED FOR BY THE STARTER (a
    payroll run and a purchase order name nobody, so whoever starts it asks), with no other request in flight about
    it - read from the reader that folds that domain: leave from the HR reader, an expense claim from the expense
    reader, a loan and an off-cycle payment from the compensation reader, a payroll run and an overtime claim from the
    payroll reader, a purchase order from the credit reader. A day at home and a job offer are folded by no reader of
    this tree (their families are not in the exported log); a request about one is counted and printed, and every
    other rule still held to it;
  * A STEP decided by a holder of its role, or by whoever holds a delegation STANDING ON THE DAY from a member who
    holds it - never the requester in either name, nobody twice in either name; a rejection carries its reason; the
    last step of a linked request is never decided here; a request whose record its domain settled since is carried
    no further;
  * THE GATE: while a request is in flight about a record, the domain's approval stands only at the request's last
    step, by somebody with authority to decide it, and ends the request approved; a rejection always stands and ends
    the request rejected; with no request in flight, the domain's approval stands only while the company has no
    active cycle for the kind;
  * A DELEGATION, the giver's approvals held by another member from the day given until a day at most a year and a
    day on; one standing at a time from a person, the one past its day lapsed when the next is given; revoked by its
    giver while it stands.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import write_nat, write_text

KINDS = {1: "businessTrip", 2: "expense", 3: "general", 4: "jobOffer", 5: "leave", 6: "loan", 7: "offCyclePay", 8: "overtime",
         9: "payrollRun", 10: "purchase", 11: "wfh"}
KIND_BYTE = {v: k for k, v in KINDS.items()}
UNLINKED = {"general", "businessTrip"}
UNREAD = {"wfh", "jobOffer"}
ROLE_OF_BYTE = {1: "CompanyAdmin", 2: "HR", 3: "Director", 4: "Manager", 5: "Employee", 6: "Auditor", 7: "Drafter"}
CHAIN_STATE_BYTE = {"approved": 1, "pending": 2, "rejected": 3, "withdrawn": 4}
DELEGATION_STATE_BYTE = {"active": 1, "lapsed": 2, "revoked": 3}
GOVERNORS = ("CompanyAdmin", "HR")
MAX_STEPS = 6
MAX_TEXT = 4_000
MAX_DELEGATION_DAYS = 366

# every domain decision about a record of a chained kind: (kind, the record's field, whether it approves)
GATED = {
    "decideLeave": ("leave", "requestId", lambda c: c["approve"]),
    "approvePayrollRun": ("payrollRun", "runId", lambda c: True),
    "rejectExpenseClaim": ("expense", "claimId", lambda c: False),
    "approveExpenseClaim": ("expense", "claimId", lambda c: True),
    "confirmOrder": ("purchase", "orderId", lambda c: True),
    "cancelOrder": ("purchase", "orderId", lambda c: False),
    "approveOffCyclePayment": ("offCyclePay", "paymentId", lambda c: True),
    "rejectOffCyclePayment": ("offCyclePay", "paymentId", lambda c: False),
    "decideLoan": ("loan", "loanId", lambda c: c["approve"]),
    "decideOvertime": ("overtime", "overtimeId", lambda c: c["approve"]),
    "decideWorkFromHome": ("wfh", "wfhId", lambda c: c["approve"]),
    "sendOffer": ("jobOffer", "offerId", lambda c: True),
    "rescindOffer": ("jobOffer", "offerId", lambda c: False),
}


def write_bool(b):
    return b"\x01" if b else b"\x00"


def write_len16(n):
    return n.to_bytes(2, "big")


def write_principal(p):
    return bytes([len(p)]) + bytes(p)


def read_roles(r):
    return [r.nat8() for _ in range(r.len16())]


READERS = {
    586: ("defineApprovalCycle", lambda r: {"facts": {"companyId": r.nat(), "name": r.text(), "kind": r.nat8(), "steps": read_roles(r)}}),
    587: ("retireApprovalCycle", lambda r: {"companyId": r.nat(), "cycleId": r.nat()}),
    588: ("startApproval", lambda r: {"facts": {"companyId": r.nat(), "kind": r.nat8(), "recordId": r.nat(), "subject": r.text()}}),
    589: ("decideApprovalStep", lambda r: {"companyId": r.nat(), "instanceId": r.nat(), "approve": r.bool(), "note": r.text()}),
    590: ("withdrawApproval", lambda r: {"companyId": r.nat(), "instanceId": r.nat()}),
    591: ("delegateApprovals", lambda r: {"companyId": r.nat(), "delegate": r.principal(), "untilDay": r.nat()}),
    592: ("revokeDelegation", lambda r: {"companyId": r.nat(), "delegationId": r.nat()}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_workflow_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


ENCODERS = {
    "defineApprovalCycle": (586, lambda c: write_nat(c["facts"]["companyId"]) + write_text(c["facts"]["name"]) + bytes([c["facts"]["kind"]])
                            + write_len16(len(c["facts"]["steps"])) + bytes(c["facts"]["steps"])),
    "retireApprovalCycle": (587, lambda c: write_nat(c["companyId"]) + write_nat(c["cycleId"])),
    "startApproval": (588, lambda c: write_nat(c["facts"]["companyId"]) + bytes([c["facts"]["kind"]]) + write_nat(c["facts"]["recordId"])
                      + write_text(c["facts"]["subject"])),
    "decideApprovalStep": (589, lambda c: write_nat(c["companyId"]) + write_nat(c["instanceId"]) + write_bool(c["approve"]) + write_text(c["note"])),
    "withdrawApproval": (590, lambda c: write_nat(c["companyId"]) + write_nat(c["instanceId"])),
    "delegateApprovals": (591, lambda c: write_nat(c["companyId"]) + write_principal(c["delegate"]) + write_nat(c["untilDay"])),
    "revokeDelegation": (592, lambda c: write_nat(c["companyId"]) + write_nat(c["delegationId"])),
}


def workflow_command_bytes(cmd):
    tag, enc = ENCODERS[cmd["family"]]
    return put_tag(tag) + enc(cmd)


def stands(d, day):
    return d["state"] == "active" and d["fromDay"] <= day <= d["untilDay"]


class Workflow:
    def __init__(self):
        self.cycles = {}
        self.instances = {}
        self.decisions = {}
        self.delegations = {}
        self.next_cycle = 1
        self.next_instance = 1
        self.next_decision = 1
        self.next_delegation = 1
        self.records_read = 0
        self.records_unread = 0
        self.gates_held = 0
        self.authorities_checked = 0
        self.faults = []

    # -- reads --

    def active_cycle(self, co, kind):
        for cid in sorted(self.cycles):
            x = self.cycles[cid]
            if x["companyId"] == co and x["kind"] == kind and x["isActive"]:
                return cid
        return None

    def live_request(self, kind, record_id):
        if record_id == 0:
            return None
        for iid in sorted(self.instances):
            i = self.instances[iid]
            if i["kind"] == kind and i["recordId"] == record_id and i["state"] == "pending":
                return iid
        return None

    def decision_of(self, iid, order):
        for d in self.decisions.values():
            if d["instanceId"] == iid and d["order"] == order:
                return d
        return None

    def record_of(self, kind, co, rid, store):
        """(requester or None, pending) from the reader that folds the kind's domain; None when there is no such
        record in the company."""
        if kind == "leave":
            x = store.hr.requests.get(rid)
            return None if x is None or x["companyId"] != co else (bytes(x["subject"]), x["state"] == "Pending")
        if kind == "expense":
            x = store.expenses.claims.get(rid)
            return None if x is None or x["companyId"] != co else (bytes(x["claimant"]), x["state"] == "submitted")
        if kind == "loan":
            x = store.compensation.loans.get(rid)
            return None if x is None or x["companyId"] != co else (bytes(x["subject"]), x["state"] == "requested")
        if kind == "offCyclePay":
            x = store.compensation.payments.get(rid)
            return None if x is None or x["companyId"] != co else (bytes(x["createdBy"]), x["state"] == "pending")
        if kind == "payrollRun":
            x = store.pay.runs.get(rid)
            return None if x is None or x["companyId"] != co else (None, x["state"] == "Computed")
        if kind == "overtime":
            x = store.pay.claims.get(rid)
            return None if x is None or x["companyId"] != co else (bytes(x["subject"]), x["state"] == "submitted")
        if kind == "purchase":
            x = store.credit.orders.get(rid)
            if x is None or x["facts"]["companyId"] != co or x["facts"]["direction"] != "purchase":
                return None
            return (None, x["state"] == "draft")
        raise ValueError("no record view for %s" % kind)

    def authority(self, i, iid, caller, day, store):
        """On whose behalf the caller decides the step the request stands at, or None."""
        self.authorities_checked += 1
        if caller == i["requester"]:
            return None
        co = i["companyId"]
        role = i["steps"][i["currentStep"] - 1]
        if store.discuss.roles.get((co, caller)) == role:
            behalf = caller
        else:
            behalf = None
            for did in sorted(self.delegations):
                d = self.delegations[did]
                if (d["companyId"] == co and d["to"] == caller and stands(d, day) and d["from"] != i["requester"]
                        and store.discuss.roles.get((co, d["from"])) == role):
                    behalf = d["from"]
                    break
            if behalf is None:
                return None
        for order in range(1, i["currentStep"]):
            d = self.decision_of(iid, order)
            if d is not None and (caller in (d["decidedBy"], d["onBehalfOf"]) or behalf in (d["decidedBy"], d["onBehalfOf"])):
                return None
        return behalf

    def write_decision(self, iid, i, by, behalf, approve, day):
        self.decisions[self.next_decision] = {"companyId": i["companyId"], "instanceId": iid, "order": i["currentStep"], "decidedBy": by,
                                              "onBehalfOf": behalf, "approve": approve, "day": day}
        self.next_decision += 1

    # -- the gate, before the domain's own reader folds the block --

    def gate(self, block, store):
        c = block["command"]
        kind, field, approving = GATED[c["family"]]
        if kind == "purchase":
            o = store.credit.orders.get(c[field])
            if o is None or o["facts"]["direction"] != "purchase":
                return
        co = c["companyId"]
        rid = c[field]
        approve = approving(c)
        caller = bytes(block["caller"])
        day = block["day"]
        self.gates_held += 1
        iid = self.live_request(kind, rid)
        if iid is None:
            if approve and self.active_cycle(co, kind) is not None:
                self.faults.append("block %d LET A DOMAIN APPROVE A %s OUTSIDE THE CHAIN ITS COMPANY KEEPS FOR IT" % (block["index"], kind.upper()))
            return
        i = self.instances[iid]
        if i["companyId"] != co:
            return
        if not approve:
            self.write_decision(iid, i, caller, caller, False, day)
            i.update(state="rejected", decidedDay=day)
            return
        behalf = self.authority(i, iid, caller, day, store) if i["currentStep"] == len(i["steps"]) else None
        if behalf is None:
            self.faults.append("block %d LET A DOMAIN APPROVE A %s BEFORE ITS LAST STEP, OR BY SOMEBODY WITHOUT ITS ROLE" % (block["index"], kind.upper()))
            return
        self.write_decision(iid, i, caller, behalf, True, day)
        i.update(state="approved", decidedDay=day)

    # -- the families --

    def apply(self, block, store):
        c = block["command"]
        f = c["family"]
        idx = block["index"]
        day = block["day"]
        caller = bytes(block["caller"])
        discuss = store.discuss

        def fault(what):
            self.faults.append("block %d %s" % (idx, what))

        def member(co):
            return co in store.companies and discuss.is_member(co, caller)

        def governor(co):
            return member(co) and discuss.roles.get((co, caller)) in GOVERNORS

        def request(co, iid):
            i = self.instances.get(iid)
            return i if i is not None and i["companyId"] == co and member(co) and i["state"] == "pending" else None

        if f == "defineApprovalCycle":
            fc = c["facts"]
            co = fc["companyId"]
            steps = fc["steps"]
            if (not governor(co) or not fc["name"] or len(fc["name"]) > MAX_TEXT or fc["kind"] not in KINDS
                    or not 1 <= len(steps) <= MAX_STEPS or any(b not in ROLE_OF_BYTE for b in steps)):
                fault("defined a cycle it could not")
                return
            kind = KINDS[fc["kind"]]
            old = self.active_cycle(co, kind)
            if old is not None:
                self.cycles[old]["isActive"] = False
            self.cycles[self.next_cycle] = {"companyId": co, "kind": kind, "steps": [ROLE_OF_BYTE[b] for b in steps], "isActive": True}
            self.next_cycle += 1
            return

        if f == "retireApprovalCycle":
            x = self.cycles.get(c["cycleId"])
            if not governor(c["companyId"]) or x is None or x["companyId"] != c["companyId"] or not x["isActive"]:
                fault("retired a cycle it could not")
                return
            x["isActive"] = False
            return

        if f == "startApproval":
            fc = c["facts"]
            co = fc["companyId"]
            kind = KINDS.get(fc["kind"])
            cid = None if kind is None else self.active_cycle(co, kind)
            if not member(co) or cid is None or len(fc["subject"]) > MAX_TEXT:
                fault("started a request it could not")
                return
            if kind in UNLINKED:
                if fc["recordId"] != 0 or not fc["subject"]:
                    fault("STARTED A REQUEST THAT IS THE CHAIN ITSELF NAMING A RECORD, OR ABOUT NOTHING")
                    return
            else:
                if fc["recordId"] == 0 or self.live_request(kind, fc["recordId"]) is not None:
                    fault("STARTED A SECOND REQUEST ABOUT A RECORD, OR ONE ABOUT NO RECORD")
                    return
                if kind in UNREAD:
                    self.records_unread += 1
                else:
                    self.records_read += 1
                    rec = self.record_of(kind, co, fc["recordId"], store)
                    if rec is None or not rec[1] or (rec[0] is not None and rec[0] != caller):
                        fault("STARTED A REQUEST ABOUT A RECORD NOT PENDING, NOT THE COMPANY'S OR NOT THE STARTER'S")
                        return
            self.instances[self.next_instance] = {"companyId": co, "cycleId": cid, "kind": kind, "recordId": fc["recordId"], "requester": caller,
                                                  "steps": list(self.cycles[cid]["steps"]), "currentStep": 1, "state": "pending", "day": day, "decidedDay": 0}
            self.next_instance += 1
            return

        if f == "decideApprovalStep":
            co = c["companyId"]
            i = request(co, c["instanceId"])
            if i is None:
                fault("decided a request that does not stand")
                return
            behalf = self.authority(i, c["instanceId"], caller, day, store)
            if behalf is None:
                fault("LET SOMEBODY DECIDE A STEP WITHOUT ITS ROLE, OR THE REQUESTER, OR SOMEBODY TWICE")
                return
            last = i["currentStep"] == len(i["steps"])
            linked = i["kind"] not in UNLINKED
            if c["approve"] and last and linked:
                fault("DECIDED HERE THE LAST STEP OF A REQUEST ABOUT ANOTHER DOMAIN'S RECORD")
                return
            if not c["approve"] and not c["note"]:
                fault("took a rejection without its reason")
                return
            if linked and i["kind"] not in UNREAD:
                rec = self.record_of(i["kind"], co, i["recordId"], store)
                if rec is None or not rec[1]:
                    fault("CARRIED ON A REQUEST WHOSE RECORD ITS DOMAIN SETTLED")
                    return
            self.write_decision(c["instanceId"], i, caller, behalf, c["approve"], day)
            if not c["approve"]:
                i.update(state="rejected", decidedDay=day)
            elif last:
                i.update(state="approved", decidedDay=day)
            else:
                i["currentStep"] += 1
            return

        if f == "withdrawApproval":
            i = request(c["companyId"], c["instanceId"])
            if i is None or i["requester"] != caller:
                fault("withdrew a request it could not")
                return
            i.update(state="withdrawn", decidedDay=day)
            return

        if f == "delegateApprovals":
            co = c["companyId"]
            to = bytes(c["delegate"])
            if not member(co) or to == caller or not discuss.is_member(co, to) or c["untilDay"] < day or c["untilDay"] - day > MAX_DELEGATION_DAYS:
                fault("TOOK A DELEGATION TO ONESELF, TO A STRANGER, OR PAST A YEAR AND A DAY")
                return
            for did in sorted(self.delegations):
                d = self.delegations[did]
                if d["companyId"] == co and d["from"] == caller and d["state"] == "active":
                    if stands(d, day):
                        fault("took a second delegation while one stands")
                        return
                    d["state"] = "lapsed"
            self.delegations[self.next_delegation] = {"companyId": co, "from": caller, "to": to, "fromDay": day, "untilDay": c["untilDay"], "state": "active"}
            self.next_delegation += 1
            return

        if f == "revokeDelegation":
            d = self.delegations.get(c["delegationId"])
            if not member(c["companyId"]) or d is None or d["companyId"] != c["companyId"] or d["from"] != caller or not stands(d, day):
                fault("revoked a delegation it could not")
                return
            d["state"] = "revoked"
            return

    # -- what the contract prints, recomputed --

    def cycle_line(self, cid):
        x = self.cycles[cid]
        return (x["companyId"], KIND_BYTE[x["kind"]], len(x["steps"]), 1 if x["isActive"] else 0)

    def instance_line(self, iid, store):
        i = self.instances[iid]
        return (i["companyId"], KIND_BYTE[i["kind"]], i["recordId"], store.discuss.membership_id(i["companyId"], i["requester"]), len(i["steps"]),
                i["currentStep"], CHAIN_STATE_BYTE[i["state"]], i["day"], i["decidedDay"])

    def decision_line(self, did, store):
        d = self.decisions[did]
        m = store.discuss.membership_id
        return (d["instanceId"], d["order"], m(d["companyId"], d["decidedBy"]), m(d["companyId"], d["onBehalfOf"]), 1 if d["approve"] else 0, d["day"])

    def delegation_line(self, did, store):
        d = self.delegations[did]
        m = store.discuss.membership_id
        return (m(d["companyId"], d["from"]), m(d["companyId"], d["to"]), d["fromDay"], d["untilDay"], DELEGATION_STATE_BYTE[d["state"]])

    def summary(self):
        return {"cycles": len(self.cycles), "requests": len(self.instances), "decisions": len(self.decisions), "delegations": len(self.delegations)}
