/// Catalogue.mo - Mentat's permission catalogue: every act, what it guards, and whether one person
/// may do it alone.
///
/// The catalogue is a **table**, not a set of `if` statements, for one reason: a table can be
/// checked in both directions. `Permissions.validate` refuses a build where a command has no
/// permission and a build where a permission names a command that does not exist. The received
/// tree has neither direction - 83 of `erp.mo`'s 84 update methods gate on
/// `isPlatformAdmin(msg.caller)` and nothing else, and `grep -ciE "maker|checker|four-eyes"` over
/// that file returns 0.
///
/// The kernel's rule, carried: anything that moves money or a person's record is dual by default,
/// and `Permissions.validate` refuses a row where it is not. A company being brought into
/// existence is a record-moving act - it is the root every other record hangs from - so
/// `bootstrapCompany` is dual, and the battery proves a single authority cannot perform it.
///
/// Attribution: Thebes Core Team. Licence: Apache 2.0.

import P "mo:kernel/auth/Permissions";
import T "mo:kernel/auth/AuthTypes";

import Cmd "Command";

module {

  /// A module `let` must be static, and `P.p` is a call - so the rows are written out. The field
  /// names are what a reader checks, not the order.
  public let catalogue : P.Catalogue = [
    {
      id = "company.bootstrap";
      resource = "company";
      action = #create;
      guards = #command("bootstrapCompany");
      moneyMoving = false;
      /// the root record every other record of a tenant hangs from
      recordMoving = true;
      dualByDefault = true;
    },
    { id = "company.amend"; resource = "company"; action = #update; guards = #command("amendCompany");
      moneyMoving = false; recordMoving = true; dualByDefault = true },

    // ── the platform operator ─────────────────────────────────────────────────
    // The operator is no company's record and moves no money. The hand-over is two acts by two principals - 
    // the operator offers, the principal offered accepts - so the role never moves on one signature.
    { id = "platform.claim"; resource = "platform"; action = #create; guards = #command("claimPlatformOperator");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "platform.offer"; resource = "platform"; action = #update; guards = #command("offerPlatformOperator");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "platform.accept"; resource = "platform"; action = #approve; guards = #command("acceptPlatformOperator");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── structure ─────────────────────────────────────────────────────────────
    // A branch, a department and a job title are not a person's record and do not move money, so
    // one entitled administrator may declare one. What they DO bear on is a person's standing - 
    // a job title carries a seniority - so amending or retiring one is dual: retiring the title
    // every senior engineer holds changes what those people are, without touching their records.
    { id = "branch.create"; resource = "branch"; action = #create; guards = #command("createBranch");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "branch.amend"; resource = "branch"; action = #update; guards = #command("amendBranch");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "branch.close"; resource = "branch"; action = #close; guards = #command("closeBranch");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "department.create"; resource = "department"; action = #create; guards = #command("createDepartment");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "department.amend"; resource = "department"; action = #update; guards = #command("amendDepartment");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "department.close"; resource = "department"; action = #close; guards = #command("closeDepartment");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "jobTitle.declare"; resource = "jobTitle"; action = #create; guards = #command("declareJobTitle");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "jobTitle.amend"; resource = "jobTitle"; action = #update; guards = #command("amendJobTitle");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "jobTitle.retire"; resource = "jobTitle"; action = #close; guards = #command("retireJobTitle");
      moneyMoving = false; recordMoving = true; dualByDefault = true },

    // ── people ────────────────────────────────────────────────────────────────
    // Everything that changes what a person IS in the company is record-moving and therefore dual:
    // admission, role, manager, suspension, reinstatement, registration, and the standing half of
    // the person record. The kernel refuses a catalogue where a record-moving row is not dual.
    { id = "member.admit"; resource = "membership"; action = #create; guards = #command("admitMember");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "member.setRole"; resource = "membership"; action = #update; guards = #command("setMemberRole");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "member.setManager"; resource = "membership"; action = #update; guards = #command("setManagers");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "member.suspend"; resource = "membership"; action = #close; guards = #command("suspendMember");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "member.reinstate"; resource = "membership"; action = #activate; guards = #command("reinstateMember");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "employee.register"; resource = "employee"; action = #create; guards = #command("registerEmployee");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // The one exception, and it is the point of splitting the received `updateUserProfile` in two:
    // a person changing their own telephone number, language or notification preference is not a
    // record-moving act, and requiring a second person for it would make the control meaningless by
    // making it constant. What this command CANNOT touch is department, title, manager, seniority
    // or status - those are `amendEmployeeStanding`, which is dual.
    { id = "employee.amendDetails"; resource = "employee"; action = #update; guards = #command("amendEmployeeDetails");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "employee.amendStanding"; resource = "employee"; action = #update; guards = #command("amendEmployeeStanding");
      moneyMoving = false; recordMoving = true; dualByDefault = true },

    // ── the working day ───────────────────────────────────────────────────────
    // A punch is a person recording their own attendance and is single-authority; a CORRECTION to
    // one is a change to the record that pay is computed from, and is dual. That is the line the
    // received tree does not draw: `updateAttendanceRecord` is one method with one role check.
    { id = "attendance.punchIn"; resource = "attendance"; action = #create; guards = #command("punchIn");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "attendance.punchOut"; resource = "attendance"; action = #update; guards = #command("punchOut");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "attendance.requestCorrection"; resource = "attendance"; action = #create; guards = #command("requestPunchCorrection");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "attendance.decideCorrection"; resource = "attendance"; action = #approve; guards = #command("decidePunchCorrection");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "leave.request"; resource = "leave"; action = #create; guards = #command("requestLeave");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "leave.decide"; resource = "leave"; action = #approve; guards = #command("decideLeave");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "leave.withdraw"; resource = "leave"; action = #close; guards = #command("withdrawLeave");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // A balance moved by hand is the one HR act that creates value out of nothing: a day of annual
    // leave is a day of pay. Money-moving as well as record-moving.
    { id = "leave.adjustBalance"; resource = "leave"; action = #update; guards = #command("adjustLeaveBalance");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // An accrual slice carries the plan's hash, and the plan was fixed before the run. The slice
    // itself is the machine executing an approved plan, so it is not a second approval.
    { id = "leave.accrue"; resource = "leave"; action = #update; guards = #command("accrueLeave");
      moneyMoving = true; recordMoving = true; dualByDefault = true },

    // ── payroll ───────────────────────────────────────────────────────────────
    // The statutory layer is DATA, and data that decides what is deducted from a person's pay is a
    // record-moving act: declaring a profile or a bracket needs two people, and so does retiring
    // one. The received engine has no such rows at all - the rates are compiled in.
    { id = "payroll.declareProfile"; resource = "statutory"; action = #create; guards = #command("declareStatutoryProfile");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "payroll.declareBracket"; resource = "statutory"; action = #create; guards = #command("declareTaxBracket");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "payroll.retireProfile"; resource = "statutory"; action = #close; guards = #command("retireStatutoryProfile");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "payroll.setCompensation"; resource = "compensation"; action = #update; guards = #command("setCompensation");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // Opening a run FIXES THE PLAN - the period, the employee set, the profile version - before any
    // payslip exists, so it is the act that decides what the run will be and needs two people.
    { id = "payroll.openRun"; resource = "payrollRun"; action = #create; guards = #command("openPayrollRun");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // A slice is the machine executing an approved plan, not a second approval, so it is single
    // authority - and it carries the plan's hash, which is what stops it becoming something else.
    { id = "payroll.runSlice"; resource = "payrollRun"; action = #update; guards = #command("runPayrollSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "payroll.closeRun"; resource = "payrollRun"; action = #close; guards = #command("closePayrollRun");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "payroll.approveRun"; resource = "payrollRun"; action = #approve; guards = #command("approvePayrollRun");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "payroll.post"; resource = "payrollRun"; action = #approve; guards = #command("postPayrollJournal");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "payroll.abandonRun"; resource = "payrollRun"; action = #reject; guards = #command("abandonPayrollRun");
      moneyMoving = false; recordMoving = true; dualByDefault = true },

    // ── accounting ────────────────────────────────────────────────────────────
    // A chart decides where money lands, so declaring and amending an account is record-moving.
    { id = "account.create"; resource = "account"; action = #create; guards = #command("createAccount");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "account.amend"; resource = "account"; action = #update; guards = #command("amendAccount");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "account.deprecate"; resource = "account"; action = #close; guards = #command("deprecateAccount");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "journal.create"; resource = "journal"; action = #create; guards = #command("createJournal");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "journal.amend"; resource = "journal"; action = #update; guards = #command("amendJournal");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "journal.close"; resource = "journal"; action = #close; guards = #command("closeJournal");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // PROPOSING a move moves no money - the maker's half of four eyes, and single authority by
    // design, because requiring two people to write a draft makes the control theatre.
    { id = "move.propose"; resource = "move"; action = #create; guards = #command("proposeMove");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // POSTING is the act that moves money, and the checker's half. The fold refuses a poster who
    // is the proposer, by any path.
    { id = "move.post"; resource = "move"; action = #approve; guards = #command("postMove");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "move.cancel"; resource = "move"; action = #reject; guards = #command("cancelMove");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // Closing a period is what makes a filed year unchangeable. It only moves forward.
    { id = "period.lock"; resource = "period"; action = #close; guards = #command("lockPeriod");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // THE CLOSE. Beginning it locks the period, which is a record about every move in it; the plan
    // slices write only the plan; posting the sweep moves money and is the checker's half, refused
    // to the planner by the fold; re-opening is a recorded act and its reversal moves money again.
    { id = "close.begin"; resource = "period"; action = #create; guards = #command("beginClose");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "close.plan"; resource = "period"; action = #update; guards = #command("planCloseSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "close.cancel"; resource = "period"; action = #reject; guards = #command("cancelClose");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "close.post"; resource = "period"; action = #approve; guards = #command("closePeriod");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "close.reopen"; resource = "period"; action = #reverse; guards = #command("reopenClose");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "close.reverse"; resource = "period"; action = #reverse; guards = #command("reverseCloseSlice");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // STATEMENTS are read-outs of the ledger at a block: they move no money and no record, and are
    // refused by the fold unless their window is locked.
    { id = "statement.open"; resource = "statement"; action = #create; guards = #command("openStatement");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "statement.slice"; resource = "statement"; action = #update; guards = #command("statementSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "statement.cancel"; resource = "statement"; action = #reject; guards = #command("cancelStatement");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // DEFERRALS. The schedule is a record about money and is declared and cancelled under four
    // eyes; the run's slices post moves, and the fold refuses them to the opener.
    { id = "deferral.declare"; resource = "deferral"; action = #create; guards = #command("declareDeferral");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "deferral.cancel"; resource = "deferral"; action = #reject; guards = #command("cancelDeferral");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "deferral.openRun"; resource = "deferral"; action = #activate; guards = #command("openDeferralRun");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "deferral.recognise"; resource = "deferral"; action = #approve; guards = #command("deferralRunSlice");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // REVALUATION. The policy names where unrealised differences go; the slices post them.
    { id = "revaluation.policy"; resource = "period"; action = #create; guards = #command("setRevaluationPolicy");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "close.revalue"; resource = "period"; action = #approve; guards = #command("revalueCloseSlice");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // FIXED ASSETS. The register row is a recorded act; an impairment and a disposal are proposed by
    // one person and posted by another; the run's slices post the charges, refused to the opener.
    { id = "asset.capitalise"; resource = "asset"; action = #create; guards = #command("capitaliseAsset");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "asset.impair"; resource = "asset"; action = #update; guards = #command("impairAsset");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "asset.dispose"; resource = "asset"; action = #close; guards = #command("disposeAsset");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "asset.postEvent"; resource = "asset"; action = #approve; guards = #command("postAssetEvent");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "asset.cancelEvent"; resource = "asset"; action = #reject; guards = #command("cancelAssetEvent");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "asset.openRun"; resource = "asset"; action = #activate; guards = #command("openDepreciationRun");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "asset.depreciate"; resource = "asset"; action = #approve; guards = #command("depreciationRunSlice");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // EXPENSES. A category and a rate decide where a claim's money lands and how much it is; the
    // policy names the payable it accrues on. Filing and withdrawing are the claimant's own acts; a
    // decision on somebody's claim is record-moving, and the approval and the settlement move money.
    { id = "expense.declareCategory"; resource = "expense_category"; action = #create; guards = #command("declareExpenseCategory");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "expense.setRate"; resource = "expense_rate"; action = #create; guards = #command("setExpenseRate");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "expense.setPolicy"; resource = "expense_policy"; action = #create; guards = #command("setExpensePolicy");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "expense.file"; resource = "expense_claim"; action = #create; guards = #command("fileExpenseClaim");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "expense.withdraw"; resource = "expense_claim"; action = #close; guards = #command("withdrawExpenseClaim");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "expense.reject"; resource = "expense_claim"; action = #reject; guards = #command("rejectExpenseClaim");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "expense.approve"; resource = "expense_claim"; action = #approve; guards = #command("approveExpenseClaim");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "expense.settle"; resource = "expense_claim"; action = #close; guards = #command("settleExpenseClaim");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // PAYMENTS OUT. An account at either end decides where money goes; the preparation fixes the
    // message; the submission and the hub's word are each a second person's act; the acceptance
    // posts the move; a prepared message withdrawn is the preparer's own act.
    { id = "payment.registerBankAccount"; resource = "bank_account"; action = #create; guards = #command("registerBankAccount");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "payment.setPartnerBankAccount"; resource = "partner_bank_account"; action = #create; guards = #command("setPartnerBankAccount");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "payment.prepare"; resource = "payment"; action = #create; guards = #command("preparePayment");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "payment.submit"; resource = "payment"; action = #update; guards = #command("recordPaymentSubmission");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "payment.result"; resource = "payment"; action = #approve; guards = #command("recordPaymentResult");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "payment.cancel"; resource = "payment"; action = #close; guards = #command("cancelPayment");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // A statement from the bank is the same record as one typed in, and is confirmed and matched the same way.
    { id = "bankStatement.importCamt053"; resource = "bank_statement"; action = #create; guards = #command("importCamt053");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // ── credit terms on parties ──
    // The terms decide what a customer may owe and what an overdue invoice is charged: record-moving.
    { id = "creditTerms.set"; resource = "credit_terms"; action = #update; guards = #command("setCreditTerms");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // The run posts late charges and interest to the ledger: one person opens it, another slices it.
    { id = "interestRun.open"; resource = "interest_run"; action = #create; guards = #command("openInterestRun");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "interestRun.slice"; resource = "interest_run"; action = #approve; guards = #command("interestRunSlice");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // ── consolidation ──
    // The group, its members and its links decide whose books fold into whose statement and what is
    // eliminated: records about companies, under four eyes.
    { id = "group.declare"; resource = "company_group"; action = #update; guards = #command("declareGroup");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "group.addMember"; resource = "group_member"; action = #create; guards = #command("addGroupMember");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "group.removeMember"; resource = "group_member"; action = #close; guards = #command("removeGroupMember");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "group.link"; resource = "intercompany_link"; action = #update; guards = #command("linkIntercompanyPartner");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "group.unlink"; resource = "intercompany_link"; action = #close; guards = #command("unlinkIntercompanyPartner");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // A CONSOLIDATION is a read-out of published statements at a block, like a statement: it moves
    // no money and no record, and the fold refuses it over anything but published statements of one
    // kind and one window.
    { id = "consolidation.open"; resource = "consolidation"; action = #create; guards = #command("openConsolidation");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "consolidation.slice"; resource = "consolidation"; action = #update; guards = #command("consolidationSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "consolidation.cancel"; resource = "consolidation"; action = #reject; guards = #command("cancelConsolidation");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // ── maintenance ──
    // The register and the plans decide what is maintained and when: records, under four eyes.
    { id = "equipment.declare"; resource = "equipment"; action = #update; guards = #command("declareEquipment");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "equipment.retire"; resource = "equipment"; action = #close; guards = #command("retireEquipment");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // A piece handed to a person and received back moves custody, not value: the register's own record.
    { id = "equipment.assign"; resource = "equipment_holding"; action = #create; guards = #command("assignEquipment");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "equipment.return"; resource = "equipment_holding"; action = #close; guards = #command("returnEquipment");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "maintenancePlan.declare"; resource = "maintenance_plan"; action = #create; guards = #command("declareMaintenancePlan");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "maintenancePlan.cancel"; resource = "maintenance_plan"; action = #close; guards = #command("cancelMaintenancePlan");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // The run raises work orders: one person opens it, another slices it.
    { id = "maintenanceRun.open"; resource = "maintenance_run"; action = #create; guards = #command("openMaintenanceRun");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "maintenanceRun.slice"; resource = "maintenance_run"; action = #approve; guards = #command("maintenanceRunSlice");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // A request takes equipment down and stands against a production; the sign-off consumes stock:
    // raised by one person, signed off by another.
    { id = "workOrder.request"; resource = "work_order"; action = #create; guards = #command("requestRepair");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "workOrder.complete"; resource = "work_order"; action = #approve; guards = #command("completeWorkOrder");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "workOrder.cancel"; resource = "work_order"; action = #reject; guards = #command("cancelWorkOrder");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // ── quality ──
    // A control point decides what is held: a record, under four eyes. A check is the checker's
    // record of the goods and decides whether stock moves; a disposition is a second person's act
    // that may cancel a picking or move goods into loss.
    { id = "controlPoint.declare"; resource = "control_point"; action = #update; guards = #command("declareControlPoint");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "controlPoint.retire"; resource = "control_point"; action = #close; guards = #command("retireControlPoint");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "qualityCheck.record"; resource = "quality_check"; action = #create; guards = #command("recordQualityCheck");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "nonConformance.decide"; resource = "non_conformance"; action = #approve; guards = #command("decideDisposition");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // ── helpdesk ──
    // A team names the person its tickets land on and an assignment puts work on a person's desk:
    // records about people, under four eyes. A ticket anybody may raise alone and write on alone;
    // moving it is the desk's act and never the requester's, closing it a second person's; the
    // escalation run is opened by one person and sliced by another.
    { id = "helpdeskTeam.declare"; resource = "helpdesk_team"; action = #update; guards = #command("declareHelpdeskTeam");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "helpdeskTeam.retire"; resource = "helpdesk_team"; action = #close; guards = #command("retireHelpdeskTeam");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "ticketStage.declare"; resource = "ticket_stage"; action = #update; guards = #command("declareTicketStage");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "serviceLevel.set"; resource = "service_level"; action = #update; guards = #command("setServiceLevel");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "ticket.open"; resource = "ticket"; action = #create; guards = #command("openTicket");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "ticket.assign"; resource = "ticket"; action = #update; guards = #command("assignTicket");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "ticket.move"; resource = "ticket"; action = #approve; guards = #command("moveTicket");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "ticketMessage.post"; resource = "ticket_message"; action = #create; guards = #command("postTicketMessage");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "escalationSweep.open"; resource = "escalation_run"; action = #create; guards = #command("openEscalationSweep");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "escalationSweep.slice"; resource = "escalation_run"; action = #approve; guards = #command("escalationSweepSlice");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // ── field service ──
    // A visit is planned by one person for another (a record about a person, under four eyes: the
    // planner is not the technician); the technician completes it and the parts move from stock;
    // the invoice is a second person's act, and it moves money.
    { id = "serviceRate.set"; resource = "service_rate"; action = #update; guards = #command("setServiceRate");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "visit.plan"; resource = "visit"; action = #create; guards = #command("planVisit");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "visit.cancel"; resource = "visit"; action = #reject; guards = #command("cancelVisit");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "visit.complete"; resource = "visit"; action = #approve; guards = #command("completeVisit");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "visit.invoice"; resource = "visit"; action = #approve; guards = #command("invoiceVisit");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // ── appointments ──
    // A resource names its keeper, a person: declared and retired under four eyes. A booking is
    // one person's act and its cancellation the booker's or the keeper's.
    { id = "bookableResource.declare"; resource = "bookable_resource"; action = #update; guards = #command("declareBookableResource");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "bookableResource.retire"; resource = "bookable_resource"; action = #close; guards = #command("retireBookableResource");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "booking.make"; resource = "booking"; action = #create; guards = #command("bookResource");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "booking.cancel"; resource = "booking"; action = #reject; guards = #command("cancelBooking");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // ── subscriptions ──
    // A subscription is a standing claim on a customer: opened and changed under four eyes, since a
    // change may raise a prorated invoice; closed by whoever closes it; the run that invoices is
    // opened by one person and sliced by another.
    { id = "subscription.open"; resource = "subscription"; action = #create; guards = #command("openSubscription");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "subscription.change"; resource = "subscription"; action = #update; guards = #command("changeSubscription");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "subscription.close"; resource = "subscription"; action = #close; guards = #command("closeSubscription");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "subscriptionRun.open"; resource = "subscription_run"; action = #create; guards = #command("openSubscriptionRun");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "subscriptionRun.slice"; resource = "subscription_run"; action = #approve; guards = #command("subscriptionRunSlice");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // ── rental ──
    // An item for hire and a reservation are records of a thing and of days; the handover moves
    // stock and the return moves it back and raises money, each by somebody other than the person
    // who reserved.
    { id = "rentalItem.declare"; resource = "rental_item"; action = #update; guards = #command("declareRentalItem");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "rentalItem.retire"; resource = "rental_item"; action = #close; guards = #command("retireRentalItem");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "rental.reserve"; resource = "rental"; action = #create; guards = #command("reserveRental");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "rental.cancel"; resource = "rental"; action = #reject; guards = #command("cancelRental");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "rental.pickUp"; resource = "rental"; action = #approve; guards = #command("pickUpRental");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "rental.return"; resource = "rental"; action = #approve; guards = #command("returnRental");
      moneyMoving = true; recordMoving = true; dualByDefault = true },

    // ── point of sale ──
    // A shop and its list are records of a place and of prices; a session is the cashier's own - 
    // opened, sold in and counted by one person, every sale an invoice proposed in their name - and
    // the Z report that posts the receipts, moves the goods and takes the takings is somebody
    // else's act.
    { id = "shop.declare"; resource = "pos_shop"; action = #update; guards = #command("declareShop");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "shop.retire"; resource = "pos_shop"; action = #close; guards = #command("retireShop");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "shop.setPrice"; resource = "pos_price"; action = #update; guards = #command("setShopPrice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "shop.withdrawPrice"; resource = "pos_price"; action = #close; guards = #command("withdrawShopPrice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "till.open"; resource = "pos_session"; action = #create; guards = #command("openTillSession");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // a sale rung up PROPOSES its invoice in the cashier's name and posts nothing; the money moves
    // when the session is posted, which is the dual act below
    { id = "till.ringUp"; resource = "pos_sale"; action = #create; guards = #command("ringUpSale");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "till.close"; resource = "pos_session"; action = #close; guards = #command("closeTillSession");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "till.post"; resource = "pos_session"; action = #approve; guards = #command("postTillSession");
      moneyMoving = true; recordMoving = true; dualByDefault = true },

    // ── the restaurant ──
    // A table is a record of a place; a tab, its courses and its lines are a bill in the making,
    // the waiter's acts; settling the bill RINGS IT UP THROUGH THE TILL - the sale proposes its
    // invoice as every till sale does and posts nothing, the Z report being the dual act.
    { id = "table.declare"; resource = "rst_table"; action = #update; guards = #command("declareTable");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "table.retire"; resource = "rst_table"; action = #close; guards = #command("retireTable");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "tab.open"; resource = "rst_tab"; action = #create; guards = #command("openTab");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "tab.orderCourse"; resource = "rst_line"; action = #create; guards = #command("orderCourse");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "tab.voidLine"; resource = "rst_line"; action = #reject; guards = #command("voidTabLine");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "tab.sendCourse"; resource = "rst_course"; action = #update; guards = #command("sendCourse");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "tab.cancel"; resource = "rst_tab"; action = #reject; guards = #command("cancelTab");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "tab.settle"; resource = "rst_tab"; action = #close; guards = #command("settleTab");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── the web shop ──
    // A storefront and its catalogue are records; a cart is the shopper's draft; the checkout
    // confirms an order and records a payment and posts nothing; FULFILMENT moves stock and money
    // and is a second person's - the shopper proposes by having paid, a member posts.
    { id = "storefront.open"; resource = "web_storefront"; action = #update; guards = #command("openStorefront");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "storefront.close"; resource = "web_storefront"; action = #close; guards = #command("closeStorefront");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "storefront.list"; resource = "web_listing"; action = #update; guards = #command("listOnline");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "storefront.delist"; resource = "web_listing"; action = #close; guards = #command("delist");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "cart.add"; resource = "web_cart"; action = #update; guards = #command("addToCart");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "cart.remove"; resource = "web_cart"; action = #update; guards = #command("removeFromCart");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "cart.abandon"; resource = "web_cart"; action = #reject; guards = #command("abandonCart");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "cart.checkout"; resource = "web_order"; action = #create; guards = #command("checkout");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "webOrder.fulfil"; resource = "web_order"; action = #approve; guards = #command("fulfilWebOrder");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "webOrder.cancel"; resource = "web_order"; action = #reject; guards = #command("cancelWebOrder");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── the website ──
    // A page is a company document made public at a path: a record of what the company says, by a
    // member, moving no money and no record about a person.
    { id = "page.publish"; resource = "site_page"; action = #update; guards = #command("publishPage");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "page.unpublish"; resource = "site_page"; action = #close; guards = #command("unpublishPage");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── the blog ──
    // A post is a page with a byline and a day: a record of what the company says, by a member.
    { id = "post.publish"; resource = "blog_post"; action = #create; guards = #command("publishPost");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "post.revise"; resource = "blog_post"; action = #update; guards = #command("revisePost");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "post.withdraw"; resource = "blog_post"; action = #close; guards = #command("withdrawPost");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── the forum ──
    // A board, a topic and a reply are a member's word on the record, said once and never edited; a
    // moderation is a second person's act on it, recorded as a row of its own.
    { id = "board.declare"; resource = "forum_board"; action = #create; guards = #command("declareBoard");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "topic.open"; resource = "forum_topic"; action = #create; guards = #command("openTopic");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "topic.reply"; resource = "forum_reply"; action = #create; guards = #command("replyToTopic");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "forum.moderate"; resource = "forum_moderation"; action = #create; guards = #command("moderate");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // An idea is a topic on a board marked for ideas; a vote is a member's, one per idea; a decision on it is a
    // second person's, never its author's, and moves it forward only.
    { id = "board.mark_ideas"; resource = "forum_idea_board"; action = #update; guards = #command("markIdeaBoard");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "topic.vote"; resource = "forum_vote"; action = #create; guards = #command("voteTopic");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "idea.decide"; resource = "forum_idea_status"; action = #approve; guards = #command("setIdeaStatus");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── live chat ──
    // A conversation is a visitor's, taken by an operator the fold assigns; an operator is enrolled by
    // somebody else; a word is a party's own and the history bounded.
    { id = "operator.enrol"; resource = "chat_operator"; action = #create; guards = #command("enrolOperator");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "operator.withdraw"; resource = "chat_operator"; action = #close; guards = #command("withdrawOperator");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "conversation.open"; resource = "chat_conversation"; action = #create; guards = #command("openConversation");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "conversation.take"; resource = "chat_conversation"; action = #update; guards = #command("takeConversation");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "conversation.transfer"; resource = "chat_conversation"; action = #update; guards = #command("transferConversation");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "conversation.say"; resource = "chat_message"; action = #create; guards = #command("sendChatMessage");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "conversation.close"; resource = "chat_conversation"; action = #close; guards = #command("closeConversation");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "conversation.rate"; resource = "chat_conversation"; action = #update; guards = #command("rateConversation");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── marketing automation ──
    // A workflow is a rule set the second person activates; its runs enrol and fire in bounded slices,
    // every send a wave through the mailing. The activation is dual in substance (declarer ≠ activator)
    // and moves no money or record of its own, so it is not flagged.
    { id = "workflow.declare"; resource = "auto_workflow"; action = #create; guards = #command("declareWorkflow");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "workflow.addStep"; resource = "auto_step"; action = #create; guards = #command("addWorkflowStep");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "workflow.activate"; resource = "auto_workflow"; action = #update; guards = #command("activateWorkflow");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "workflow.close"; resource = "auto_workflow"; action = #close; guards = #command("closeWorkflow");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "workflow.openEnrolment"; resource = "auto_run"; action = #create; guards = #command("openEnrolmentRun");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "workflow.enrolSlice"; resource = "auto_participant"; action = #create; guards = #command("enrolmentSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "workflow.openSteps"; resource = "auto_run"; action = #create; guards = #command("openStepRun");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "workflow.stepSlice"; resource = "auto_participant"; action = #update; guards = #command("stepSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── SMS marketing ──
    // The mailing's shape over numbers: the body fixed at launch, the list built and claimed in bounded
    // slices for a relay's call made outside the contract, what came back written per copy.
    { id = "sms.create"; resource = "sms_mailing"; action = #create; guards = #command("createSmsMailing");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "sms.amend"; resource = "sms_mailing"; action = #update; guards = #command("amendSmsMailing");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "sms.launch"; resource = "sms_mailing"; action = #update; guards = #command("launchSmsMailing");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "sms.plan"; resource = "sms_recipient"; action = #create; guards = #command("planSmsSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "sms.claim"; resource = "sms_recipient"; action = #update; guards = #command("claimSmsSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "sms.results"; resource = "sms_recipient"; action = #update; guards = #command("recordSmsResults");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "sms.replies"; resource = "sms_recipient"; action = #update; guards = #command("recordSmsReplies");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "sms.cancel"; resource = "sms_mailing"; action = #close; guards = #command("cancelSmsMailing");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "sms.suppress"; resource = "sms_suppression"; action = #create; guards = #command("suppressNumber");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "sms.release"; resource = "sms_suppression"; action = #close; guards = #command("releaseNumber");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── social marketing ──
    // An account the company's voice on a channel; a post a member's word scheduled by the calendar, given
    // to the relay by the fold when its day has come, the relay's word folded per post.
    { id = "social.connect"; resource = "social_account"; action = #create; guards = #command("connectSocialAccount");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "social.disconnect"; resource = "social_account"; action = #close; guards = #command("disconnectSocialAccount");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "social.schedule"; resource = "social_post"; action = #create; guards = #command("schedulePost");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "social.amend"; resource = "social_post"; action = #update; guards = #command("amendPost");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "social.cancel"; resource = "social_post"; action = #close; guards = #command("cancelPost");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "social.claim"; resource = "social_post"; action = #update; guards = #command("claimPost");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "social.result"; resource = "social_post"; action = #update; guards = #command("recordPostResult");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── events ──
    // A ticket is an order invoiced through the order fold - money moves - sold by a member who is not the
    // organiser who set the price, so the act is two people's.
    { id = "event.announce"; resource = "event"; action = #create; guards = #command("announceEvent");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "event.amend"; resource = "event"; action = #update; guards = #command("amendEvent");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "event.cancel"; resource = "event"; action = #close; guards = #command("cancelEvent");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "event.sell"; resource = "event_ticket"; action = #create; guards = #command("sellTickets");
      moneyMoving = true; recordMoving = false; dualByDefault = true },
    { id = "event.attend"; resource = "event_ticket"; action = #update; guards = #command("recordAttendance");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // A member's answer to an event held at no price is their own word and moves nothing.
    { id = "event.respond"; resource = "event_response"; action = #create; guards = #command("respondToEvent");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "event.close"; resource = "event"; action = #close; guards = #command("closeEvent");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── surveys ──
    // A survey a member opens, questions added in order, a response a member's once with its answers as rows.
    { id = "survey.open"; resource = "survey"; action = #create; guards = #command("openSurvey");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "survey.addQuestion"; resource = "survey_question"; action = #create; guards = #command("addSurveyQuestion");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "survey.respond"; resource = "survey_response"; action = #create; guards = #command("respondToSurvey");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "survey.close"; resource = "survey"; action = #close; guards = #command("closeSurvey");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── appraisals ────────────────────────────────────────────────────────────
    // A cycle, its enrolment and its close are a member's; the self review is the subject's own word. The
    // manager's review, the calibration and a recognition are records about a
    // person made by somebody else, so each compares two principals and is dual. Succession is the people fold's.
    { id = "appraisal.openCycle"; resource = "review_cycle"; action = #create; guards = #command("openReviewCycle");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "appraisal.enrol"; resource = "review"; action = #create; guards = #command("enrolReviewSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "appraisal.selfReview"; resource = "review"; action = #update; guards = #command("submitSelfReview");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "appraisal.managerReview"; resource = "review"; action = #update; guards = #command("submitManagerReview");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "appraisal.startCalibration"; resource = "review_cycle"; action = #update; guards = #command("startCalibration");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "appraisal.calibrate"; resource = "review"; action = #approve; guards = #command("calibrateReview");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "appraisal.closeCycle"; resource = "review_cycle"; action = #close; guards = #command("closeReviewCycle");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "goal.set"; resource = "goal"; action = #create; guards = #command("setGoal");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "goal.addKeyResult"; resource = "key_result"; action = #create; guards = #command("addKeyResult");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "goal.updateKeyResult"; resource = "key_result"; action = #update; guards = #command("updateKeyResult");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "goal.close"; resource = "goal"; action = #close; guards = #command("closeGoal");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "recognition.give"; resource = "recognition"; action = #create; guards = #command("giveRecognition");
      moneyMoving = false; recordMoving = true; dualByDefault = true },

    // ── learning and career ───────────────────────────────────────────────────
    // A course and a path are the company's catalogue; an enrolment, a skill, a certification recorded and a
    // mentor's offer are the person's own word or their manager's. Revoking a certification, endorsing or rating
    // a skill and answering a mentorship are records about a person made by somebody else: each compares two
    // principals and is dual.
    { id = "learning.createCourse"; resource = "course"; action = #create; guards = #command("createCourse");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "learning.retireCourse"; resource = "course"; action = #close; guards = #command("retireCourse");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "learning.createPath"; resource = "learning_path"; action = #create; guards = #command("createLearningPath");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "learning.retirePath"; resource = "learning_path"; action = #close; guards = #command("retireLearningPath");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "learning.enrol"; resource = "enrolment"; action = #create; guards = #command("enrolInCourse");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "learning.progress"; resource = "enrolment"; action = #update; guards = #command("updateCourseProgress");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "learning.drop"; resource = "enrolment"; action = #close; guards = #command("dropEnrolment");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "certification.record"; resource = "certification"; action = #create; guards = #command("recordCertification");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "certification.renew"; resource = "certification"; action = #update; guards = #command("renewCertification");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "certification.revoke"; resource = "certification"; action = #close; guards = #command("revokeCertification");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "skill.declare"; resource = "skill"; action = #create; guards = #command("declareSkill");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "skill.remove"; resource = "skill"; action = #close; guards = #command("removeSkill");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "skill.endorse"; resource = "endorsement"; action = #create; guards = #command("endorseSkill");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "skill.rate"; resource = "skill"; action = #approve; guards = #command("rateSkill");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "mentoring.offer"; resource = "mentor_profile"; action = #create; guards = #command("offerMentoring");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "mentoring.request"; resource = "mentorship"; action = #create; guards = #command("requestMentorship");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "mentoring.respond"; resource = "mentorship"; action = #approve; guards = #command("respondMentorship");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "mentoring.logSession"; resource = "mentorship"; action = #update; guards = #command("logMentoringSession");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "mentoring.complete"; resource = "mentorship"; action = #close; guards = #command("completeMentorship");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── compensation and benefits ─────────────────────────────────────────────
    // A policy, a band, a plan and a period are the company's tables. A salary review is a record about a person at
    // every step - proposed by their manager, decided by a second person, implemented by a third who writes their
    // pay - so each step is dual. A grant, its cancellation, a score and a payment created are records about a person
    // by somebody else; approving a payment, disbursing a loan and recording a repayment move money through the
    // ledger. Vesting is the schedule recorded, exercising the holder's own act, a loan the borrower's own request,
    // an enrolment the employee's own.
    { id = "compensation.setPolicy"; resource = "comp_policy"; action = #create; guards = #command("setCompensationPolicy");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "payBand.declare"; resource = "pay_band"; action = #create; guards = #command("declarePayBand");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "payBand.amend"; resource = "pay_band"; action = #update; guards = #command("amendPayBand");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "payBand.retire"; resource = "pay_band"; action = #close; guards = #command("retirePayBand");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "salaryReview.propose"; resource = "salary_review"; action = #create; guards = #command("proposeSalaryReview");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "salaryReview.decide"; resource = "salary_review"; action = #approve; guards = #command("decideSalaryReview");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "salaryReview.implement"; resource = "salary_review"; action = #update; guards = #command("implementSalaryReview");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "salaryReview.withdraw"; resource = "salary_review"; action = #close; guards = #command("withdrawSalaryReview");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "equity.grant"; resource = "equity_grant"; action = #create; guards = #command("grantEquity");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "equity.vest"; resource = "equity_grant"; action = #update; guards = #command("vestEquity");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "equity.exercise"; resource = "equity_grant"; action = #update; guards = #command("exerciseEquity");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "equity.cancel"; resource = "equity_grant"; action = #close; guards = #command("cancelEquityGrant");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "incentive.createPlan"; resource = "incentive_plan"; action = #create; guards = #command("createIncentivePlan");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "incentive.retirePlan"; resource = "incentive_plan"; action = #close; guards = #command("retireIncentivePlan");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "incentive.score"; resource = "incentive_score"; action = #create; guards = #command("scoreIncentive");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "offCycle.create"; resource = "offcycle_payment"; action = #create; guards = #command("createOffCyclePayment");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "offCycle.approve"; resource = "offcycle_payment"; action = #approve; guards = #command("approveOffCyclePayment");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "offCycle.reject"; resource = "offcycle_payment"; action = #approve; guards = #command("rejectOffCyclePayment");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "offCycle.cancel"; resource = "offcycle_payment"; action = #close; guards = #command("cancelOffCyclePayment");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "loan.request"; resource = "employee_loan"; action = #create; guards = #command("requestLoan");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "loan.withdraw"; resource = "employee_loan"; action = #close; guards = #command("withdrawLoan");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "loan.decide"; resource = "employee_loan"; action = #approve; guards = #command("decideLoan");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "loan.disburse"; resource = "employee_loan"; action = #update; guards = #command("disburseLoan");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "loan.repay"; resource = "loan_repayment"; action = #create; guards = #command("recordLoanRepayment");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "benefit.createPlan"; resource = "benefit_plan"; action = #create; guards = #command("createBenefitPlan");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "benefit.togglePlan"; resource = "benefit_plan"; action = #update; guards = #command("toggleBenefitPlan");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "benefit.openPeriod"; resource = "enrolment_period"; action = #create; guards = #command("openEnrolmentPeriod");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "benefit.enrol"; resource = "benefit_enrolment"; action = #create; guards = #command("enrolInBenefit");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "benefit.waive"; resource = "benefit_enrolment"; action = #close; guards = #command("waiveBenefit");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── fleet ─────────────────────────────────────────────────────────────────
    // A vehicle, a contract and a reading are the company's tables; a driver assigned is a record about a person by
    // somebody else; a cost posted moves money through the ledger and a cost rejected is a second person's word.
    { id = "fleet.setPolicy"; resource = "fleet_policy"; action = #create; guards = #command("setFleetPolicy");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "vehicle.register"; resource = "vehicle"; action = #create; guards = #command("registerVehicle");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "vehicle.retire"; resource = "vehicle"; action = #close; guards = #command("retireVehicle");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "vehicle.assignDriver"; resource = "vehicle_assignment"; action = #create; guards = #command("assignDriver");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "vehicle.releaseDriver"; resource = "vehicle_assignment"; action = #close; guards = #command("releaseDriver");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "vehicleContract.add"; resource = "vehicle_contract"; action = #create; guards = #command("addVehicleContract");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "vehicleContract.cancel"; resource = "vehicle_contract"; action = #close; guards = #command("cancelVehicleContract");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "vehicle.logOdometer"; resource = "odometer_log"; action = #create; guards = #command("logOdometer");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "vehicle.logFuel"; resource = "fuel_log"; action = #create; guards = #command("logFuel");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "vehicleCost.log"; resource = "vehicle_cost"; action = #create; guards = #command("logVehicleCost");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "vehicleCost.post"; resource = "vehicle_cost"; action = #approve; guards = #command("postVehicleCost");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "vehicleCost.reject"; resource = "vehicle_cost"; action = #approve; guards = #command("rejectVehicleCost");
      moneyMoving = false; recordMoving = true; dualByDefault = true },

    // ── discussion ────────────────────────────────────────────────────────────
    // Words said, announced and notified move no money and no person's record: a notification that reports a leave,
    // a payslip or a review reports a record its own domain moved, and the fold holds it to that record.
    { id = "channel.create"; resource = "channel"; action = #create; guards = #command("createChannel");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "channel.archive"; resource = "channel"; action = #close; guards = #command("archiveChannel");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "channel.join"; resource = "channel_member"; action = #create; guards = #command("joinChannel");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "channel.addMember"; resource = "channel_member"; action = #create; guards = #command("addChannelMember");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "channel.leave"; resource = "channel_member"; action = #close; guards = #command("leaveChannel");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "channel.removeMember"; resource = "channel_member"; action = #close; guards = #command("removeChannelMember");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "channel.send"; resource = "channel_message"; action = #create; guards = #command("sendChannelMessage");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "channel.deleteMessage"; resource = "channel_message"; action = #delete; guards = #command("deleteChannelMessage");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "channel.markRead"; resource = "channel_member"; action = #update; guards = #command("markChannelRead");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "announcement.create"; resource = "announcement"; action = #create; guards = #command("createAnnouncement");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "announcement.amend"; resource = "announcement"; action = #update; guards = #command("amendAnnouncement");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "announcement.pin"; resource = "announcement"; action = #update; guards = #command("pinAnnouncement");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "announcement.withdraw"; resource = "announcement"; action = #close; guards = #command("withdrawAnnouncement");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "announcement.react"; resource = "announcement_reaction"; action = #update; guards = #command("toggleReaction");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "announcementSweep.open"; resource = "announcement_sweep"; action = #create; guards = #command("openAnnouncementSweep");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "announcementSweep.slice"; resource = "announcement_sweep"; action = #update; guards = #command("sweepAnnouncementSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "notification.create"; resource = "notification"; action = #create; guards = #command("createNotification");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "notification.markRead"; resource = "notification"; action = #update; guards = #command("markNotificationRead");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "notification.markAllRead"; resource = "notification"; action = #update; guards = #command("markAllNotificationsRead");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "notification.dismiss"; resource = "notification"; action = #close; guards = #command("dismissNotification");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── knowledge ─────────────────────────────────────────────────────────────
    // What readers read is the version a second person published: publishing is record-moving and dual.
    { id = "kbArticle.create"; resource = "kb_article"; action = #create; guards = #command("createKbArticle");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "kbArticle.revise"; resource = "kb_version"; action = #create; guards = #command("reviseKbArticle");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "kbArticle.publish"; resource = "kb_article"; action = #approve; guards = #command("publishKbVersion");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "kbArticle.archive"; resource = "kb_article"; action = #close; guards = #command("archiveKbArticle");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "kbArticle.view"; resource = "kb_view"; action = #create; guards = #command("recordKbView");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "kbArticle.vote"; resource = "kb_vote"; action = #update; guards = #command("voteKbArticle");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── governance ────────────────────────────────────────────────────────────
    // A policy binds the company once a governor who did not write it publishes it, and a citation is a second
    // person's word on somebody's compliance: publishing and citing are record-moving and dual. The step's decision is a
    // second person's by rule; a delegation is the delegator's own act and moves no record.
    { id = "policy.create"; resource = "gov_policy"; action = #create; guards = #command("createPolicy");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "policy.revise"; resource = "gov_policy_version"; action = #create; guards = #command("revisePolicy");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "policy.publish"; resource = "gov_policy"; action = #approve; guards = #command("publishPolicyVersion");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "policy.archive"; resource = "gov_policy"; action = #close; guards = #command("archivePolicy");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "policy.acknowledge"; resource = "gov_ack"; action = #create; guards = #command("acknowledgePolicy");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "requirement.define"; resource = "gov_requirement"; action = #create; guards = #command("defineRequirement");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "requirement.retire"; resource = "gov_requirement"; action = #close; guards = #command("retireRequirement");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "requirement.cite"; resource = "gov_citation"; action = #approve; guards = #command("citeCertification");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "dashboard.layout"; resource = "gov_layout"; action = #update; guards = #command("setDashboardLayout");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "figures.open"; resource = "gov_figures_run"; action = #create; guards = #command("openFiguresRun");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "figures.slice"; resource = "gov_figures_run"; action = #update; guards = #command("runFiguresSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── approval workflows ────────────────────────────────────────────────────
    { id = "approvalCycle.define"; resource = "wf_cycle"; action = #create; guards = #command("defineApprovalCycle");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "approvalCycle.retire"; resource = "wf_cycle"; action = #close; guards = #command("retireApprovalCycle");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "approval.start"; resource = "wf_instance"; action = #create; guards = #command("startApproval");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "approval.decide"; resource = "wf_decision"; action = #approve; guards = #command("decideApprovalStep");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "approval.withdraw"; resource = "wf_instance"; action = #close; guards = #command("withdrawApproval");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "delegation.give"; resource = "wf_delegation"; action = #create; guards = #command("delegateApprovals");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "delegation.revoke"; resource = "wf_delegation"; action = #close; guards = #command("revokeDelegation");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── studio ────────────────────────────────────────────────────────────────
    // A field, a rule and a retirement change no record's contents: a value is its own act, by a writer the rule
    // names. The fold holds each of these to a company administrator.
    { id = "studio_field.define"; resource = "studio_field"; action = #create; guards = #command("defineStudioField");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "studio_field.amend"; resource = "studio_field"; action = #update; guards = #command("amendStudioField");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "studio_field.retire"; resource = "studio_field"; action = #close; guards = #command("retireStudioField");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "studio_rule.set"; resource = "studio_rule"; action = #update; guards = #command("setStudioRule");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "studio_value.set"; resource = "studio_value"; action = #update; guards = #command("setStudioValue");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "studio_value.clear"; resource = "studio_value"; action = #close; guards = #command("clearStudioValue");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── controls ──────────────────────────────────────────────────────────────
    // The screening reads the books and moves nothing: a profile, a run, a finding concluded, a procedure and its
    // conclusion are each a record of the controls alone. The fold holds the profile and the procedure to an
    // administrator or a director, the run and the findings to the profile's screeners, and the review of a
    // conclusion to an administrator or a director who did not prepare it - four eyes by the fold, not by a flag.
    { id = "ctl_profile.set"; resource = "ctl_profile"; action = #update; guards = #command("setControlProfile");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "ctl_run.open"; resource = "ctl_run"; action = #create; guards = #command("openScreening");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "ctl_run.slice"; resource = "ctl_run"; action = #update; guards = #command("screenSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "ctl_finding.conclude"; resource = "ctl_finding"; action = #close; guards = #command("concludeFinding");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "ctl_procedure.define"; resource = "ctl_procedure"; action = #create; guards = #command("defineControlProcedure");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "ctl_conclusion.prepare"; resource = "ctl_conclusion"; action = #create; guards = #command("prepareControlConclusion");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "ctl_conclusion.review"; resource = "ctl_conclusion"; action = #approve; guards = #command("reviewControlConclusion");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── voice over IP ─────────────────────────────────────────────────────────
    // A call moves no money: it is a record of the pipeline, logged by the member who took or made it, and its
    // recording is a document the evidence store already holds under the company's ring.
    { id = "voip_call.log"; resource = "voip_call"; action = #create; guards = #command("logCall");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "voip_call.attach_recording"; resource = "voip_call"; action = #update; guards = #command("attachCallRecording");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── sales and purchase ────────────────────────────────────────────────────
    // A partner and a category decide where an invoice's money lands, so both are record-moving.
    { id = "partner.create"; resource = "partner"; action = #create; guards = #command("createPartner");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "partner.amend"; resource = "partner"; action = #update; guards = #command("amendPartner");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "category.create"; resource = "category"; action = #create; guards = #command("createCategory");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "category.amend"; resource = "category"; action = #update; guards = #command("amendCategory");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // A draft order commits nothing.
    { id = "order.place"; resource = "order"; action = #create; guards = #command("placeOrder");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "order.amend"; resource = "order"; action = #update; guards = #command("amendOrder");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Confirming is the commitment, and issuing is the posting.
    { id = "order.confirm"; resource = "order"; action = #approve; guards = #command("confirmOrder");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "order.cancel"; resource = "order"; action = #reject; guards = #command("cancelOrder");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "order.issueInvoice"; resource = "order"; action = #approve; guards = #command("issueInvoice");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // The three-way match. Assigning a receipt moves no money but it moves the record a payment
    // will later be justified by, so it needs two people as much as the payment does.
    { id = "order.assignReceipt"; resource = "order"; action = #update; guards = #command("assignReceiptToOrder");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // Recording what a supplier SAYS is not yet a claim this business accepts, and one person may
    // do it. Deciding it is owed is the money-moving act, and that one is the second pair of eyes.
    { id = "order.recordBill"; resource = "order"; action = #create; guards = #command("recordSupplierBill");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "order.matchBill"; resource = "order"; action = #approve; guards = #command("matchSupplierBill");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // A CREDIT NOTE MOVES MONEY BACK: a refund move, posted by a second person as the invoice was.
    { id = "order.creditNote"; resource = "order"; action = #create; guards = #command("issueCreditNote");
      moneyMoving = true; recordMoving = true; dualByDefault = true },

    // ── inventory ─────────────────────────────────────────────────────────────
    { id = "warehouse.create"; resource = "warehouse"; action = #create; guards = #command("createWarehouse");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "location.create"; resource = "location"; action = #create; guards = #command("createLocation");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "lot.create"; resource = "lot"; action = #create; guards = #command("createLot");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // A costing rule decides what every unit of stock is WORTH, so it is money-moving in the most
    // direct sense: changing it revalues the balance sheet.
    { id = "costing.set"; resource = "costing"; action = #update; guards = #command("setCosting");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "picking.create"; resource = "picking"; action = #create; guards = #command("createPicking");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "picking.cancel"; resource = "picking"; action = #reject; guards = #command("cancelPicking");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Validating is where stock and value both move, and where the journal entry is posted.
    { id = "picking.validate"; resource = "picking"; action = #approve; guards = #command("validatePicking");
      moneyMoving = true; recordMoving = true; dualByDefault = true },

    // ── manufacturing ─────────────────────────────────────────────────────────
    // A bill of materials decides what every unit costs to make, so declaring or retiring one is
    // record-moving: retiring the BoM a product is made from changes what that product IS.
    { id = "bom.declare"; resource = "bom"; action = #create; guards = #command("declareBom");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "bom.retire"; resource = "bom"; action = #close; guards = #command("retireBom");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // An engineering change decides what every later production of a product consumes, so it is record-moving
    // and therefore dual: proposed by one member, made effective only by another.
    { id = "bom_change.propose"; resource = "bom_change"; action = #create; guards = #command("proposeBomChange");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "bom_change.approve"; resource = "bom_change"; action = #approve; guards = #command("approveBomChange");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "bom_change.reject"; resource = "bom_change"; action = #reject; guards = #command("rejectBomChange");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "bom_change.withdraw"; resource = "bom_change"; action = #close; guards = #command("withdrawBomChange");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── environment, social and governance ──────────────────────────────────
    // A GWP set or a factor decides every figure weighed by it, so it is record-moving and dual: recorded by one
    // member, put in force only by an administrator or director who did not record it.
    { id = "esg_gwp_set.record"; resource = "esg_gwp_set"; action = #create; guards = #command("recordGwpSet");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "esg_gwp_set.approve"; resource = "esg_gwp_set"; action = #approve; guards = #command("approveGwpSet");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "esg_factor.record"; resource = "esg_factor"; action = #create; guards = #command("recordEsgFactor");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "esg_factor.approve"; resource = "esg_factor"; action = #approve; guards = #command("approveEsgFactor");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // A rule decides which approved factor weighs what a line names in later runs. It moves no person's record
    // and no money, and changes no figure already sealed: a run reads the rules as they stood before it was opened,
    // and every factor a rule can point to was put in force under four eyes.
    { id = "esg_rule.set"; resource = "esg_rule"; action = #create; guards = #command("setEsgRule");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "esg_rule.retire"; resource = "esg_rule"; action = #close; guards = #command("retireEsgRule");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "esg_activity.record"; resource = "esg_activity"; action = #create; guards = #command("recordEsgActivity");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "esg_activity.cancel"; resource = "esg_activity"; action = #close; guards = #command("cancelEsgActivity");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // A run computes and seals a statement; it moves nothing.
    { id = "esg_run.open"; resource = "esg_run"; action = #create; guards = #command("openEsgRun");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "esg_run.slice"; resource = "esg_run"; action = #update; guards = #command("esgRunSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // A draft is a candidate act and moves nothing. Accepting it folds the act it holds as the acceptor's, through
    // that act's own row, its gate and its fold - so the act keeps every rule of its own, four eyes included, and
    // the acceptance adds none and removes none.
    { id = "draft.propose"; resource = "draft"; action = #create; guards = #command("proposeDraft");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "draft.accept"; resource = "draft"; action = #approve; guards = #command("acceptDraft");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "draft.reject"; resource = "draft"; action = #close; guards = #command("rejectDraft");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "production.plan"; resource = "production"; action = #create; guards = #command("planProduction");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "production.confirm"; resource = "production"; action = #approve; guards = #command("confirmProduction");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Producing consumes components and creates goods: stock and value both move.
    { id = "production.produce"; resource = "production"; action = #update; guards = #command("produce");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // Closing short writes off the shortfall, which is a decision about value.
    { id = "production.closeShort"; resource = "production"; action = #close; guards = #command("closeProductionShort");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "production.cancel"; resource = "production"; action = #reject; guards = #command("cancelProduction");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // An explosion computes and publishes; it moves nothing.
    { id = "production.explode"; resource = "production"; action = #read; guards = #command("explodeRequirements");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── projects, tasks and time ──────────────────────────────────────────────
    { id = "project.create"; resource = "project"; action = #create; guards = #command("createProject");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "project.amend"; resource = "project"; action = #update; guards = #command("amendProject");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Closing a project stops its cost from moving, which is a decision about money.
    { id = "project.setState"; resource = "project"; action = #close; guards = #command("setProjectState");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "task.create"; resource = "task"; action = #create; guards = #command("createTask");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "task.amend"; resource = "task"; action = #update; guards = #command("amendTask");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "task.setState"; resource = "task"; action = #update; guards = #command("setTaskState");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Logging and submitting time commit nothing. APPROVING a timesheet posts the project's cost,
    // so it is money-moving and needs two people - and never the person who submitted it.
    { id = "time.log"; resource = "time"; action = #create; guards = #command("logTime");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "time.void"; resource = "time"; action = #reject; guards = #command("voidTimeEntry");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "time.submit"; resource = "time"; action = #create; guards = #command("submitTimesheet");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "time.decide"; resource = "time"; action = #approve; guards = #command("decideTimesheet");
      moneyMoving = true; recordMoving = true; dualByDefault = true },

    // ── CRM: leads, stages, activities, mailings, scoring ─────────────────────
    { id = "lead.create"; resource = "lead"; action = #create; guards = #command("createLead");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "lead.amend"; resource = "lead"; action = #update; guards = #command("amendLead");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "lead.setStage"; resource = "lead"; action = #update; guards = #command("setLeadStage");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "lead.convert"; resource = "lead"; action = #update; guards = #command("convertLead");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Winning and losing a lead move a forecast figure that the pipeline report and the sales
    // commission both read, so they are decisions about money.
    { id = "lead.setWon"; resource = "lead"; action = #approve; guards = #command("setLeadWon");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "lead.setLost"; resource = "lead"; action = #reject; guards = #command("setLeadLost");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "lead.restore"; resource = "lead"; action = #update; guards = #command("restoreLead");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "lead.archive"; resource = "lead"; action = #close; guards = #command("archiveLead");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "stage.create"; resource = "stage"; action = #create; guards = #command("createStage");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "stage.amend"; resource = "stage"; action = #update; guards = #command("amendStage");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "stage.archive"; resource = "stage"; action = #close; guards = #command("archiveStage");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "activity.create"; resource = "activity"; action = #create; guards = #command("createActivity");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "activity.amend"; resource = "activity"; action = #update; guards = #command("amendActivity");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "activity.complete"; resource = "activity"; action = #update; guards = #command("completeActivity");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "activity.archive"; resource = "activity"; action = #close; guards = #command("archiveActivity");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // A sweep reads and marks; it moves no money and no record anybody reads as a fact about the
    // world.
    { id = "reminder.open"; resource = "reminder"; action = #create; guards = #command("openReminderSweep");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "reminder.slice"; resource = "reminder"; action = #update; guards = #command("sweepReminderSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Suppressing an address is a promise to a person that they will not be written to again.
    // Releasing one takes that promise back, which is why it needs two.
    { id = "suppression.add"; resource = "suppression"; action = #create; guards = #command("suppressAddress");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "suppression.release"; resource = "suppression"; action = #reject; guards = #command("releaseAddress");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "mailing.create"; resource = "mailing"; action = #create; guards = #command("createMailing");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "mailing.amend"; resource = "mailing"; action = #update; guards = #command("amendMailing");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // LAUNCHING IS THE DECISION. Everything after it is the machine doing what was decided, which
    // is why the slices are single-authority and this is not.
    { id = "mailing.launch"; resource = "mailing"; action = #approve; guards = #command("launchMailing");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "mailing.plan"; resource = "mailing"; action = #update; guards = #command("planMailingSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "mailing.claim"; resource = "mailing"; action = #update; guards = #command("claimMailingSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "mailing.record"; resource = "mailing"; action = #update; guards = #command("recordMailingResults");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "mailing.cancel"; resource = "mailing"; action = #close; guards = #command("cancelMailing");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // A scoring rule decides which leads a salesperson sees first, so changing one is a decision
    // about the pipeline and not a preference.
    { id = "scoring.create"; resource = "scoring_rule"; action = #create; guards = #command("createScoringRule");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "scoring.amend"; resource = "scoring_rule"; action = #update; guards = #command("amendScoringRule");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "scoring.retire"; resource = "scoring_rule"; action = #close; guards = #command("retireScoringRule");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "scoring.open"; resource = "scoring_run"; action = #create; guards = #command("openScoringRun");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "scoring.slice"; resource = "scoring_run"; action = #update; guards = #command("scoreSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── campaigns ─────────────────────────────────────────────────────────────
    // A segment is a saved question about the pipeline; writing one down moves nothing. Archiving
    // one is refused while a live campaign stands on it, and is dual because it takes an audience
    // away from everything that would be addressed to it.
    { id = "segment.create"; resource = "segment"; action = #create; guards = #command("createSegment");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "segment.amend"; resource = "segment"; action = #update; guards = #command("amendSegment");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "segment.archive"; resource = "segment"; action = #close; guards = #command("archiveSegment");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "campaign.create"; resource = "campaign"; action = #create; guards = #command("createCampaign");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "campaign.amend"; resource = "campaign"; action = #update; guards = #command("amendCampaign");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // LAUNCHING IS THE DECISION, as it is for a mailing: it fixes the audience's rule and both
    // arms' content, and the fold refuses it to whoever made the campaign. Everything after it is
    // the machine applying what was decided - the planning, the dealing into arms, the winner by
    // the recorded rule, the remainder - and each of those is single-authority.
    { id = "campaign.launch"; resource = "campaign"; action = #approve; guards = #command("launchCampaign");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "campaign.plan"; resource = "campaign"; action = #update; guards = #command("planCampaignSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "campaign.decide"; resource = "campaign"; action = #update; guards = #command("decideCampaignWinner");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "campaign.remainder"; resource = "campaign"; action = #update; guards = #command("planRemainderSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "campaign.complete"; resource = "campaign"; action = #update; guards = #command("completeCampaign");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "campaign.cancel"; resource = "campaign"; action = #close; guards = #command("cancelCampaign");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // The relay's acknowledgements. An unsubscribe writes a suppression, which is the same promise
    // `suppression.add` makes, and is single-authority for the same reason.
    { id = "engagement.record"; resource = "engagement"; action = #create; guards = #command("recordEngagement");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── evidence and signatures ───────────────────────────────────────────────
    //
    // A VIEW PERMISSION DOES NOT GRANT UPLOAD. `main.mo:8376-8378` admits the caller if they hold
    // `#UploadDocuments` OR `#ViewDocuments`, so read access to the document store was write
    // access to it. Here the two are different resources with different actions, and the
    // catalogue's totality check is what keeps them different.
    { id = "device.register"; resource = "device"; action = #create; guards = #command("registerDevice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Revoking a device is what makes a ring stale and forces a rotation, so it is the act that
    // decides who can read what from this moment on.
    { id = "device.revoke"; resource = "device"; action = #reject; guards = #command("revokeDevice");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "ring.open"; resource = "ring"; action = #create; guards = #command("openRing");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "ring.rotate"; resource = "ring"; action = #update; guards = #command("rotateRing");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "ring.share"; resource = "ring"; action = #update; guards = #command("shareRing");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "upload.begin"; resource = "upload"; action = #create; guards = #command("beginUpload");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "upload.chunk"; resource = "upload"; action = #update; guards = #command("putChunk");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "upload.seal"; resource = "upload"; action = #update; guards = #command("sealUpload");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "upload.abort"; resource = "upload"; action = #reject; guards = #command("abortUpload");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "document.register"; resource = "document"; action = #create; guards = #command("registerDocument");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "document.amend"; resource = "document"; action = #update; guards = #command("amendDocument");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "document.archive"; resource = "document"; action = #close; guards = #command("archiveDocument");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // ERASURE IS IRREVERSIBLE BY CONSTRUCTION. The key is destroyed; no later command can bring
    // the document back. That is exactly the act that needs two people.
    { id = "document.erase"; resource = "document"; action = #reject; guards = #command("eraseDocument");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "documentExpiry.open"; resource = "document_expiry"; action = #create; guards = #command("openDocumentExpirySweep");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "documentExpiry.slice"; resource = "document_expiry"; action = #update; guards = #command("sweepDocumentExpirySlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "signingKey.register"; resource = "signing_key"; action = #create; guards = #command("registerSigningKey");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "signingKey.revoke"; resource = "signing_key"; action = #reject; guards = #command("revokeSigningKey");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "signatureRequest.create"; resource = "signature_request"; action = #create; guards = #command("createSignatureRequest");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "signatureRequest.revoke"; resource = "signature_request"; action = #close; guards = #command("revokeSignatureRequest");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "signatureRequest.address"; resource = "signature_request"; action = #update; guards = #command("nameSigners");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // THE CALENDAR CLOSES IT, NOT THE CALLER. The act records a day that has already passed; the
    // fold refuses it on any other day, so there is nothing for a second person to check.
    { id = "signatureRequest.expire"; resource = "signature_request"; action = #close; guards = #command("expireSignatureRequest");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // A PERSON SIGNS FOR THEMSELVES. Beginning, completing and declining are acts of the signer;
    // a second approver on them would be somebody else signing.
    { id = "signature.begin"; resource = "signature"; action = #create; guards = #command("beginSignature");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "signature.complete"; resource = "signature"; action = #approve; guards = #command("completeSignature");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "signature.completePq"; resource = "signature"; action = #approve; guards = #command("completeSignaturePq");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "signature.decline"; resource = "signature"; action = #reject; guards = #command("declineSignature");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── currencies, taxes, banking and the tax-authority filing ───────────────
    { id = "currency.create"; resource = "currency"; action = #create; guards = #command("createCurrency");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "currency.amend"; resource = "currency"; action = #update; guards = #command("amendCurrency");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "currency.retire"; resource = "currency"; action = #close; guards = #command("retireCurrency");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // A RATE REVALUES A LEDGER. Whoever records one decides what every foreign balance is worth,
    // which is as money-moving as an act gets without a journal entry.
    { id = "currency.rate"; resource = "currency_rate"; action = #create; guards = #command("recordRate");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // A TAX RATE DECIDES WHAT IS OWED TO A REVENUE AUTHORITY.
    { id = "tax.create"; resource = "tax"; action = #create; guards = #command("createTax");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "tax.amend"; resource = "tax"; action = #update; guards = #command("amendTax");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "tax.retire"; resource = "tax"; action = #close; guards = #command("retireTax");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "bankStatement.import"; resource = "bank_statement"; action = #create; guards = #command("importBankStatement");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "bankStatement.addLine"; resource = "bank_statement"; action = #update; guards = #command("addStatementLine");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Confirming fixes the lines a reconciliation will be done against.
    { id = "bankStatement.confirm"; resource = "bank_statement"; action = #approve; guards = #command("confirmBankStatement");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "bankStatement.archive"; resource = "bank_statement"; action = #close; guards = #command("archiveBankStatement");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // A RECONCILIATION SAYS A PAYMENT HAPPENED. It closes a receivable or a payable.
    { id = "reconciliation.match"; resource = "reconciliation"; action = #approve; guards = #command("reconcileLine");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "reconciliation.undo"; resource = "reconciliation"; action = #reject; guards = #command("unreconcileLine");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // The run only SUGGESTS where exactly one candidate fits; the suggestion is the same act, so
    // opening one is the decision and a slice is the machine doing it.
    { id = "match.open"; resource = "match_run"; action = #create; guards = #command("openMatchRun");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "match.slice"; resource = "match_run"; action = #update; guards = #command("matchSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // WHERE A COMPANY'S TAX DOCUMENTS GO. `submitEtaInvoice` lets a caller name the URL.
    { id = "eta.configure"; resource = "eta_config"; action = #update; guards = #command("configureEtaEndpoint");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "eta.prepare"; resource = "eta_filing"; action = #create; guards = #command("prepareEtaFiling");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // FILING IS THE DECISION: a document goes to a revenue authority in the company's name.
    { id = "eta.submit"; resource = "eta_filing"; action = #approve; guards = #command("recordEtaSubmission");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "eta.result"; resource = "eta_filing"; action = #update; guards = #command("recordEtaResult");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "eta.abandon"; resource = "eta_filing"; action = #close; guards = #command("abandonEtaFiling");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // THE COMPANY AS THE AUTHORITY KNOWS IT, and the anchor every seal must chain to.
    { id = "eta.issuerProfile"; resource = "eta_config"; action = #update; guards = #command("setIssuerProfile");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "eta.partnerAddress"; resource = "partner"; action = #update; guards = #command("setPartnerAddress");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "eta.categoryProfile"; resource = "category"; action = #update; guards = #command("setCategoryTaxProfile");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "eta.prepareCredit"; resource = "eta_filing"; action = #create; guards = #command("prepareEtaCreditNote");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // THE SEAL IS A SEPARATE PARTY'S ACT: the holder of the sealing token, not the preparer.
    { id = "eta.seal"; resource = "eta_filing"; action = #approve; guards = #command("sealEtaFiling");
      moneyMoving = false; recordMoving = true; dualByDefault = true },

    // ── the person record and conduct ─────────────────────────────────────────
    { id = "plan.openPlan"; resource = "plan"; action = #create; guards = #command("openPlan");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "plan.addPlanItem"; resource = "plan"; action = #update; guards = #command("addPlanItem");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "plan.setPlanItemState"; resource = "plan"; action = #update; guards = #command("setPlanItemState");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Closing a plan says somebody is onboarded, or has left; it is the record the product is asked for afterwards.
    { id = "plan.closePlan"; resource = "plan"; action = #close; guards = #command("closePlan");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // A contract is the commercial terms of an engagement.
    { id = "contract.createContract"; resource = "contract"; action = #create; guards = #command("createContract");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "contract.amendContract"; resource = "contract"; action = #update; guards = #command("amendContract");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // Signing and terminating are both decisions about money.
    { id = "contract.setContractState"; resource = "contract"; action = #approve; guards = #command("setContractState");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "probation.openProbation"; resource = "probation"; action = #create; guards = #command("openProbation");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "probation.addProbationCheckIn"; resource = "probation"; action = #update; guards = #command("addProbationCheckIn");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // THE ACT THAT ENDS OR CONFIRMS AN EMPLOYMENT. `main.mo:21575` lets the manager whose report it is do it alone.
    { id = "probation.finalizeProbation"; resource = "probation"; action = #approve; guards = #command("finalizeProbation");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "relocation.requestRelocation"; resource = "relocation"; action = #create; guards = #command("requestRelocation");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "relocation.decideRelocation"; resource = "relocation"; action = #approve; guards = #command("decideRelocation");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "relocation.setRelocationState"; resource = "relocation"; action = #update; guards = #command("setRelocationState");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // An expense against an approved budget is money.
    { id = "relocation.addRelocationExpense"; resource = "relocation"; action = #update; guards = #command("addRelocationExpense");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "work_history.addWorkHistoryItem"; resource = "work_history"; action = #create; guards = #command("addWorkHistoryItem");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "family_member.addFamilyMember"; resource = "family_member"; action = #create; guards = #command("addFamilyMember");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // A dependant removed is a person taken off a policy.
    { id = "family_member.removeFamilyMember"; resource = "family_member"; action = #reject; guards = #command("removeFamilyMember");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "headcount_plan.createHeadcountPlan"; resource = "headcount_plan"; action = #create; guards = #command("createHeadcountPlan");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "headcount_plan.addFteEntry"; resource = "headcount_plan"; action = #update; guards = #command("addFteEntry");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // A headcount plan commits a budget.
    { id = "headcount_plan.setHeadcountState"; resource = "headcount_plan"; action = #approve; guards = #command("setHeadcountState");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "key_position.declareKeyPosition"; resource = "key_position"; action = #create; guards = #command("declareKeyPosition");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Naming somebody's successor is a statement about them and about the incumbent.
    { id = "key_position.upsertSuccessor"; resource = "key_position"; action = #update; guards = #command("upsertSuccessor");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "key_position.removeSuccessor"; resource = "key_position"; action = #reject; guards = #command("removeSuccessor");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // A field added to every person record in the company.
    { id = "custom_field.createCustomField"; resource = "custom_field"; action = #create; guards = #command("createCustomField");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "custom_field.amendCustomField"; resource = "custom_field"; action = #update; guards = #command("amendCustomField");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "custom_field.retireCustomField"; resource = "custom_field"; action = #close; guards = #command("retireCustomField");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "custom_field.setCustomFieldValue"; resource = "custom_field"; action = #update; guards = #command("setCustomFieldValue");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // A WARNING MAY END SOMEBODY'S EMPLOYMENT. One person opening one alone is the shape a tribunal asks about.
    { id = "disciplinary_case.openDisciplinaryCase"; resource = "disciplinary_case"; action = #create; guards = #command("openDisciplinaryCase");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // Only the subject acknowledges their own; a second person here would be somebody else signing.
    { id = "disciplinary_case.acknowledgeDisciplinaryCase"; resource = "disciplinary_case"; action = #approve; guards = #command("acknowledgeDisciplinaryCase");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "disciplinary_case.resolveDisciplinaryCase"; resource = "disciplinary_case"; action = #close; guards = #command("resolveDisciplinaryCase");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "disciplinary_case.openWarningExpirySweep"; resource = "disciplinary_case"; action = #create; guards = #command("openWarningExpirySweep");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "disciplinary_case.sweepWarningExpirySlice"; resource = "disciplinary_case"; action = #update; guards = #command("sweepWarningExpirySlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // A complaint is the complainant's act. A second approver on it would be somebody reading it before it is filed.
    { id = "grievance.submitGrievance"; resource = "grievance"; action = #create; guards = #command("submitGrievance");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "grievance.setGrievanceState"; resource = "grievance"; action = #approve; guards = #command("setGrievanceState");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // Withdrawing is the complainant's act, proved by the blinded key their own browser recomputes.
    { id = "grievance.withdrawGrievance"; resource = "grievance"; action = #reject; guards = #command("withdrawGrievance");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "incident.reportIncident"; resource = "incident"; action = #create; guards = #command("reportIncident");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "incident.assignIncident"; resource = "incident"; action = #update; guards = #command("assignIncident");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // Closing an injury report is a decision a regulator may read.
    { id = "incident.setIncidentState"; resource = "incident"; action = #close; guards = #command("setIncidentState");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "incident.addInvestigationNote"; resource = "incident"; action = #update; guards = #command("addInvestigationNote");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "milestone.addMilestone"; resource = "milestone"; action = #create; guards = #command("addMilestone");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "milestone.amendMilestone"; resource = "milestone"; action = #update; guards = #command("amendMilestone");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "milestone.setMilestoneState"; resource = "milestone"; action = #update; guards = #command("setMilestoneState");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Where somebody works and the number they are known by are facts payroll and attendance both read.
    { id = "employee_assignment.setEmployeeAssignment"; resource = "employee_assignment"; action = #update; guards = #command("setEmployeeAssignment");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "pending_employee.addPendingEmployee"; resource = "pending_employee"; action = #create; guards = #command("addPendingEmployee");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Approving somebody onto the roster admits them to the company.
    { id = "pending_employee.decidePendingEmployee"; resource = "pending_employee"; action = #approve; guards = #command("decidePendingEmployee");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // An import writes the roster wholesale.
    { id = "import_run.openImportRun"; resource = "import_run"; action = #create; guards = #command("openImportRun");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "import_run.importSlice"; resource = "import_run"; action = #update; guards = #command("importSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },

    // ── shifts, breaks, overtime, holidays, working from home and the devices ──
    { id = "shift_template.createShiftTemplate"; resource = "shift_template"; action = #create; guards = #command("createShiftTemplate");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "shift_template.setShiftTemplateActive"; resource = "shift_template"; action = #update; guards = #command("setShiftTemplateActive");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // A roster decides who works when, which is a record about a person.
    { id = "shift_assignment.assignShift"; resource = "shift_assignment"; action = #create; guards = #command("assignShift");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "shift_assignment.cancelShiftAssignment"; resource = "shift_assignment"; action = #update; guards = #command("cancelShiftAssignment");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "swap_request.requestShiftSwap"; resource = "swap_request"; action = #create; guards = #command("requestShiftSwap");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // The person asked to take the shift; their own consent, so not four eyes.
    { id = "swap_request.answerSwapRequest"; resource = "swap_request"; action = #approve; guards = #command("answerSwapRequest");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Moving a shift onto somebody else's day is decided by a third person.
    { id = "swap_request.decideShiftSwap"; resource = "swap_request"; action = #approve; guards = #command("decideShiftSwap");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "break_type.createBreakType"; resource = "break_type"; action = #create; guards = #command("createBreakType");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "break_type.setBreakTypeActive"; resource = "break_type"; action = #update; guards = #command("setBreakTypeActive");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "break_entry.startBreak"; resource = "break_entry"; action = #create; guards = #command("startBreak");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "break_entry.endBreak"; resource = "break_entry"; action = #update; guards = #command("endBreak");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "overtime_request.claimOvertime"; resource = "overtime_request"; action = #create; guards = #command("claimOvertime");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "overtime_request.submitOvertime"; resource = "overtime_request"; action = #update; guards = #command("submitOvertime");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "overtime_request.cancelOvertime"; resource = "overtime_request"; action = #update; guards = #command("cancelOvertime");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Approving overtime commits money: the claim is paid through payroll at the rate this act writes.
    { id = "overtime_request.decideOvertime"; resource = "overtime_request"; action = #approve; guards = #command("decideOvertime");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "comp_time_use.requestCompTimeUse"; resource = "comp_time_use"; action = #create; guards = #command("requestCompTimeUse");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Time in lieu is time bought with money already earned; granting it is a second person's act.
    { id = "comp_time_use.decideCompTimeUse"; resource = "comp_time_use"; action = #approve; guards = #command("decideCompTimeUse");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "company_holiday.createCompanyHoliday"; resource = "company_holiday"; action = #create; guards = #command("createCompanyHoliday");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "company_holiday.amendCompanyHoliday"; resource = "company_holiday"; action = #update; guards = #command("amendCompanyHoliday");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "company_holiday.withdrawCompanyHoliday"; resource = "company_holiday"; action = #update; guards = #command("withdrawCompanyHoliday");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "wfh_request.requestWorkFromHome"; resource = "wfh_request"; action = #create; guards = #command("requestWorkFromHome");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "wfh_request.decideWorkFromHome"; resource = "wfh_request"; action = #approve; guards = #command("decideWorkFromHome");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "wfh_request.cancelWorkFromHome"; resource = "wfh_request"; action = #update; guards = #command("cancelWorkFromHome");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // The working week decides what counts as late and what counts as overtime.
    { id = "working_hours.setWorkingHours"; resource = "working_hours"; action = #update; guards = #command("setWorkingHours");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // The policy decides what an absence costs, so it is money-moving even though it moves none itself.
    { id = "attendance_policy.setAttendancePolicy"; resource = "attendance_policy"; action = #update; guards = #command("setAttendancePolicy");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // The same: a ladder of deductions is money somebody will lose.
    { id = "late_tier.setLateDeductionTiers"; resource = "late_tier"; action = #update; guards = #command("setLateDeductionTiers");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // A device attests to attendance, which payroll is computed from. Admitting one is a four-eyes act.
    { id = "attendance_device.registerAttendanceDevice"; resource = "attendance_device"; action = #create; guards = #command("registerAttendanceDevice");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "attendance_device.amendAttendanceDevice"; resource = "attendance_device"; action = #update; guards = #command("amendAttendanceDevice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "attendance_device.revokeAttendanceDevice"; resource = "attendance_device"; action = #update; guards = #command("revokeAttendanceDevice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // THE DEVICE'S SIGNATURE IS THE AUTHORITY HERE, not a principal's role: the batch verifies
    // against a key the device registered, or it is refused. The row claims neither money nor a
    // record because a second pair of eyes on every batch would mean a person approving a
    // thousand punches a day, which is a rubber stamp and not a control; what stands in its place
    // is that nothing in the contract can forge one.
    { id = "ingest_receipt.ingestDeviceBatch"; resource = "ingest_receipt"; action = #create; guards = #command("ingestDeviceBatch");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Enrolled by the person themselves, so not four eyes.
    { id = "face_template.enrolFaceTemplate"; resource = "face_template"; action = #create; guards = #command("enrolFaceTemplate");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "face_template.withdrawFaceTemplate"; resource = "face_template"; action = #update; guards = #command("withdrawFaceTemplate");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "report_schedule.createReportSchedule"; resource = "report_schedule"; action = #create; guards = #command("createReportSchedule");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "report_schedule.setReportScheduleActive"; resource = "report_schedule"; action = #update; guards = #command("setReportScheduleActive");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "attendance_run.openReportRun"; resource = "attendance_run"; action = #create; guards = #command("openReportRun");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "attendance_run.runReportSlice"; resource = "attendance_run"; action = #update; guards = #command("runReportSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // The statutory overtime premium is money on every overtime claim a company ever approves.
    { id = "statutory_profile.declareOvertimePremiums"; resource = "statutory_profile"; action = #update; guards = #command("declareOvertimePremiums");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // ── recruitment: postings, applications, candidates, offers, checks ──
    { id = "job_posting.createJobPosting"; resource = "job_posting"; action = #create; guards = #command("createJobPosting");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "job_posting.amendJobPosting"; resource = "job_posting"; action = #update; guards = #command("amendJobPosting");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "job_posting.setPostingState"; resource = "job_posting"; action = #update; guards = #command("setPostingState");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // The ceilings and the price a stranger pays. It is not money-moving and it moves no record, but it is the only thing standing between an open page and an unmetered write, so it is a row of its own rather than a field on the company.
    { id = "careers_policy.setCareersPolicy"; resource = "careers_policy"; action = #update; guards = #command("setCareersPolicy");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // THE ONE SURFACE A STRANGER MAY REACH. Its authority is not a principal's role - there is no principal - it is the company's own ceiling and a proof of work; the catalogue row is what admits the surface at all.
    { id = "public_application.submitPublicApplication"; resource = "public_application"; action = #create; guards = #command("submitPublicApplication");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Erasing somebody's application destroys the key that opens it, and a second pair of eyes is what stops one person quietly deleting an inconvenient candidate.
    { id = "public_application.eraseApplication"; resource = "public_application"; action = #update; guards = #command("eraseApplication");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "application.applyToPosting"; resource = "application"; action = #create; guards = #command("applyToPosting");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Shortlisting or rejecting a colleague is a decision about a person's record.
    { id = "application.reviewApplication"; resource = "application"; action = #approve; guards = #command("reviewApplication");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "application.withdrawApplication"; resource = "application"; action = #update; guards = #command("withdrawApplication");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "candidate.addCandidate"; resource = "candidate"; action = #create; guards = #command("addCandidate");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "candidate.setCandidateStage"; resource = "candidate"; action = #update; guards = #command("setCandidateStage");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "candidate_note.addCandidateNote"; resource = "candidate_note"; action = #create; guards = #command("addCandidateNote");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // The same as erasing an application, and it takes the notes with it.
    { id = "candidate.eraseCandidate"; resource = "candidate"; action = #update; guards = #command("eraseCandidate");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "requisition.createRequisition"; resource = "requisition"; action = #create; guards = #command("createRequisition");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "requisition.amendRequisition"; resource = "requisition"; action = #update; guards = #command("amendRequisition");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "requisition.submitRequisition"; resource = "requisition"; action = #update; guards = #command("submitRequisition");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Approving a requisition commits a budget and a headcount.
    { id = "requisition.decideRequisition"; resource = "requisition"; action = #approve; guards = #command("decideRequisition");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "requisition.setRequisitionState"; resource = "requisition"; action = #update; guards = #command("setRequisitionState");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // An offer is a salary the company is prepared to pay, and it becomes the contract.
    { id = "offer.createOffer"; resource = "offer"; action = #create; guards = #command("createOffer");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // Sending it is what makes it an offer, and it names the person who may accept.
    { id = "offer.sendOffer"; resource = "offer"; action = #update; guards = #command("sendOffer");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // The CANDIDATE's own answer to their own offer, so not four eyes: there is only one person who may give it.
    { id = "offer.respondToOffer"; resource = "offer"; action = #approve; guards = #command("respondToOffer");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "offer.rescindOffer"; resource = "offer"; action = #update; guards = #command("rescindOffer");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // The candidate's own counter.
    { id = "counter_offer.submitCounterOffer"; resource = "counter_offer"; action = #create; guards = #command("submitCounterOffer");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Accepting a counter moves the offer's figures, which is money.
    { id = "counter_offer.decideCounterOffer"; resource = "counter_offer"; action = #approve; guards = #command("decideCounterOffer");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // The act that turns an accepted offer into an engagement, at the offer's own figures.
    { id = "offer.contractFromOffer"; resource = "offer"; action = #approve; guards = #command("contractFromOffer");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    { id = "recruit_run.openOfferExpirySweep"; resource = "recruit_run"; action = #create; guards = #command("openOfferExpirySweep");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "recruit_run.sweepOfferExpirySlice"; resource = "recruit_run"; action = #update; guards = #command("sweepOfferExpirySlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "interview.scheduleInterview"; resource = "interview"; action = #create; guards = #command("scheduleInterview");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "interview.setInterviewState"; resource = "interview"; action = #update; guards = #command("setInterviewState");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // An interviewer's own verdict on their own interview.
    { id = "scorecard.submitScorecard"; resource = "scorecard"; action = #create; guards = #command("submitScorecard");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // The decision a person's hiring turns on.
    { id = "interview.makeHiringDecision"; resource = "interview"; action = #approve; guards = #command("makeHiringDecision");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "referral.submitReferral"; resource = "referral"; action = #create; guards = #command("submitReferral");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Moving a referral to hired is what the reward is paid on.
    { id = "referral.setReferralState"; resource = "referral"; action = #approve; guards = #command("setReferralState");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "referral.withdrawReferral"; resource = "referral"; action = #update; guards = #command("withdrawReferral");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Money to an employee, outside payroll in the received tree and named to a payslip here.
    { id = "referral.payReferralReward"; resource = "referral"; action = #approve; guards = #command("payReferralReward");
      moneyMoving = true; recordMoving = true; dualByDefault = true },
    // The candidate's own signature, recorded by whoever collected it.
    { id = "check_consent.recordCheckConsent"; resource = "check_consent"; action = #create; guards = #command("recordCheckConsent");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // A criminal, credit or medical check about somebody who does not work here.
    { id = "background_check.createBackgroundCheck"; resource = "background_check"; action = #create; guards = #command("createBackgroundCheck");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    // What the provider said, which decides whether a person is hired.
    { id = "background_check.recordCheckResult"; resource = "background_check"; action = #approve; guards = #command("recordCheckResult");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "background_check.cancelBackgroundCheck"; resource = "background_check"; action = #update; guards = #command("cancelBackgroundCheck");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "recruit_run.openCheckRetentionSweep"; resource = "recruit_run"; action = #create; guards = #command("openCheckRetentionSweep");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "recruit_run.sweepCheckRetentionSlice"; resource = "recruit_run"; action = #update; guards = #command("sweepCheckRetentionSlice");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    { id = "exit_interview.createExitInterview"; resource = "exit_interview"; action = #create; guards = #command("createExitInterview");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // The leaver's own words, submitted by the leaver.
    { id = "exit_interview.submitExitInterview"; resource = "exit_interview"; action = #update; guards = #command("submitExitInterview");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
    // Reading what somebody said about their colleagues on the way out.
    { id = "exit_interview.acknowledgeExitInterview"; resource = "exit_interview"; action = #approve; guards = #command("acknowledgeExitInterview");
      moneyMoving = false; recordMoving = true; dualByDefault = true },
    { id = "talent_assessment.setTalentAssessment"; resource = "talent_assessment"; action = #update; guards = #command("setTalentAssessment");
      moneyMoving = false; recordMoving = false; dualByDefault = false },
  ];

  /// Every command family this build knows. The audit walks it against the catalogue in both
  /// directions.
  public let commandNames : [Text] = Cmd.FAMILIES;

  /// Every public update method of the contract. This one is the spine's own surface, and it
  /// grows with each domain; a method added without a catalogue row fails `validate`.
  public let methodNames : [Text] = [];

  public func validate() : P.Report { P.validate(catalogue, commandNames, methodNames) };

  public func summary() : P.Summary { P.summarise(catalogue) };

  public func requireFor(id : T.PermissionId) : { #ok : T.Permission; #err : T.Error } {
    P.require(catalogue, id)
  };

}
