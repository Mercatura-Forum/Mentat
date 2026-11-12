"""The company-authority gate and the platform operator, restated for the reader: every block on the log is asked,
before any reader folds it, whether its caller could have sent it, by rules written from the design and not read off
the contract:

  * THE COMPANY AN ACT IS IN is the one its command names, directly or in its facts; for a command that names only a
    record, that record's company, which this reader tracks from the acts that made the record; none for bringing a
    company into existence and for the platform's own acts;
  * WHO MAY SEND IT is this reader's own table, family by family (HOLDERS below): the roles a member in standing must
    hold, any member in standing, the person the act is about, anyone (bringing a company into existence), a visitor
    of a company that exists, the platform operator, the claimant while no operator is named and no company exists,
    the principal a standing offer names, or the principal that began an upload;
  * A MEMBER IN STANDING is one admitted and not suspended; THE FOUNDER IS ADMITTED as the company's administrator in
    the act that brings it into existence, and this reader folds that admission itself, as every reader watching the
    memberships sees it;
  * THE PLATFORM OPERATOR is claimed once, offered by the operator - to nobody withdrawing the offer - and taken only by
    the principal offered.

A block the gate would have refused is a fault: the contract refuses such an act before its fold, so the log never
holds one, and a log that does was not written by the contract.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

from canonical import hash_with_domain, write_nat, write_text

READERS = {
    612: ("claimPlatformOperator", lambda r: {}),
    613: ("offerPlatformOperator", lambda r: {"to": r.principal() if r.bool() else None}),
    614: ("acceptPlatformOperator", lambda r: {}),
}

FAMILIES = {name for _tag, (name, _fn) in READERS.items()}


def read_gate_command(tag, r):
    family, fn = READERS[tag]
    return {"family": family, **fn(r)}


def put_tag(tag):
    if tag < 255:
        return bytes([tag])
    if tag < 510:
        return bytes([255, tag - 255])
    return bytes([255, 255]) + (tag - 510).to_bytes(2, "big")


def _offer(c):
    if c["to"] is None:
        return b"\x00"
    return b"\x01" + bytes([len(c["to"])]) + bytes(c["to"])


ENCODERS = {
    "claimPlatformOperator": (612, lambda c: b""),
    "offerPlatformOperator": (613, _offer),
    "acceptPlatformOperator": (614, lambda c: b""),
}


def gate_command_bytes(cmd):
    tag, fn = ENCODERS[cmd["family"]]
    return put_tag(tag) + fn(cmd)


# THE RECORDS A COMMAND NAMES BY ID ALONE, and the kind of record each names.
BY_RECORD = {
    "closeBranch": ("branch", "branchId"), "closeDepartment": ("department", "departmentId"),
    "retireJobTitle": ("jobTitle", "jobTitleId"), "deprecateAccount": ("account", "accountId"),
    "closeJournal": ("journal", "journalId"), "consolidationSlice": ("group", "groupId"),
    "cancelConsolidation": ("group", "groupId"),
}
PLATFORM_ACTS = {"declareStatutoryProfile", "declareTaxBracket", "retireStatutoryProfile", "declareOvertimePremiums",
                 "claimPlatformOperator", "offerPlatformOperator", "acceptPlatformOperator"}
UPLOAD_ACTS = {"putChunk", "sealUpload", "abortUpload"}


class Gate:
    def __init__(self):
        self.roles = {}            # (company, subject) -> company role
        self.suspended = set()     # (company, subject)
        self.records = {"branch": {}, "department": {}, "jobTitle": {}}
        self.next_record = {"branch": 1, "department": 1, "jobTitle": 1}
        self.operator = None
        self.offered = None
        self.staging = {}          # blob id -> the principal that began it
        self.dedup_epoch = 1
        self.checked = 0
        self.drafted_checked = 0
        self.reserved_checked = 0
        self.founders = 0

    # -- where an act is --

    def company_of(self, cmd, store):
        f = cmd["family"]
        if f in BY_RECORD:
            kind, key = BY_RECORD[f]
            rid = cmd[key]
            if kind == "account":
                a = store.ledger.accounts.get(rid)
                return None if a is None else a["companyId"]
            if kind == "journal":
                j = store.ledger.journals.get(rid)
                return None if j is None else j["companyId"]
            if kind == "group":
                g = store.consolidation.groups.get(rid)
                return None if g is None else g["companyId"]
            return self.records[kind].get(rid)
        if f == "openConsolidation":
            g = store.consolidation.groups.get(cmd["facts"]["groupId"])
            return None if g is None else g["companyId"]
        if "companyId" in cmd:
            return cmd["companyId"]
        for k in ("facts", "results"):
            if isinstance(cmd.get(k), dict) and "companyId" in cmd[k]:
                return cmd[k]["companyId"]
        raise ValueError("the reader cannot say which company a %s acts in" % f)

    def standing(self, company, p):
        key = (company, bytes(p))
        if key in self.suspended:
            return None
        return self.roles.get(key)

    # -- the rule --

    def check(self, block, store, drafted=False):
        """`drafted`: the act a draft holds, checked as its acceptor's inside the acceptance's block - counted apart
        from the blocks, so the count of blocks held is the count of blocks on the log."""
        cmd = block["command"]
        f = cmd["family"]
        caller = bytes(block["caller"])
        holders = HOLDERS.get(f)
        if holders is None:
            raise ValueError("block %d: the reader's gate names no holders for %s" % (block["index"], f))
        kind = holders[0]
        held = None
        if drafted:
            self.drafted_checked += 1
        else:
            self.checked += 1
        if kind == "founder":
            return
        if kind == "claim":
            ok = self.operator is None and not store.companies
        elif kind == "platform":
            ok = self.operator == caller
        elif kind == "offered":
            ok = self.offered is not None and self.offered == caller
        elif kind == "uploader":
            blob = cmd["facts"]["blobId"] if f == "putChunk" else cmd["blobId"]
            ok = self.staging.get(blob) == caller
        else:
            co = None if f in PLATFORM_ACTS else self.company_of(cmd, store)
            held = None if co is None else self.standing(co, caller)
            if kind == "visitor":
                ok = co is not None and co in store.companies
            elif kind == "member":
                # THE AUDITOR HOLDS NO ACT: a member in standing acts as a member, the read-only role does not
                ok = held is not None and held not in NO_ACT
            elif kind == "roles":
                ok = held in holders[1]
            elif kind == "self":
                subject = cmd.get("subject")
                ok = (held is not None and held not in NO_ACT and subject is not None and bytes(subject) == caller) or held in holders[1]
            else:
                raise ValueError("holders of an unknown kind: %r" % (holders,))
        if not ok:
            raise ValueError("block %d: %s from a caller the gate refuses (holders %s; the caller holds %s)"
                             % (block["index"], f, holders[0], held or "no role in standing"))
        # THE ROLES ONLY AN ADMINISTRATOR MOVES: its own and the auditor's, granted, changed, suspended or restored by
        # an administrator in standing and nobody else (HrFold, onlyAnAdministrator)
        if f in RESERVED_ACTS:
            co = cmd["companyId"]
            now = self.roles.get((co, bytes(cmd["subject"])))
            moves = {cmd.get("companyRole"), now} if f == "setMemberRole" else ({cmd["companyRole"]} if f == "admitMember" else {now})
            if moves & RESERVED_ROLES and self.standing(co, caller) != "CompanyAdmin":
                raise ValueError("block %d: %s moved an administrator's or auditor's role by a caller who is not an administrator" % (block["index"], f))
            self.reserved_checked += 1

    # -- what the acts leave behind --

    def after(self, block, store):
        cmd = block["command"]
        f = cmd["family"]
        caller = bytes(block["caller"])
        if f == "admitMember":
            self.roles[(cmd["companyId"], bytes(cmd["subject"]))] = cmd["companyRole"]
        elif f == "setMemberRole":
            self.roles[(cmd["companyId"], bytes(cmd["subject"]))] = cmd["companyRole"]
        elif f == "suspendMember":
            self.suspended.add((cmd["companyId"], bytes(cmd["subject"])))
        elif f == "reinstateMember":
            self.suspended.discard((cmd["companyId"], bytes(cmd["subject"])))
        elif f in ("createBranch", "createDepartment", "declareJobTitle"):
            kind = {"createBranch": "branch", "createDepartment": "department", "declareJobTitle": "jobTitle"}[f]
            self.records[kind][self.next_record[kind]] = cmd["facts"]["companyId"]
            self.next_record[kind] += 1
        elif f == "claimPlatformOperator":
            self.operator, self.offered = caller, None
        elif f == "offerPlatformOperator":
            self.offered = None if cmd["to"] is None else bytes(cmd["to"])
        elif f == "acceptPlatformOperator":
            self.operator, self.offered = caller, None
        elif f == "beginUpload":
            facts = cmd["facts"]
            payload = write_nat(self.dedup_epoch) + write_nat(facts["size"]) + len(facts["chunkHashes"]).to_bytes(2, "big")
            payload += b"".join(write_text(h) for h in facts["chunkHashes"])
            self.staging[hash_with_domain("THEBES-EVIDENCE-BLOB-v1", payload).hex()] = caller
        elif f in ("sealUpload", "abortUpload"):
            self.staging.pop(cmd["blobId"], None)
        elif f == "eraseDocument":
            self.dedup_epoch += 1

    def founder(self, block, company):
        """THE FOUNDER'S ADMISSION, which the contract writes in the act that brings the company into existence:
        the command every reader watching the memberships folds for it."""
        self.founders += 1
        return {**block, "command": {"family": "admitMember", "companyId": company, "subject": bytes(block["caller"]),
                                     "companyRole": "CompanyAdmin", "platformRole": "None", "managerId": 0}}

    def summary(self):
        return {"blocks_checked": self.checked, "drafted_checked": self.drafted_checked, "founders_admitted": self.founders, "reserved_checked": self.reserved_checked,
                "operator_named": 0 if self.operator is None else 1}


# THE ROLES ONLY AN ADMINISTRATOR MOVES, and the acts that move a membership's role or standing.
RESERVED_ACTS = {"admitMember", "setMemberRole", "suspendMember", "reinstateMember"}
RESERVED_ROLES = {"CompanyAdmin", "Auditor", "Drafter"}
# the roles that hold no act at the gate: the auditor, which reads, and the drafter, which only proposes drafts
NO_ACT = {"Auditor", "Drafter"}

# WHO MAY SEND EACH ACT: this reader's own table, family by family.

HOLDERS = {
    'bootstrapCompany': ('founder',),
    'amendCompany': ('roles', ('CompanyAdmin',)),
    'createBranch': ('roles', ('CompanyAdmin', 'HR')),
    'amendBranch': ('roles', ('CompanyAdmin', 'HR')),
    'closeBranch': ('roles', ('CompanyAdmin', 'HR')),
    'createDepartment': ('roles', ('CompanyAdmin', 'HR')),
    'amendDepartment': ('roles', ('CompanyAdmin', 'HR')),
    'closeDepartment': ('roles', ('CompanyAdmin', 'HR')),
    'declareJobTitle': ('roles', ('CompanyAdmin', 'HR')),
    'amendJobTitle': ('roles', ('CompanyAdmin', 'HR')),
    'retireJobTitle': ('roles', ('CompanyAdmin', 'HR')),
    'admitMember': ('roles', ('CompanyAdmin', 'HR')),
    'setMemberRole': ('roles', ('CompanyAdmin', 'HR')),
    'setManagers': ('roles', ('CompanyAdmin', 'HR')),
    'suspendMember': ('roles', ('CompanyAdmin', 'HR')),
    'reinstateMember': ('roles', ('CompanyAdmin', 'HR')),
    'registerEmployee': ('roles', ('CompanyAdmin', 'HR')),
    'amendEmployeeDetails': ('self', ('CompanyAdmin', 'HR')),
    'amendEmployeeStanding': ('roles', ('CompanyAdmin', 'HR')),
    'punchIn': ('self', ('CompanyAdmin', 'HR', 'Manager')),
    'punchOut': ('self', ('CompanyAdmin', 'HR', 'Manager')),
    'requestPunchCorrection': ('self', ('CompanyAdmin', 'HR', 'Manager')),
    'decidePunchCorrection': ('roles', ('CompanyAdmin', 'HR', 'Manager')),
    'requestLeave': ('self', ('CompanyAdmin', 'HR', 'Manager')),
    'decideLeave': ('roles', ('CompanyAdmin', 'HR', 'Manager')),
    'withdrawLeave': ('member',),
    'adjustLeaveBalance': ('roles', ('CompanyAdmin', 'HR')),
    'accrueLeave': ('roles', ('CompanyAdmin', 'HR')),
    'declareStatutoryProfile': ('platform',),
    'declareTaxBracket': ('platform',),
    'retireStatutoryProfile': ('platform',),
    'setCompensation': ('roles', ('CompanyAdmin', 'HR')),
    'openPayrollRun': ('roles', ('CompanyAdmin', 'HR', 'Director')),
    'runPayrollSlice': ('member',),
    'closePayrollRun': ('roles', ('CompanyAdmin', 'HR', 'Director')),
    'approvePayrollRun': ('roles', ('CompanyAdmin', 'HR', 'Director')),
    'postPayrollJournal': ('roles', ('CompanyAdmin', 'HR', 'Director')),
    'abandonPayrollRun': ('roles', ('CompanyAdmin', 'HR', 'Director')),
    'createAccount': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'amendAccount': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'deprecateAccount': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'createJournal': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'amendJournal': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'closeJournal': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'proposeMove': ('member',),
    'postMove': ('member',),
    'cancelMove': ('member',),
    'lockPeriod': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'createPartner': ('member',),
    'amendPartner': ('member',),
    'createCategory': ('member',),
    'amendCategory': ('member',),
    'placeOrder': ('member',),
    'amendOrder': ('member',),
    'confirmOrder': ('member',),
    'cancelOrder': ('member',),
    'issueInvoice': ('member',),
    'createWarehouse': ('member',),
    'createLocation': ('member',),
    'createLot': ('member',),
    'setCosting': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'createPicking': ('member',),
    'cancelPicking': ('member',),
    'validatePicking': ('member',),
    'declareBom': ('member',),
    'retireBom': ('member',),
    'planProduction': ('member',),
    'confirmProduction': ('member',),
    'produce': ('member',),
    'closeProductionShort': ('member',),
    'cancelProduction': ('member',),
    'explodeRequirements': ('member',),
    'createProject': ('member',),
    'amendProject': ('member',),
    'setProjectState': ('member',),
    'createTask': ('member',),
    'amendTask': ('member',),
    'setTaskState': ('member',),
    'logTime': ('member',),
    'voidTimeEntry': ('member',),
    'submitTimesheet': ('member',),
    'decideTimesheet': ('member',),
    'createLead': ('member',),
    'amendLead': ('member',),
    'setLeadStage': ('member',),
    'convertLead': ('member',),
    'setLeadWon': ('member',),
    'setLeadLost': ('member',),
    'restoreLead': ('member',),
    'archiveLead': ('member',),
    'createStage': ('member',),
    'amendStage': ('member',),
    'archiveStage': ('member',),
    'createActivity': ('member',),
    'amendActivity': ('member',),
    'completeActivity': ('member',),
    'archiveActivity': ('member',),
    'openReminderSweep': ('member',),
    'sweepReminderSlice': ('member',),
    'suppressAddress': ('member',),
    'releaseAddress': ('member',),
    'createMailing': ('member',),
    'amendMailing': ('member',),
    'launchMailing': ('member',),
    'planMailingSlice': ('member',),
    'claimMailingSlice': ('member',),
    'recordMailingResults': ('member',),
    'cancelMailing': ('member',),
    'createScoringRule': ('member',),
    'amendScoringRule': ('member',),
    'retireScoringRule': ('member',),
    'openScoringRun': ('member',),
    'scoreSlice': ('member',),
    'registerDevice': ('member',),
    'revokeDevice': ('member',),
    'openRing': ('member',),
    'rotateRing': ('member',),
    'shareRing': ('member',),
    'beginUpload': ('member',),
    'putChunk': ('uploader',),
    'sealUpload': ('uploader',),
    'abortUpload': ('uploader',),
    'registerDocument': ('member',),
    'amendDocument': ('member',),
    'archiveDocument': ('member',),
    'eraseDocument': ('member',),
    'openDocumentExpirySweep': ('member',),
    'sweepDocumentExpirySlice': ('member',),
    'registerSigningKey': ('member',),
    'revokeSigningKey': ('member',),
    'createSignatureRequest': ('member',),
    'revokeSignatureRequest': ('member',),
    'beginSignature': ('member',),
    'completeSignature': ('member',),
    'completeSignaturePq': ('member',),
    'declineSignature': ('member',),
    'createCurrency': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'amendCurrency': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'retireCurrency': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'recordRate': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'createTax': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'amendTax': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'retireTax': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'importBankStatement': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'addStatementLine': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'confirmBankStatement': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'archiveBankStatement': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'reconcileLine': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'unreconcileLine': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'openMatchRun': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'matchSlice': ('member',),
    'configureEtaEndpoint': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'prepareEtaFiling': ('member',),
    'recordEtaSubmission': ('member',),
    'recordEtaResult': ('member',),
    'abandonEtaFiling': ('member',),
    'openPlan': ('member',),
    'addPlanItem': ('member',),
    'setPlanItemState': ('member',),
    'closePlan': ('member',),
    'createContract': ('member',),
    'amendContract': ('member',),
    'setContractState': ('member',),
    'openProbation': ('member',),
    'addProbationCheckIn': ('member',),
    'finalizeProbation': ('member',),
    'requestRelocation': ('member',),
    'decideRelocation': ('member',),
    'setRelocationState': ('member',),
    'addRelocationExpense': ('member',),
    'addWorkHistoryItem': ('member',),
    'addFamilyMember': ('member',),
    'removeFamilyMember': ('member',),
    'createHeadcountPlan': ('member',),
    'addFteEntry': ('member',),
    'setHeadcountState': ('member',),
    'declareKeyPosition': ('roles', ('CompanyAdmin', 'HR')),
    'upsertSuccessor': ('roles', ('CompanyAdmin', 'HR')),
    'removeSuccessor': ('roles', ('CompanyAdmin', 'HR')),
    'createCustomField': ('roles', ('CompanyAdmin', 'HR')),
    'amendCustomField': ('roles', ('CompanyAdmin', 'HR')),
    'retireCustomField': ('roles', ('CompanyAdmin', 'HR')),
    'setCustomFieldValue': ('roles', ('CompanyAdmin', 'HR')),
    'openDisciplinaryCase': ('member',),
    'acknowledgeDisciplinaryCase': ('member',),
    'resolveDisciplinaryCase': ('member',),
    'openWarningExpirySweep': ('member',),
    'sweepWarningExpirySlice': ('member',),
    'submitGrievance': ('member',),
    'setGrievanceState': ('member',),
    'withdrawGrievance': ('member',),
    'reportIncident': ('member',),
    'assignIncident': ('member',),
    'setIncidentState': ('member',),
    'addInvestigationNote': ('member',),
    'addMilestone': ('member',),
    'amendMilestone': ('member',),
    'setMilestoneState': ('member',),
    'setEmployeeAssignment': ('roles', ('CompanyAdmin', 'HR')),
    'addPendingEmployee': ('roles', ('CompanyAdmin', 'HR')),
    'decidePendingEmployee': ('roles', ('CompanyAdmin', 'HR')),
    'openImportRun': ('roles', ('CompanyAdmin', 'HR')),
    'importSlice': ('member',),
    'createShiftTemplate': ('roles', ('CompanyAdmin', 'HR')),
    'setShiftTemplateActive': ('roles', ('CompanyAdmin', 'HR')),
    'assignShift': ('member',),
    'cancelShiftAssignment': ('member',),
    'requestShiftSwap': ('member',),
    'answerSwapRequest': ('member',),
    'decideShiftSwap': ('member',),
    'createBreakType': ('roles', ('CompanyAdmin', 'HR')),
    'setBreakTypeActive': ('roles', ('CompanyAdmin', 'HR')),
    'startBreak': ('member',),
    'endBreak': ('member',),
    'claimOvertime': ('member',),
    'submitOvertime': ('member',),
    'cancelOvertime': ('member',),
    'decideOvertime': ('member',),
    'requestCompTimeUse': ('member',),
    'decideCompTimeUse': ('member',),
    'createCompanyHoliday': ('roles', ('CompanyAdmin', 'HR')),
    'amendCompanyHoliday': ('roles', ('CompanyAdmin', 'HR')),
    'withdrawCompanyHoliday': ('roles', ('CompanyAdmin', 'HR')),
    'requestWorkFromHome': ('member',),
    'decideWorkFromHome': ('member',),
    'cancelWorkFromHome': ('member',),
    'setWorkingHours': ('roles', ('CompanyAdmin', 'HR')),
    'setAttendancePolicy': ('roles', ('CompanyAdmin', 'HR')),
    'setLateDeductionTiers': ('roles', ('CompanyAdmin', 'HR')),
    'registerAttendanceDevice': ('roles', ('CompanyAdmin', 'HR')),
    'amendAttendanceDevice': ('roles', ('CompanyAdmin', 'HR')),
    'revokeAttendanceDevice': ('roles', ('CompanyAdmin', 'HR')),
    'ingestDeviceBatch': ('visitor',),
    'enrolFaceTemplate': ('member',),
    'withdrawFaceTemplate': ('member',),
    'createReportSchedule': ('roles', ('CompanyAdmin', 'HR')),
    'setReportScheduleActive': ('roles', ('CompanyAdmin', 'HR')),
    'openReportRun': ('member',),
    'runReportSlice': ('member',),
    'declareOvertimePremiums': ('platform',),
    'createJobPosting': ('roles', ('CompanyAdmin', 'HR')),
    'amendJobPosting': ('roles', ('CompanyAdmin', 'HR')),
    'setPostingState': ('roles', ('CompanyAdmin', 'HR')),
    'setCareersPolicy': ('roles', ('CompanyAdmin', 'HR')),
    'submitPublicApplication': ('visitor',),
    'eraseApplication': ('member',),
    'applyToPosting': ('member',),
    'reviewApplication': ('member',),
    'withdrawApplication': ('member',),
    'addCandidate': ('member',),
    'setCandidateStage': ('member',),
    'addCandidateNote': ('member',),
    'eraseCandidate': ('member',),
    'createRequisition': ('member',),
    'amendRequisition': ('member',),
    'submitRequisition': ('member',),
    'decideRequisition': ('member',),
    'setRequisitionState': ('member',),
    'createOffer': ('member',),
    'sendOffer': ('member',),
    'respondToOffer': ('visitor',),
    'rescindOffer': ('member',),
    'submitCounterOffer': ('visitor',),
    'decideCounterOffer': ('member',),
    'contractFromOffer': ('member',),
    'openOfferExpirySweep': ('member',),
    'sweepOfferExpirySlice': ('member',),
    'scheduleInterview': ('member',),
    'setInterviewState': ('member',),
    'submitScorecard': ('member',),
    'makeHiringDecision': ('member',),
    'submitReferral': ('member',),
    'setReferralState': ('member',),
    'withdrawReferral': ('member',),
    'payReferralReward': ('member',),
    'recordCheckConsent': ('member',),
    'createBackgroundCheck': ('member',),
    'recordCheckResult': ('member',),
    'cancelBackgroundCheck': ('member',),
    'openCheckRetentionSweep': ('member',),
    'sweepCheckRetentionSlice': ('member',),
    'createExitInterview': ('member',),
    'submitExitInterview': ('member',),
    'acknowledgeExitInterview': ('member',),
    'setTalentAssessment': ('member',),
    'assignReceiptToOrder': ('member',),
    'recordSupplierBill': ('member',),
    'matchSupplierBill': ('member',),
    'issueCreditNote': ('member',),
    'setIssuerProfile': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'setPartnerAddress': ('member',),
    'setCategoryTaxProfile': ('member',),
    'prepareEtaCreditNote': ('member',),
    'sealEtaFiling': ('member',),
    'nameSigners': ('member',),
    'expireSignatureRequest': ('member',),
    'createSegment': ('member',),
    'amendSegment': ('member',),
    'archiveSegment': ('member',),
    'createCampaign': ('member',),
    'amendCampaign': ('member',),
    'launchCampaign': ('member',),
    'planCampaignSlice': ('member',),
    'decideCampaignWinner': ('member',),
    'planRemainderSlice': ('member',),
    'completeCampaign': ('member',),
    'cancelCampaign': ('member',),
    'recordEngagement': ('member',),
    'beginClose': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'planCloseSlice': ('member',),
    'cancelClose': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'closePeriod': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'reopenClose': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'reverseCloseSlice': ('member',),
    'openStatement': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'statementSlice': ('member',),
    'cancelStatement': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'declareDeferral': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'cancelDeferral': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'openDeferralRun': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'deferralRunSlice': ('member',),
    'setRevaluationPolicy': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'revalueCloseSlice': ('member',),
    'capitaliseAsset': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'impairAsset': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'disposeAsset': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'postAssetEvent': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'cancelAssetEvent': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'openDepreciationRun': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'depreciationRunSlice': ('member',),
    'declareExpenseCategory': ('member',),
    'setExpenseRate': ('member',),
    'setExpensePolicy': ('member',),
    'fileExpenseClaim': ('member',),
    'withdrawExpenseClaim': ('member',),
    'rejectExpenseClaim': ('member',),
    'approveExpenseClaim': ('member',),
    'settleExpenseClaim': ('member',),
    'registerBankAccount': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'setPartnerBankAccount': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'preparePayment': ('member',),
    'recordPaymentSubmission': ('member',),
    'recordPaymentResult': ('member',),
    'cancelPayment': ('member',),
    'importCamt053': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'setCreditTerms': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'openInterestRun': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'interestRunSlice': ('member',),
    'declareGroup': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'addGroupMember': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'removeGroupMember': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'linkIntercompanyPartner': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'unlinkIntercompanyPartner': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'openConsolidation': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'consolidationSlice': ('member',),
    'cancelConsolidation': ('roles', ('CompanyAdmin', 'Director', 'Manager')),
    'declareEquipment': ('member',),
    'retireEquipment': ('member',),
    'declareMaintenancePlan': ('member',),
    'cancelMaintenancePlan': ('member',),
    'openMaintenanceRun': ('member',),
    'maintenanceRunSlice': ('member',),
    'requestRepair': ('member',),
    'completeWorkOrder': ('member',),
    'cancelWorkOrder': ('member',),
    'declareControlPoint': ('member',),
    'retireControlPoint': ('member',),
    'recordQualityCheck': ('member',),
    'decideDisposition': ('member',),
    'declareHelpdeskTeam': ('member',),
    'retireHelpdeskTeam': ('member',),
    'declareTicketStage': ('member',),
    'setServiceLevel': ('member',),
    'openTicket': ('member',),
    'assignTicket': ('member',),
    'moveTicket': ('member',),
    'postTicketMessage': ('member',),
    'openEscalationSweep': ('member',),
    'escalationSweepSlice': ('member',),
    'setServiceRate': ('member',),
    'planVisit': ('member',),
    'cancelVisit': ('member',),
    'completeVisit': ('member',),
    'invoiceVisit': ('member',),
    'declareBookableResource': ('member',),
    'retireBookableResource': ('member',),
    'bookResource': ('member',),
    'cancelBooking': ('member',),
    'openSubscription': ('member',),
    'changeSubscription': ('member',),
    'closeSubscription': ('member',),
    'openSubscriptionRun': ('member',),
    'subscriptionRunSlice': ('member',),
    'declareRentalItem': ('member',),
    'retireRentalItem': ('member',),
    'reserveRental': ('member',),
    'cancelRental': ('member',),
    'pickUpRental': ('member',),
    'returnRental': ('member',),
    'declareShop': ('member',),
    'retireShop': ('member',),
    'setShopPrice': ('member',),
    'withdrawShopPrice': ('member',),
    'openTillSession': ('member',),
    'ringUpSale': ('member',),
    'closeTillSession': ('member',),
    'postTillSession': ('member',),
    'declareTable': ('member',),
    'retireTable': ('member',),
    'openTab': ('member',),
    'orderCourse': ('member',),
    'voidTabLine': ('member',),
    'sendCourse': ('member',),
    'cancelTab': ('member',),
    'settleTab': ('member',),
    'openStorefront': ('member',),
    'closeStorefront': ('member',),
    'listOnline': ('member',),
    'delist': ('member',),
    'addToCart': ('visitor',),
    'removeFromCart': ('visitor',),
    'abandonCart': ('visitor',),
    'checkout': ('visitor',),
    'fulfilWebOrder': ('member',),
    'cancelWebOrder': ('visitor',),
    'publishPage': ('member',),
    'unpublishPage': ('member',),
    'publishPost': ('member',),
    'revisePost': ('member',),
    'withdrawPost': ('member',),
    'declareBoard': ('member',),
    'openTopic': ('member',),
    'replyToTopic': ('member',),
    'moderate': ('member',),
    'enrolOperator': ('member',),
    'withdrawOperator': ('member',),
    'openConversation': ('visitor',),
    'takeConversation': ('member',),
    'transferConversation': ('member',),
    'sendChatMessage': ('visitor',),
    'closeConversation': ('visitor',),
    'rateConversation': ('visitor',),
    'declareWorkflow': ('member',),
    'addWorkflowStep': ('member',),
    'activateWorkflow': ('member',),
    'closeWorkflow': ('member',),
    'openEnrolmentRun': ('member',),
    'enrolmentSlice': ('member',),
    'openStepRun': ('member',),
    'stepSlice': ('member',),
    'createSmsMailing': ('member',),
    'amendSmsMailing': ('member',),
    'launchSmsMailing': ('member',),
    'planSmsSlice': ('member',),
    'claimSmsSlice': ('member',),
    'recordSmsResults': ('member',),
    'recordSmsReplies': ('member',),
    'cancelSmsMailing': ('member',),
    'suppressNumber': ('member',),
    'releaseNumber': ('member',),
    'connectSocialAccount': ('member',),
    'disconnectSocialAccount': ('member',),
    'schedulePost': ('member',),
    'amendPost': ('member',),
    'cancelPost': ('member',),
    'claimPost': ('member',),
    'recordPostResult': ('member',),
    'announceEvent': ('member',),
    'amendEvent': ('member',),
    'cancelEvent': ('member',),
    'sellTickets': ('member',),
    'recordAttendance': ('member',),
    'closeEvent': ('member',),
    'openSurvey': ('member',),
    'addSurveyQuestion': ('member',),
    'respondToSurvey': ('member',),
    'closeSurvey': ('member',),
    'openReviewCycle': ('member',),
    'enrolReviewSlice': ('member',),
    'submitSelfReview': ('member',),
    'submitManagerReview': ('member',),
    'startCalibration': ('member',),
    'calibrateReview': ('member',),
    'closeReviewCycle': ('member',),
    'setGoal': ('member',),
    'addKeyResult': ('member',),
    'updateKeyResult': ('member',),
    'closeGoal': ('member',),
    'giveRecognition': ('member',),
    'createCourse': ('member',),
    'retireCourse': ('member',),
    'createLearningPath': ('member',),
    'retireLearningPath': ('member',),
    'enrolInCourse': ('member',),
    'updateCourseProgress': ('member',),
    'dropEnrolment': ('member',),
    'recordCertification': ('member',),
    'renewCertification': ('member',),
    'revokeCertification': ('member',),
    'declareSkill': ('member',),
    'removeSkill': ('member',),
    'endorseSkill': ('member',),
    'rateSkill': ('member',),
    'offerMentoring': ('member',),
    'requestMentorship': ('member',),
    'respondMentorship': ('member',),
    'logMentoringSession': ('member',),
    'completeMentorship': ('member',),
    'setCompensationPolicy': ('roles', ('CompanyAdmin', 'HR')),
    'declarePayBand': ('roles', ('CompanyAdmin', 'HR')),
    'amendPayBand': ('roles', ('CompanyAdmin', 'HR')),
    'retirePayBand': ('roles', ('CompanyAdmin', 'HR')),
    'proposeSalaryReview': ('member',),
    'decideSalaryReview': ('member',),
    'implementSalaryReview': ('member',),
    'withdrawSalaryReview': ('member',),
    'grantEquity': ('member',),
    'vestEquity': ('member',),
    'exerciseEquity': ('member',),
    'cancelEquityGrant': ('member',),
    'createIncentivePlan': ('roles', ('CompanyAdmin', 'HR')),
    'retireIncentivePlan': ('roles', ('CompanyAdmin', 'HR')),
    'scoreIncentive': ('member',),
    'createOffCyclePayment': ('member',),
    'approveOffCyclePayment': ('member',),
    'rejectOffCyclePayment': ('member',),
    'cancelOffCyclePayment': ('member',),
    'requestLoan': ('member',),
    'withdrawLoan': ('member',),
    'decideLoan': ('member',),
    'disburseLoan': ('member',),
    'recordLoanRepayment': ('member',),
    'createBenefitPlan': ('roles', ('CompanyAdmin', 'HR')),
    'toggleBenefitPlan': ('roles', ('CompanyAdmin', 'HR')),
    'openEnrolmentPeriod': ('roles', ('CompanyAdmin', 'HR')),
    'enrolInBenefit': ('member',),
    'waiveBenefit': ('member',),
    'setFleetPolicy': ('member',),
    'registerVehicle': ('member',),
    'retireVehicle': ('member',),
    'assignDriver': ('member',),
    'releaseDriver': ('member',),
    'addVehicleContract': ('member',),
    'cancelVehicleContract': ('member',),
    'logOdometer': ('member',),
    'logFuel': ('member',),
    'logVehicleCost': ('member',),
    'postVehicleCost': ('member',),
    'rejectVehicleCost': ('member',),
    'createChannel': ('member',),
    'archiveChannel': ('member',),
    'joinChannel': ('member',),
    'addChannelMember': ('member',),
    'leaveChannel': ('member',),
    'removeChannelMember': ('member',),
    'sendChannelMessage': ('member',),
    'deleteChannelMessage': ('member',),
    'markChannelRead': ('member',),
    'createAnnouncement': ('member',),
    'amendAnnouncement': ('member',),
    'pinAnnouncement': ('member',),
    'withdrawAnnouncement': ('member',),
    'toggleReaction': ('member',),
    'openAnnouncementSweep': ('member',),
    'sweepAnnouncementSlice': ('member',),
    'createNotification': ('member',),
    'markNotificationRead': ('member',),
    'markAllNotificationsRead': ('member',),
    'dismissNotification': ('member',),
    'createKbArticle': ('member',),
    'reviseKbArticle': ('member',),
    'publishKbVersion': ('member',),
    'archiveKbArticle': ('member',),
    'recordKbView': ('member',),
    'voteKbArticle': ('member',),
    'createPolicy': ('member',),
    'revisePolicy': ('member',),
    'publishPolicyVersion': ('member',),
    'archivePolicy': ('member',),
    'acknowledgePolicy': ('member',),
    'defineRequirement': ('member',),
    'retireRequirement': ('member',),
    'citeCertification': ('member',),
    'setDashboardLayout': ('member',),
    'openFiguresRun': ('member',),
    'runFiguresSlice': ('member',),
    'defineApprovalCycle': ('member',),
    'retireApprovalCycle': ('member',),
    'startApproval': ('member',),
    'decideApprovalStep': ('member',),
    'withdrawApproval': ('member',),
    'delegateApprovals': ('member',),
    'revokeDelegation': ('member',),
    'defineStudioField': ('roles', ('CompanyAdmin',)),
    'amendStudioField': ('roles', ('CompanyAdmin',)),
    'retireStudioField': ('roles', ('CompanyAdmin',)),
    'setStudioRule': ('roles', ('CompanyAdmin',)),
    'setStudioValue': ('member',),
    'clearStudioValue': ('member',),
    'setControlProfile': ('member',),
    'openScreening': ('member',),
    'screenSlice': ('member',),
    'concludeFinding': ('member',),
    'defineControlProcedure': ('member',),
    'prepareControlConclusion': ('member',),
    'reviewControlConclusion': ('member',),
    'logCall': ('member',),
    'attachCallRecording': ('member',),
    'proposeBomChange': ('member',),
    'approveBomChange': ('member',),
    'rejectBomChange': ('member',),
    'withdrawBomChange': ('member',),
    'claimPlatformOperator': ('claim',),
    'offerPlatformOperator': ('platform',),
    'acceptPlatformOperator': ('offered',),
    'recordGwpSet': ('member',),
    'approveGwpSet': ('member',),
    'recordEsgFactor': ('member',),
    'approveEsgFactor': ('member',),
    'setEsgRule': ('member',),
    'retireEsgRule': ('member',),
    'recordEsgActivity': ('member',),
    'cancelEsgActivity': ('member',),
    'openEsgRun': ('member',),
    'esgRunSlice': ('member',),
    'proposeDraft': ('roles', ('CompanyAdmin', 'HR', 'Director', 'Manager', 'Employee', 'Drafter')),
    'acceptDraft': ('member',),
    'rejectDraft': ('roles', ('CompanyAdmin', 'HR', 'Director', 'Manager', 'Employee', 'Drafter')),
    'markIdeaBoard': ('roles', ('CompanyAdmin', 'HR')),
    'voteTopic': ('member',),
    'setIdeaStatus': ('roles', ('CompanyAdmin', 'HR', 'Director', 'Manager')),
    'respondToEvent': ('member',),
    'assignEquipment': ('member',),
    'returnEquipment': ('member',),
}
