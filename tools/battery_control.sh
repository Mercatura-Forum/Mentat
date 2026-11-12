#!/usr/bin/env bash
# The battery's negative control: remove one rule at a time and require the battery to notice.
#
# A battery that has only ever been seen green is a battery nobody knows is connected - and a
# battery written after the code it tests is exactly the one that passes for the wrong reason. So
# each rule the domain claims is removed on purpose in a scratch copy, and the battery must go red.
#
# THE FAULTS ARE THE CLAIMS. Every line below is a rule stated in the proposal of record, and its
# presence here is what makes the claim checkable rather than asserted.
#
# Attribution: Thebes Core Team. Licence: Apache 2.0.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# THE COPY MUST BE ABLE TO FIND THE KERNEL.
#
# `tools/packages.sh` looks for the kernel at `../thebes-kernel` relative to the tree it is in. A
# scratch copy under /tmp has no such sibling, so `packages.sh` exited 1, the source flags came back
# empty, and every battery compiled to "package core not defined" - RED, without the battery ever
# having run. Every "caught" this control reported before the compile check below was that, not a
# battery noticing anything. The kernel is now resolved once, here, and exported into every run.
KERNEL_PATH="$(cd "$HERE/../thebes-kernel" && pwd)" || { echo "CONTROL STOPPED: no kernel beside $HERE"; exit 1; }
export KERNEL="$KERNEL_PATH"
# AND THE MESSAGING HUB, the second sibling, for the payment battery: resolved the same way.
HUB_PATH="$(cd "$HERE/../thebes-example-open-banking-iso20022" 2>/dev/null && pwd)" \
  || HUB_PATH="$(cd "$HERE/../thebes-example-iso20022" 2>/dev/null && pwd)" \
  || { echo "CONTROL STOPPED: no messaging hub beside $HERE (thebes-example-open-banking-iso20022)"; exit 1; }
export HUB="$HUB_PATH"

# THE INJECTIONS RUN A FEW AT A TIME. Each one copies the tree, injects, compiles a battery and
# runs it - a minute or more each, and there are over two hundred. `try` only RECORDS an
# injection; the pool at the end of this file runs them, `CONTROL_JOBS` at a time (three unless
# told otherwise: a battery under wasmtime takes gigabytes), each into its own copy, and the
# verdicts are printed in the order the injections are written here so a reader can follow them.
CONTROL_JOBS="${CONTROL_JOBS:-3}"
mkdir -p "$TMP/jobs" "$TMP/results"
jobs_n=0

try() {
  local what="$1"; local test="$2"; shift 2
  jobs_n=$((jobs_n+1))
  local job; job="$(printf '%s/jobs/%03d' "$TMP" "$jobs_n")"
  {
    printf 'what=%q\ntest=%q\n' "$what" "$test"
    printf 'inject() { '; printf '%q ' "$@"; printf '; }\n'
  } > "$job"
}

# One injection, from its job file: the copy, the injection, the battery, the verdict. Writes the
# verdict to its results file; the pool prints them in order.
run_one() {
  local job="$1"; local result="$TMP/results/$(basename "$job")"
  local what test
  # shellcheck disable=SC1090
  . "$job"
  local broken="$TMP/$what"
  rm -rf "$broken"; mkdir -p "$broken"
  # EVERY FILE THE TREE HAS, not only the committed ones. `git ls-files` alone omits a file that
  # is written and not yet added - and a control that injects a fault into a file the copy does not
  # contain goes red because the file is missing, which is a catch for the wrong reason and no
  # catch at all. `--others --exclude-standard` adds the untracked, non-ignored files.
  ( cd "$HERE" && git ls-files -z --cached --others --exclude-standard | xargs -0 tar -c ) | tar -x -C "$broken"
  cp -r "$HERE/.mops" "$broken/.mops" 2>/dev/null || true
  # AND THE INJECTION ITSELF MUST SUCCEED. A `sed` against a file that is not there exits non-zero
  # and changes nothing; without this the control reads the subsequent redness as a catch.
  if ! ( cd "$broken" && inject ); then
    echo "CONTROL BROKEN: the $what injection command itself failed" > "$result"; return
  fi
  if diff -rq "$HERE/src" "$broken/src" > /dev/null 2>&1; then
    echo "CONTROL BROKEN: the $what injection changed nothing" > "$result"; return
  fi
  if ( cd "$broken" && TEST_OUT="$TMP/out-$what" ./test/run.sh "$test" > "$TMP/$what.log" 2>&1 ); then
    echo "MISSED: the battery stayed green without $what" > "$result"
  elif grep -q "^HOST COULD NOT RUN" "$TMP/$what.log"; then
    # NOT RUN IS NOT CAUGHT. wasmtime aborted before the battery's first instruction (the box at its
    # process limit) and kept aborting; the battery never saw the injected fault (tools/wasi_run.sh).
    { echo "CONTROL BROKEN: the host could not run the battery for $what"
      grep -A1 "^HOST COULD NOT RUN" "$TMP/$what.log" | head -2; } > "$result"
  elif grep -q "^COMPILE FAILED" "$TMP/$what.log"; then
    # RED FOR THE WRONG REASON. An injection that does not compile makes the battery fail without
    # the battery ever having run, which proves nothing about whether it would have noticed. This
    # has happened once already, and it is the same class as an injection that silently changes
    # nothing - so it is a MISS, not a catch.
    { echo "CONTROL BROKEN: the $what injection does not compile, so the battery never ran"
      grep -A2 "^COMPILE FAILED" "$TMP/$what.log" | head -3; } > "$result"
  else
    { echo "caught: $what"; grep -E "^FAIL: " "$TMP/$what.log" | head -2; } > "$result"
  fi
  rm -rf "$broken" "$TMP/out-$what"
}

# ── the foundation ────────────────────────────────────────────────────────────

# a slug taken twice: two companies on one login URL
try duplicate-slug-allowed Spine \
  sed -i 's|      case (?(id, _)) { return #err(#slugTaken { slug = f.slug; companyId = id }) };|      case (?(_id, _)) { };|' src/State.mo

# a refusal that writes before it refuses
try refusal-writes-first Spine \
  sed -i 's|    if (Text.size(f.name) == 0) return #err(#nameRequired);|    if (false) return #err(#nameRequired);|' src/State.mo

# ── the HR core ───────────────────────────────────────────────────────────────

# a second punch in with one already open - the check the received tree does not make
try second-open-punch-allowed HrCore \
  sed -i 's|      case (?(punchId, _)) { return #err(#alreadyOpenPunch { subject; punchId }) };|      case (?(_punchId, _)) { };|' src/HrFold.mo

# a person approving their own leave
try self-approved-leave HrCore \
  sed -i 's|    if (l.subject == c.caller) return #err(#selfDecision { subject = l.subject });|    if (false) return #err(#selfDecision { subject = l.subject });|' src/HrFold.mo

# a person deciding their own attendance correction
try self-decided-correction HrCore \
  sed -i 's|    if (k.subject == c.caller) return #err(#selfDecision { subject = k.subject });|    if (false) return #err(#selfDecision { subject = k.subject });|' src/HrFold.mo

# an org chart that can contain a cycle
try department-cycle-allowed HrCore \
  sed -i 's|    if (departmentWouldCycle(c.stores, departmentId, f.parentId)) {|    if (false and departmentWouldCycle(c.stores, departmentId, f.parentId)) {|' src/HrFold.mo

# a correction that OVERWRITES the punch instead of superseding it - what the received
# `updateAttendanceRecord` does
try correction-overwrites HrCore \
  sed -i 's|      correctedFrom = original.lastBlock; lastBlock = c.block;|      correctedFrom = 0; lastBlock = c.block;|' src/HrFold.mo

# an accrual slice applied person by person, so a refusal part way leaves some of it done - the
# shape `validatePicking` gets wrong with stock. The injection removes the PRE-CHECK, leaving the
# apply loop to meet the bad subject half way through.
#
# The first version of this line used a two-line `sed` pattern. `sed` works a line at a time, so it
# matched nothing, the injection silently did not happen, and the control would have reported the
# BATTERY as having missed a fault it was never shown - which is why `try` refuses a copy it cannot
# see a difference in.
try accrual-partially-applied HrCore \
  sed -i 's|        case null { return #err(#noSuchMembership { companyId; subject = p }) };|        case null { };|' src/HrFold.mo

# a standing amendment that does not resolve what it names
try unresolved-standing HrCore \
  sed -i 's|    switch (checkStanding(c, companyId, st, id)) { case (?r) return #err(r); case null {} };|    ignore checkStanding(c, companyId, st, id);|' src/HrFold.mo

# a fingerprint that misses a table: the quietest way the fold check stops checking
try fingerprint-misses-a-table HrCore \
  sed -i 's|    section<HrRows.Employee>(s, f, "employee", s.hr.employees, HrRows.employee,|    if (false) section<HrRows.Employee>(s, f, "employee", s.hr.employees, HrRows.employee,|' src/State.mo

# ── payroll ───────────────────────────────────────────────────────────────────

# the rounding residue accumulated as INTEGERS rather than exactly - which is the number zero
# written five different ways, and the first version of the engine did precisely this
try residue-accumulated-as-integers Payroll \
  sed -i 's|    { units = u; discarded = Dec.sub(exact, back, Dec.PREC) }|    { units = u; discarded = Dec.zero }|' src/PayEngine.mo

# A PAYSLIP WHOSE LINES AND TOTALS DISAGREE.
#
# The first version of this injection removed the identity CHECK - which changed nothing, because
# with a correct engine the identity held anyway and the battery had no inconsistent payslip to
# refuse. Removing a check is only observable when something would fail it. So the fault now breaks
# the ENGINE: the bonus line is written and the gross does not count it, and the fold's identity
# check is what must refuse the slice.
try payslip-identity-broken Payroll \
  sed -i 's|    if (i.bonus > 0) { List.add(lines, { kind = #earning; code = "BONUS"; amount = i.bonus }); gross += i.bonus };|    if (i.bonus > 0) { List.add(lines, { kind = #earning; code = "BONUS"; amount = i.bonus }) };|' src/PayEngine.mo

# a slice accepted with a plan hash that is not the run's, so a run becomes a function of who was
# added to the company while it was running
try plan-hash-not-checked Payroll \
  sed -i 's|    if (padHash(f.planHash) != run.planHash) return #err(#planHashMismatch { runId = f.runId });|    if (false) return #err(#planHashMismatch { runId = f.runId });|' src/PayFold.mo

# a person paid twice in one run, so a resumed slice is not idempotent
try paid-twice-allowed Payroll \
  sed -i 's|        case (?_) { return #err(#alreadyPaid { runId = f.runId; subject }) };|        case (?_) { };|' src/PayFold.mo

# somebody approving a run their own payslip is in
try self-approved-payroll Payroll \
  sed -i 's|      case (?_) { return #err(#approverIsInTheRun { subject = c.caller }) };|      case (?_) { };|' src/PayFold.mo

# a posting that declares a rounding difference the run did not produce - it balances perfectly and
# is wrong by exactly the amount nobody sees
try difference-not-checked Payroll \
  sed -i 's|      return #err(#differenceUnaccounted { expected; declared = differenceAmount });|      return #ok([runId]);|' src/PayFold.mo

# a bracket table that may have a gap in it
try bracket-gap-allowed Payroll \
  sed -i 's|      return #err(#bracketOutOfOrder { profileId = f.profileId; ordinal = f.ordinal; expected });|      return #ok([0]);|' src/PayFold.mo

# ── accounting ────────────────────────────────────────────────────────────────

# a sequence that skips a number - what a burnt number looks like from the series' side, and what
# the received `postMove` produces every time a put fails after the counter has moved
try sequence-gaps Accounting \
  sed -i 's|        journalId = m.journalId; fiscalYear = year; nextNumber = next + 1; lastBlock = c.block;|        journalId = m.journalId; fiscalYear = year; nextNumber = next + 2; lastBlock = c.block;|' src/AcctFold.mo

# a posting whose balance is taken from the proposal rather than recomputed from the rows about to
# become posted
try balance-not-recomputed Accounting \
  sed -i 's|    for ((_id, l) in lines.vals()) { debits += l.debit; credits += l.credit };|    for ((_id, l) in lines.vals()) { debits += l.debit; credits += l.debit };|' src/AcctFold.mo

# the maker posting their own move
try self-posting-allowed Accounting \
  sed -i 's|    if (m.proposedBy == c.caller) return #err(#selfPosting { maker = m.proposedBy });|    if (false) return #err(#selfPosting { maker = m.proposedBy });|' src/AcctFold.mo

# a proposal that does not balance
try unbalanced-proposal-allowed Accounting \
  sed -i 's|    if (debits != credits) return ?#unbalanced { debits; credits };|    if (false) return ?#unbalanced { debits; credits };|' src/AcctFold.mo

# a line against an account that has been deprecated - the received `addMoveLine` looks the account
# up not at all, so neither its existence nor its standing is checked
try deprecated-account-allowed Accounting \
  sed -i 's|      if (a.deprecated) return ?#accountDeprecated { accountId = l.accountId };|      if (false) return ?#accountDeprecated { accountId = l.accountId };|' src/AcctFold.mo

# a period lock that can move backwards, re-opening a filed year
try lock-moves-backwards Accounting \
  sed -i 's|        if (through < l.lockedThroughDay) {|        if (false) {|' src/AcctFold.mo

# a posted move that can be cancelled
try posted-move-cancellable Accounting \
  sed -i 's|    if (isPosted(m)) return #err(#moveIsPosted { moveId });|    if (false) return #err(#moveIsPosted { moveId });|' src/AcctFold.mo

# ── the month-end close ───────────────────────────────────────────────────────

# beginning a close that does not lock the period, so a move can be posted into a period being planned
try close-does-not-lock Close \
  sed -i 's|    writeLock(c, f.companyId, f.throughDay);|    if (false) writeLock(c, f.companyId, f.throughDay);|' src/AcctFold.mo

# the closing type open to the public proposal, so a reader could not tell the sweep from activity
try closing-type-proposable Close \
  sed -i 's|    if (f.moveType == #closing and not generated) return ?#closingIsTheFoldsAct;|    if (false) return ?#closingIsTheFoldsAct;|' src/AcctFold.mo

# the plan counting the sweep and its reversal, so a re-closed period totals more than its activity
try plan-counts-the-sweep Close \
  sed -i 's|      if (m.state == #posted and m.moveType != #closing) {|      if (m.state == #posted) {|' src/AcctFold.mo

# the plan counting a move that was proposed and never posted
try plan-counts-proposals Close \
  sed -i 's|      if (m.state == #posted and m.moveType != #closing) {|      if (m.moveType != #closing) {|' src/AcctFold.mo

# the planner posting the sweep
try planner-may-close Close \
  sed -i 's|    if (c.caller == run.plannedBy) return #err(#selfClosing { planner = run.plannedBy });|    if (false) return #err(#selfClosing { planner = run.plannedBy });|' src/AcctFold.mo

# a stated hash that is not checked against the plan
try plan-hash-not-checked Close \
  sed -i 's|    if (padHash(planHash) != run.planHash) return #err(#planHashMismatch { runId });|    if (false) return #err(#planHashMismatch { runId });|' src/AcctFold.mo

# the closer re-opening their own close
try closer-may-reopen Close \
  sed -i 's|    if (c.caller == run.closedBy) return #err(#selfReopening { closer = run.closedBy });|    if (false) return #err(#selfReopening { closer = run.closedBy });|' src/AcctFold.mo

# the re-opener posting the reversal
try reopener-may-reverse Close \
  sed -i 's|    if (c.caller == run.reopenedBy) return #err(#selfReversing { reopener = run.reopenedBy });|    if (false) return #err(#selfReversing { reopener = run.reopenedBy });|' src/AcctFold.mo

# any closed period re-opened, not only the latest - the lock then retreats over a later close
try any-close-reopens Close \
  sed -i 's|      case (?(latest, _)) { if (latest != runId) return #err(#notTheLatestClose { runId; latest }) };|      case (?(latest, _)) { if (false) return #err(#notTheLatestClose { runId; latest }) };|' src/AcctFold.mo

# periods that need not touch, so a day can be swept twice or never
try periods-need-not-touch Close \
  sed -i 's|        if (f.fromDay != last.throughDay + 1) return #err(#periodNotContiguous { expectedFrom = last.throughDay + 1; fromDay = f.fromDay });|        if (false) return #err(#periodNotContiguous { expectedFrom = last.throughDay + 1; fromDay = f.fromDay });|' src/AcctFold.mo

# a period closed before the calendar says it is over
try period-need-not-be-over Close \
  sed -i 's|    if (f.throughDay >= c.day) return #err(#periodNotOver { throughDay = f.throughDay; day = c.day });|    if (false) return #err(#periodNotOver { throughDay = f.throughDay; day = c.day });|' src/AcctFold.mo

# retained earnings on any account, not an equity one
try retained-earnings-any-type Close \
  sed -i 's|    if (re.accountType != #equity) return #err(#notAnEquityAccount { accountId = f.retainedEarningsAccountId });|    if (false) return #err(#notAnEquityAccount { accountId = f.retainedEarningsAccountId });|' src/AcctFold.mo

# the reversal re-posting the closing move instead of swapping its lines
try reversal-does-not-swap Close \
  sed -i 's|          debit = l.credit; credit = l.debit; amountCurrency = 0; taxId = l.taxId });|          debit = l.debit; credit = l.credit; amountCurrency = 0; taxId = l.taxId });|' src/AcctFold.mo

# the lock left at the period's end after the reversal, so the re-opened period cannot take a correction
try reopen-leaves-the-lock Close \
  sed -i 's|    if (lastPage) writeLock(c, companyId, run.lockBefore);|    if (false) writeLock(c, companyId, run.lockBefore);|' src/AcctFold.mo

# a cancelled plan - and a re-opened close that posted nothing - leaving the lock where the run put
# it; the one line serves both paths, so this injection removes it from both
try cancel-or-empty-reopen-leaves-the-lock Close \
  sed -i 's|    writeLock(c, companyId, run.lockBefore);|    if (false) writeLock(c, companyId, run.lockBefore);|' src/AcctFold.mo

# the lock by hand while a close is open, so a run can no longer put it back exactly
try hand-lock-while-closing Close \
  sed -i 's|      case (?(runId, _)) { return #err(#closeRunOpen { companyId; runId }) };|      case (?(runId, _)) { if (false) return #err(#closeRunOpen { companyId; runId }) };|' src/AcctFold.mo

# the sweep on the wrong side: an income account debited by the wrong difference
try sweep-side-wrong Close \
  sed -i 's|        let toDebit = if (x.credit > x.debit) x.credit - x.debit else 0;|        let toDebit = if (x.credit > x.debit) x.credit else 0;|' src/AcctFold.mo

# a full reversal slice closing the run, so a run with exactly a slice of closing moves is re-opened
# before its last move is reversed - the mailing's own received defect, in the close
try reversal-ends-at-a-full-slice Close \
  sed -i 's|    let lastPage = moves.size() < limit;|    let lastPage = moves.size() <= limit;|' src/AcctFold.mo

# ── statements ────────────────────────────────────────────────────────────────

# a statement over a window that is not locked, so a slice can see a posting another did not
try statement-window-unlocked Statement \
  sed -i 's|    if (f.throughDay > lock) return #err(#windowNotLocked { throughDay = f.throughDay; lockedThroughDay = lock });|    if (false) return #err(#windowNotLocked { throughDay = f.throughDay; lockedThroughDay = lock });|' src/AcctFold.mo

# a cumulative statement given a start, so a balance sheet shows a period rather than a position
try cumulative-statement-with-a-start Statement \
  sed -i 's|    if (f.kind != #incomeStatement and f.fromDay != 0) return #err(#cumulativeHasNoStart { kind = statementKindName(f.kind); fromDay = f.fromDay });|    if (false) return #err(#cumulativeHasNoStart { kind = statementKindName(f.kind); fromDay = f.fromDay });|' src/AcctFold.mo

# the income statement counting the sweep, so a closed period shows no result
try income-statement-counts-the-sweep Statement \
  sed -i 's|      let counted = m.state == #posted and (x.kind != #incomeStatement or m.moveType != #closing);|      let counted = m.state == #posted;|' src/AcctFold.mo

# the statement counting proposals, so a move nobody posted is in the figures
try statement-counts-proposals Statement \
  sed -i 's|      let counted = m.state == #posted and (x.kind != #incomeStatement or m.moveType != #closing);|      let counted = (x.kind != #incomeStatement or m.moveType != #closing);|' src/AcctFold.mo

# the balance sheet keeping the profit-and-loss accounts as lines instead of collapsing them
try balance-sheet-keeps-profit-and-loss-lines Statement \
  sed -i 's|            case (#balanceSheet) { add(if (pl) 0 else l.accountId, l.debit, l.credit) };|            case (#balanceSheet) { add(l.accountId, l.debit, l.credit) };|' src/AcctFold.mo

# the statement's hash without the tip, so a statement can be re-anchored to another log
try statement-hash-omits-the-tip Statement \
  sed -i 's|      Blob.toArray(tip), Blob.toArray(chain)\]))|      Blob.toArray(zero32()), Blob.toArray(chain)]))|' src/AcctFold.mo

# the statement sealed at no block
try statement-at-no-block Statement \
  sed -i 's|        x with state = #published; lines; cursorDay = x.throughDay; cursor = 0; atBlock = c.block; tip = c.tip;|        x with state = #published; lines; cursorDay = x.throughDay; cursor = 0; atBlock = 0; tip = c.tip;|' src/AcctFold.mo

# a full slice sealing the statement before the walk is done
try statement-sealed-at-a-full-slice Statement \
  sed -i 's|    let sealed = page.size() < limit;|    let sealed = page.size() <= limit;|' src/AcctFold.mo

# two statements built at once for one company
try two-statements-at-once Statement \
  sed -i 's|      case (?(statementId, _)) { return #err(#statementOpen { companyId = f.companyId; statementId }) };|      case (?(statementId, _)) { if (false) return #err(#statementOpen { companyId = f.companyId; statementId }) };|' src/AcctFold.mo

# a published statement sliced again, so its lines move after its hash was written
try published-statement-resliced Statement \
  sed -i 's|    if (x.state != #building) return #err(#statementNotInState { statementId; state = statementStateName(x.state); wanted = "building" });|    if (false) return #err(#statementNotInState { statementId; state = statementStateName(x.state); wanted = "building" });|' src/AcctFold.mo

# ── deferrals ─────────────────────────────────────────────────────────────────

# the residue dropped: every month the integer share, so the parts sum short of the amount
try deferral-residue-dropped Deferral \
  sed -i 's|    if (k + 1 == months) per + amount % months else per|    per|' src/AcctFold.mo

# months of thirty days instead of the civil calendar
try deferral-thirty-day-months Deferral \
  sed -i 's|    let (y, m, _) = CivilDate.toCivil(firstDay);|    return firstDay + 30 * k + 16; let (y, m, _) = CivilDate.toCivil(firstDay);|' src/AcctFold.mo

# the opener posting the recognitions
try deferral-opener-may-slice Deferral \
  sed -i 's|    if (c.caller == run.openedBy) return #err(#selfRecognising { opener = run.openedBy });|    if (false) return #err(#selfRecognising { opener = run.openedBy });|' src/AcctFold.mo

# a month in a locked period posted on its own day, into the lock
try deferral-posts-into-the-lock Deferral \
  sed -i 's|        let postedDay = if (scheduled <= lock) lock + 1 else scheduled;|        let postedDay = scheduled;|' src/AcctFold.mo

# months beyond the run's day posted early
try deferral-recognises-ahead Deferral \
  sed -i 's|      while (k < x.months and recognitionDay(x.firstDay, k) <= run.throughDay) {|      while (k < x.months) {|' src/AcctFold.mo

# a deferral never marked done, so it is walked and over-recognised by the next run
try deferral-never-done Deferral \
  sed -i 's|        state = if (recognized == x.months) #done else #active; lastBlock = c.block });|        state = #active; lastBlock = c.block });|' src/AcctFold.mo

# the kind no longer naming the account types
try deferral-accounts-untyped Deferral \
  sed -i 's|    if (not typed) return #err(#deferralAccounts { kind = deferralKindName(f.kind); deferred = accountTypeName(held.accountType); target = accountTypeName(target.accountType) });|    if (false) return #err(#deferralAccounts { kind = deferralKindName(f.kind); deferred = accountTypeName(held.accountType); target = accountTypeName(target.accountType) });|' src/AcctFold.mo

# the source move not required to carry the amount
try deferral-source-unchecked Deferral \
  sed -i 's|      if (carried < f.amount) return #err(#sourceMoveLacksTheAmount { moveId = f.sourceMoveId; accountId = f.deferredAccountId; amount = f.amount });|      if (false) return #err(#sourceMoveLacksTheAmount { moveId = f.sourceMoveId; accountId = f.deferredAccountId; amount = f.amount });|' src/AcctFold.mo

# the run through a day that has not come
try deferral-run-into-the-future Deferral \
  sed -i 's|    if (throughDay > c.day) return #err(#horizonNotReached { throughDay; day = c.day });|    if (false) return #err(#horizonNotReached { throughDay; day = c.day });|' src/AcctFold.mo

# a deferral with months posted cancelled, its recognitions orphaned
try deferral-cancelled-after-posting Deferral \
  sed -i 's|    if (x.recognized > 0) return #err(#deferralHasEntries { deferralId; recognized = x.recognized });|    if (false) return #err(#deferralHasEntries { deferralId; recognized = x.recognized });|' src/AcctFold.mo

# the sides swapped for unearned revenue: the liability credited again and income debited
try deferral-unearned-sides-swapped Deferral \
  sed -i 's|          case (#unearned) (x.deferredAccountId, x.targetAccountId);|          case (#unearned) (x.targetAccountId, x.deferredAccountId);|' src/AcctFold.mo

# ── revaluation ───────────────────────────────────────────────────────────────

# the exponents ignored: a three-decimal currency revalued as if it had two
try revaluation-ignores-exponents Revaluation \
  sed -i 's|    let d = 1_000_000 \* F.pow10(foreignExponent);|    let d = 1_000_000 * F.pow10(functionalExponent);|' src/AcctFold.mo

# rounding down instead of half to even
try revaluation-rounds-down Revaluation \
  sed -i 's|    if (r \* 2 > d) q + 1 else if (r \* 2 < d) q else if (q % 2 == 0) q else q + 1|    q|' src/AcctFold.mo

# the functional rounding unit ignored
try revaluation-ignores-the-unit Revaluation \
  sed -i 's|    let rounded = roundHalfEven(minor, unit) \* unit;|    let rounded = minor;|' src/AcctFold.mo

# the planner posting the revaluation
try revaluation-planner-may-post Revaluation \
  sed -i 's|    if (c.caller == run.plannedBy) return #err(#selfRevaluing { planner = run.plannedBy });|    if (false) return #err(#selfRevaluing { planner = run.plannedBy });|' src/AcctFold.mo

# the last close's revaluation never reversed, so a difference is counted twice
try revaluation-never-reversed Revaluation \
  sed -i 's|      let rows = unreversedRevaluationsAfter(c.acct, companyId, run.cursor, limit);|      let rows = unreversedRevaluationsAfter(c.acct, companyId, run.cursor, 0);|' src/AcctFold.mo

# the reversal dated the period's last day instead of its first
try revaluation-reversal-misdated Revaluation \
  sed -i 's|          companyId; journalId = orig.journalId; businessDay = run.fromDay; moveType = #entry; currency = functional; partnerId = 0;|          companyId; journalId = orig.journalId; businessDay = run.throughDay; moveType = #entry; currency = functional; partnerId = 0;|' src/AcctFold.mo

# accounts in the functional currency revalued too
try revaluation-of-functional-accounts Revaluation \
  sed -i 's|      if (isMonetary(a.accountType) and code != "" and code != functional and not a.deprecated) {|      if (isMonetary(a.accountType) and code != "" and not a.deprecated) {|' src/AcctFold.mo

# an account with no currency of its own treated as foreign, so the close refuses for a currency "" nobody declared
try revaluation-of-accounts-without-a-currency Revaluation \
  sed -i 's|      if (isMonetary(a.accountType) and code != "" and code != functional and not a.deprecated) {|      if (isMonetary(a.accountType) and code != functional and not a.deprecated) {|' src/AcctFold.mo

# the rate of any day, not the period's last
try revaluation-at-the-wrong-day Revaluation \
  sed -i 's|        let ?rate = c.rateOn(companyId, code, run.throughDay) else return #err(#noRateOn { code; day = run.throughDay });|        let ?rate = c.rateOn(companyId, code, run.fromDay) else return #err(#noRateOn { code; day = run.throughDay });|' src/AcctFold.mo

# the policy's accounts untyped
try revaluation-accounts-untyped Revaluation \
  sed -i 's|    if (gain.accountType != #income or loss.accountType != #expense) {|    if (false) {|' src/AcctFold.mo

# the sides swapped: a gain credited to the account
try revaluation-sides-swapped Revaluation \
  sed -i 's|          let lines : \[AF.LineFacts\] = if (difference > 0) \[|          let lines : [AF.LineFacts] = if (difference < 0) [|' src/AcctFold.mo

# ── fixed assets ──────────────────────────────────────────────────────────────

# the charge taken from the original base over all the months, never re-planned: after an
# impairment the months left would be charged as if nothing had been written down
try asset-charge-not-replanned Asset \
  sed -i 's|    if (k + 1 >= months) remaining else remaining / (months - k)|    if (k + 1 >= months) remaining else remaining / months|' src/AcctFold.mo

# months of thirty days instead of the civil calendar (the one month-end rule both schedules share)
try asset-thirty-day-months Asset \
  sed -i 's|    let (y, m, _) = CivilDate.toCivil(firstDay);|    return firstDay + 30 * k + 16; let (y, m, _) = CivilDate.toCivil(firstDay);|' src/AcctFold.mo

# the opener posting the charges
try asset-opener-may-slice Asset \
  sed -i 's|    if (c.caller == run.openedBy) return #err(#selfDepreciating { opener = run.openedBy });|    if (false) return #err(#selfDepreciating { opener = run.openedBy });|' src/AcctFold.mo

# a month in a locked period charged on its own day, into the lock
try asset-charges-into-the-lock Asset \
  sed -i 's|        let postedDay = if (scheduled <= lock) lock + 1 else scheduled;   // a locked month on the first open day|        let postedDay = scheduled;|' src/AcctFold.mo

# months beyond the run's day charged early
try asset-charges-ahead Asset \
  sed -i 's|      while (k < x.months and recognitionDay(x.firstDay, k) <= run.throughDay) {   // every month due, no month ahead|      while (k < x.months) {|' src/AcctFold.mo

# an asset never written down by its months, so it is walked and over-charged by the next run
try asset-never-written-down Asset \
  sed -i 's|        state = if (recognized == x.months) #depreciated else #active; lastBlock = c.block });|        state = #active; lastBlock = c.block });|' src/AcctFold.mo

# the three accounts no longer typed
try asset-accounts-untyped Asset \
  sed -i 's|    if (held.accountType != #asset or acc.accountType != #asset or exp.accountType != #expense or f.assetAccountId == f.accumulatedAccountId) {|    if (false) {|' src/AcctFold.mo

# the source move not required to carry the cost
try asset-source-unchecked Asset \
  sed -i 's|      if (carried < f.cost) return #err(#sourceMoveLacksTheAmount { moveId = f.sourceMoveId; accountId = f.assetAccountId; amount = f.cost });|      if (false) return #err(#sourceMoveLacksTheAmount { moveId = f.sourceMoveId; accountId = f.assetAccountId; amount = f.cost });|' src/AcctFold.mo

# a salvage value at or above the cost accepted
try asset-salvage-unchecked Asset \
  sed -i 's|    if (f.salvage >= f.cost) return #err(#salvageNotBelowCost { cost = f.cost; salvage = f.salvage });|    if (false) return #err(#salvageNotBelowCost { cost = f.cost; salvage = f.salvage });|' src/AcctFold.mo

# the proposer posting the event
try asset-proposer-may-post Asset \
  sed -i 's|    if (c.caller == ev.proposedBy) return #err(#selfPostingAssetEvent { proposer = ev.proposedBy });|    if (false) return #err(#selfPostingAssetEvent { proposer = ev.proposedBy });|' src/AcctFold.mo

# an impairment beyond what is left to depreciate accepted
try asset-impairment-unbounded Asset \
  sed -i 's|    if (f.amount > remaining) return #err(#impairmentExceedsRemaining { assetId = f.assetId; amount = f.amount; remaining });|    if (false) return #err(#impairmentExceedsRemaining { assetId = f.assetId; amount = f.amount; remaining });|' src/AcctFold.mo

# a disposal proposed with a charge still due before its day
try asset-disposal-before-the-charge Asset \
  sed -i 's|    switch (chargeDueBefore(x, f.day)) { case (?scheduledDay) return #err(#depreciationDue { assetId = f.assetId; scheduledDay }); case null {} };|    switch (null : ?Nat) { case (?scheduledDay) return #err(#depreciationDue { assetId = f.assetId; scheduledDay }); case null {} };|' src/AcctFold.mo

# the impairment posted but never recorded on the register row, so the months left are not re-planned
try asset-impairment-not-recorded Asset \
  sed -i 's|        let after = { x with impaired = x.impaired + ev.amount };|        let after = { x with impaired = x.impaired };|' src/AcctFold.mo

# a second event proposed while one is pending (the same rule in the impairment and the disposal: both lines)
try asset-pending-event-ignored Asset \
  sed -i 's|    switch (pendingEventOf(c.acct, f.assetId)) { case (?(eventId, _)) return #err(#assetEventPending { assetId = f.assetId; eventId }); case null {} };|    switch (null : ?(Nat, AR.AssetEvent)) { case (?(eventId, _)) return #err(#assetEventPending { assetId = f.assetId; eventId }); case null {} };|' src/AcctFold.mo

# a written-down asset still walked by the run, so it is charged months of nothing
try asset-written-down-still-walked Asset \
  sed -i 's|        keyOf = func(id : Nat, x : Asset) : ?Blob { if (x.state == #active) ?HR.companyKey(x.companyId, id) else null } },|        keyOf = func(id : Nat, x : Asset) : ?Blob { if (x.state != #disposed) ?HR.companyKey(x.companyId, id) else null } },|' src/AcctRows.mo

# ── expenses ──────────────────────────────────────────────────────────────────
# the claimant deciding their own claim. The APPROVAL is refused twice - by this fold and, behind
# it, by the ledger's four eyes on the move it would post in the claimant's name - so removing the
# fold's line alone leaves the battery green, which is the ledger's point and not a gap; the
# REJECTION posts nothing and has no ledger behind it, and that is the line removed here.
try expense-self-rejection Expense \
  sed -i 's|    if (cl.claimant == c.caller) return #err(#selfDeciding { claimant = cl.claimant });$|    if (false) return #err(#selfDeciding { claimant = cl.claimant });|' src/ExpFold.mo
# the claimant's own figure taken instead of the rate's
try expense-rate-carried-by-the-claimant Expense \
  sed -i 's|          if (computed != l.amount) return #err(#amountDisagrees { ordinal; stated = l.amount; computed });|          if (false) return #err(#amountDisagrees { ordinal; stated = l.amount; computed });|' src/ExpFold.mo
# the rate in force today, not on the line's day
try expense-rate-of-today-not-the-days Expense \
  sed -i 's|          let ?r = rateOn(c.exp, l.categoryId, l.day) else return #err(#noExpenseRate { ordinal; categoryId = l.categoryId; day = l.day });|          let ?r = rateOn(c.exp, l.categoryId, c.day) else return #err(#noExpenseRate { ordinal; categoryId = l.categoryId; day = l.day });|' src/ExpFold.mo
# half up instead of half to even
try expense-rounded-half-up Expense \
  sed -i 's|  public func amountOf(quantity : Nat, rate : Nat) : Nat { AcctFold.roundHalfEven(quantity \* rate, 1_000) };|  public func amountOf(quantity : Nat, rate : Nat) : Nat { (quantity * rate + 500) / 1_000 };|' src/ExpFold.mo
# a receipted cost accepted without a receipt
try expense-receipt-not-required Expense \
  sed -i 's|          if (l.documentId == F.NO_ID) return #err(#receiptRequired { ordinal });|          if (false) return #err(#receiptRequired { ordinal });|' src/ExpFold.mo
# somebody else's receipt
try expense-receipt-of-another Expense \
  sed -i 's|    if (d.subject != claimant) return ?#receiptNotTheClaimants { ordinal; documentId };|    if (false) return ?#receiptNotTheClaimants { ordinal; documentId };|' src/ExpFold.mo
# one receipt behind two claims
try expense-receipt-reused Expense \
  sed -i 's|    switch (claimOfReceipt(c.exp, documentId)) { case (?claimId) return ?#receiptAlreadyClaimed { ordinal; documentId; claimId }; case null {} };|    switch (null : ?Nat) { case (?claimId) return ?#receiptAlreadyClaimed { ordinal; documentId; claimId }; case null {} };|' src/ExpFold.mo
# an archived receipt accepted at the filing
try expense-archived-receipt-accepted Expense \
  sed -i 's|    if (d.state != #active) return ?#receiptNotActive { ordinal; documentId };|    if (false) return ?#receiptNotActive { ordinal; documentId };|' src/ExpFold.mo
# a receipt erased since the filing, and the approval posts anyway
try expense-erased-receipt-still-posts Expense \
  sed -i 's|        if (d.state != #active) return #err(#receiptNotActive { ordinal = l.ordinal; documentId = l.documentId });|        if (false) return #err(#receiptNotActive { ordinal = l.ordinal; documentId = l.documentId });|' src/ExpFold.mo
# the rate not read again at the approval
try expense-rate-not-reread-at-approval Expense \
  sed -i 's|        if (inForce != l.rate) return #err(#rateChangedSinceFiling { ordinal = l.ordinal; filed = l.rate; inForce });|        if (false) return #err(#rateChangedSinceFiling { ordinal = l.ordinal; filed = l.rate; inForce });|' src/ExpFold.mo
# a line dated in the future
try expense-line-dated-tomorrow Expense \
  sed -i 's|      if (l.day > c.day) return #err(#dayInTheFuture { ordinal; day = l.day; today = c.day });|      if (false) return #err(#dayInTheFuture { ordinal; day = l.day; today = c.day });|' src/ExpFold.mo
# the settlement posted in the claimant's name rather than the approver's. (The approver settling
# is refused twice - by this fold and by the ledger's four eyes, since the settlement is proposed in
# the approver's name - so that line alone is not an injection; the name the move carries is.)
try expense-settlement-not-in-the-approvers-name Expense \
  sed -i 's|    let out = switch (c.postGenerated(cl.decidedBy, facts)) { case (#err e) return #err(#acct e); case (#ok o) o };|    let out = switch (c.postGenerated(cl.claimant, facts)) { case (#err e) return #err(#acct e); case (#ok o) o };|' src/ExpFold.mo
# the claimant settling themself
try expense-claimant-may-settle Expense \
  sed -i 's|    if (cl.claimant == c.caller) return #err(#claimantSettling { claimant = cl.claimant });|    if (false) return #err(#claimantSettling { claimant = cl.claimant });|' src/ExpFold.mo
# a claim settled before it is approved
try expense-settled-unapproved Expense \
  sed -i 's|    if (cl.state != #approved) return #err(#claimNotInState { claimId; state = claimStateName(cl.state); wanted = "approved" });|    if (false) return #err(#claimNotInState { claimId; state = claimStateName(cl.state); wanted = "approved" });|' src/ExpFold.mo
# a claim approved whatever its state
try expense-approved-in-any-state Expense \
  sed -i 's|    if (cl.state != #submitted) return #err(#claimNotInState { claimId; state = claimStateName(cl.state); wanted = "submitted" });   // only a submitted claim is approved|    if (false) return #err(#claimNotInState { claimId; state = claimStateName(cl.state); wanted = "submitted" });   // only a submitted claim is approved|' src/ExpFold.mo
# the approval posts nothing
try expense-approval-posts-nothing Expense \
  sed -i 's|    let out = switch (c.postGenerated(cl.claimant, facts)) { case (#err e) return #err(#acct e); case (#ok o) o };|    let out : [Nat] = [0];|' src/ExpFold.mo
# a category posting to any account
try expense-category-account-untyped Expense \
  sed -i 's|    if (a.accountType != #expense) return #err(#categoryAccountNotExpense { account = accountTypeName(a.accountType) });|    if (false) return #err(#categoryAccountNotExpense { account = accountTypeName(a.accountType) });|' src/ExpFold.mo
# reimbursements accruing on any account
try expense-payable-untyped Expense \
  sed -i 's|    if (a.accountType != #payable) return #err(#payableNotPayable { account = accountTypeName(a.accountType) });|    if (false) return #err(#payableNotPayable { account = accountTypeName(a.accountType) });|' src/ExpFold.mo
# the total not the sum of the lines
try expense-total-not-the-sum Expense \
  sed -i 's|      total += amount;|      if (ordinal > 1) total += amount;|' src/ExpFold.mo
# a claim by somebody who is not a member
# Not injected, and why: expense-stranger-may-file - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).
# the bound on lines removed
try expense-lines-unbounded Expense \
  sed -i 's|    if (f.lines.size() > MAX_CLAIM_LINES) return #err(#tooManyLines { lines = f.lines.size(); max = MAX_CLAIM_LINES });|    if (false) return #err(#tooManyLines { lines = f.lines.size(); max = MAX_CLAIM_LINES });|' src/ExpFold.mo
# a claim filed where no policy says where it would post
try expense-filed-without-a-policy Expense \
  sed -i 's|    if (policyOf(c.exp, f.companyId) == null) return #err(#noExpensePolicy { companyId = f.companyId });|    if (false) return #err(#noExpensePolicy { companyId = f.companyId });|' src/ExpFold.mo
# a rate on a receipted category
try expense-rate-on-receipted Expense \
  sed -i 's|    if (cat.kind == #receipted) return #err(#rateOnReceipted { categoryId = f.categoryId });|    if (false) return #err(#rateOnReceipted { categoryId = f.categoryId });|' src/ExpFold.mo
# two rates effective from one day
try expense-two-rates-one-day Expense \
  sed -i 's|      case (?_) { return #err(#rateAlreadyOnThatDay { categoryId = f.categoryId; day = f.effectiveDay }) };|      case (?_) { };|' src/ExpFold.mo
# a reimbursement paid from income, or from the payable itself
try expense-settled-from-any-account Expense \
  sed -i 's|    if ((cash.accountType != #asset and cash.accountType != #liability) or cashAccountId == cl.payableAccountId) {|    if (false) {|' src/ExpFold.mo

# ── payments out over ISO 20022 ───────────────────────────────────────────────
# an IBAN taken without its check
try payment-iban-check-skipped Payment \
  sed -i 's|    if (not P8.validIban(iban)) return ?#ibanInvalid { iban };|    if (false) return ?#ibanInvalid { iban };|' src/PmtFold.mo
# an Egyptian IBAN of any shape
try payment-egyptian-shape-skipped Payment \
  sed -i 's|    if (P8.ibanCountry(iban) == "EG" and not P8.validEgyptianIbanShape(iban)) return ?#ibanShape { iban };|    if (false) return ?#ibanShape { iban };|' src/PmtFold.mo
# a BIC of any shape
try payment-bic-unchecked Payment \
  sed -i 's|    if (not P8.validBic(bic)) return ?#bicInvalid { bic };|    if (false) return ?#bicInvalid { bic };|' src/PmtFold.mo
# a bank account standing on any account
try payment-bank-on-any-account Payment \
  sed -i 's|    if (a.accountType != #asset) return #err(#bankAccountNotAnAsset { account = accountTypeName(a.accountType) });|    if (false) return #err(#bankAccountNotAnAsset { account = accountTypeName(a.accountType) });|' src/PmtFold.mo
# two accounts under one IBAN
try payment-iban-registered-twice Payment \
  sed -i 's|      case (?(id, _)) return #err(#ibanAlreadyRegistered { iban = f.iban; bankAccountId = id });|      case (?(_, _)) {};|' src/PmtFold.mo
# an account for a partner that is neither a supplier nor a customer
try payment-account-for-nobody Payment \
  sed -i 's|    if (not p.isSupplier and not p.isCustomer) return #err(#partnerIsNeither { partnerId = f.partnerId });|    if (false) return #err(#partnerIsNeither { partnerId = f.partnerId });|' src/PmtFold.mo
# a bill paid before its liability is posted
try payment-of-an-unposted-liability Payment \
  sed -i 's|    if (m.state != #posted) return #err(#billMoveNotPosted { billId = f.billId; moveId = b.moveId });|    if (false) return #err(#billMoveNotPosted { billId = f.billId; moveId = b.moveId });|' src/PmtFold.mo
# a bill paid twice
try payment-of-a-bill-twice Payment \
  sed -i 's|    switch (livePaymentOfBill(c.pmt, f.billId)) { case (?(paymentId, _)) return #err(#billAlreadyPaid { billId = f.billId; paymentId }); case null {} };|    switch (null : ?(Nat, PR.Payment)) { case (?(paymentId, _)) return #err(#billAlreadyPaid { billId = f.billId; paymentId }); case null {} };|' src/PmtFold.mo
# a bill paid from an account in another currency
try payment-currency-unchecked Payment \
  sed -i 's|    if (acct.currency != b.currency) return #err(#currencyDiffers { bill = textOf(b.currency); account = textOf(acct.currency) });|    if (false) return #err(#currencyDiffers { bill = textOf(b.currency); account = textOf(acct.currency) });|' src/PmtFold.mo
# a remittance the hub would refuse
try payment-remittance-unchecked Payment \
  sed -i 's|    if (not P8.textFits(f.remittance, P8.MAX_TEXT)) return #err(#textNotAcceptable { field = "remittance"; max = P8.MAX_TEXT });|    if (false) return #err(#textNotAcceptable { field = "remittance"; max = P8.MAX_TEXT });|' src/PmtFold.mo
# a UETR that is not version four: the hub refuses the message
try payment-uetr-not-version-four Payment \
  sed -i 's|      if (i == 6) (h\[6\] \& 0x0F) \| 0x40|      if (i == 6) h[6] \& 0x0F|' src/Pacs008.mo
# a header naming another message definition: the hub refuses the message
try payment-header-names-another-definition Payment \
  sed -i 's|    # elem(2, "MsgDefIdr", MESSAGE_DEFINITION)|    # elem(2, "MsgDefIdr", "pacs.008.001.09")|' src/Pacs008.mo
# the amount written in minor units as if they were whole: the hub reads a hundred times the sum
try payment-amount-misplaced-point Payment \
  sed -i 's|    Nat.toText(minorUnits / 100) # "." # two(minorUnits % 100)|    Nat.toText(minorUnits) # ".00"|' src/Pacs008.mo
# settlement by another method than the guideline's
try payment-settlement-method Payment \
  sed -i 's|  public let SETTLEMENT_METHOD : Text = "CLRG";|  public let SETTLEMENT_METHOD : Text = "INDA";|' src/Pacs008.mo
# the preparer recording the submission
try payment-submitted-by-the-preparer Payment \
  sed -i 's|    if (c.caller == p.preparedBy) return #err(#selfSubmitting { preparer = p.preparedBy });|    if (false) return #err(#selfSubmitting { preparer = p.preparedBy });|' src/PmtFold.mo
# the preparer recording the hub's word. (An acceptance by the preparer is refused by the ledger
# too, since the move is proposed in the preparer's name; the battery's rejection case is what this
# line alone defends, and is what goes red.)
try payment-result-by-the-preparer Payment \
  sed -i 's|    if (c.caller == p.preparedBy) return #err(#selfRecording { preparer = p.preparedBy });|    if (false) return #err(#selfRecording { preparer = p.preparedBy });|' src/PmtFold.mo
# a submission naming another fingerprint
try payment-submission-fingerprint-unchecked Payment \
  sed -i 's|    if (payloadHash != p.payloadHash) return #err(#payloadMoved { paymentId });|    if (false) return #err(#payloadMoved { paymentId });|' src/PmtFold.mo
# a result naming another fingerprint
try payment-result-fingerprint-unchecked Payment \
  sed -i 's|    if (f.payloadHash != p.payloadHash) return #err(#payloadMoved { paymentId = f.paymentId });|    if (false) return #err(#payloadMoved { paymentId = f.paymentId });|' src/PmtFold.mo
# a rejection with no reason
try payment-rejected-without-a-reason Payment \
  sed -i 's|      if (Text.size(f.reason) == 0) return #err(#reasonRequired);|      if (false) return #err(#reasonRequired);|' src/PmtFold.mo
# a rejection that posts anyway
try payment-rejection-posts Payment \
  sed -i 's|    if (not f.accepted) {|    if (false) {|' src/PmtFold.mo
# the hub's word on a payment nobody submitted
try payment-result-before-submission Payment \
  sed -i 's|    if (p.state != #submitted) return #err(#paymentNotInState { paymentId = f.paymentId; state = stateName(p.state); wanted = "submitted" });|    if (false) return #err(#paymentNotInState { paymentId = f.paymentId; state = stateName(p.state); wanted = "submitted" });|' src/PmtFold.mo
# a payment withdrawn in any state
try payment-withdrawn-in-any-state Payment \
  sed -i 's|    if (p.state != #prepared) return #err(#paymentNotInState { paymentId; state = stateName(p.state); wanted = "prepared" });   // only a prepared payment is withdrawn|    if (false) return #err(#paymentNotInState { paymentId; state = stateName(p.state); wanted = "prepared" });   // only a prepared payment is withdrawn|' src/PmtFold.mo
# the acceptance posts nothing
try payment-acceptance-posts-nothing Payment \
  sed -i 's|    let out = switch (c.postGenerated(p.preparedBy, facts)) { case (#err e) return #err(#acct e); case (#ok o) o };|    let out : [Nat] = [0];|' src/PmtFold.mo

# ── bank statements in from a camt.053 ────────────────────────────────────────
# a statement for an account nobody registered
try camt-account-unchecked Camt \
  sed -i 's|    let ?(_, accountCurrency) = c.accountOfIban(companyId, iban) else return #err(#camtAccountUnknown { iban });|    let (_, accountCurrency) = switch (c.accountOfIban(companyId, iban)) { case (?x) x; case null (0, currency0(stmt)) };|; s|  public func importCamt053(c : Ctx, companyId : Nat, journalId : Nat, xml : Blob) : Outcome {|  func currency0(stmt : Xml.Element) : Text { switch (Xml.textAt(stmt, ["Acct", "Ccy"])) { case (?t) Xml.trim(t); case null "" } };\n  public func importCamt053(c : Ctx, companyId : Nat, journalId : Nat, xml : Blob) : Outcome {|' src/FinFold.mo
# a statement in a currency that is not the account's
try camt-currency-unchecked Camt \
  sed -i 's|    if (currency != accountCurrency) return #err(#camtCurrency { statement = currency; account = accountCurrency });|    if (false) return #err(#camtCurrency { statement = currency; account = accountCurrency });|' src/FinFold.mo
# an entry in another currency taken as if it were in the statement's
try camt-entry-currency-unchecked Camt \
  sed -i 's|      case (?ccy) { if (ccy != currency) return bad("Amt in " # ccy # ", the statement in " # currency) };|      case (?_) {};|' src/FinFold.mo
# a debit read as a credit: the sign thrown away
try camt-debit-read-as-credit Camt \
  sed -i 's|    #ok({ day; amount = if (credit) amount else -amount; ref; partnerId })|    #ok({ day; amount = amount; ref; partnerId })|' src/FinFold.mo
# a pending entry taken as a line
try camt-pending-entry-taken Camt \
  sed -i 's|      case (?st) { if (Xml.trim(st) != "BOOK") return bad("status " # Xml.trim(st) # ": only a booked entry is a statement line") };|      case (?_) {};|' src/FinFold.mo
# an entry of nothing taken as a line
try camt-entry-of-nothing Camt \
  sed -i 's|    if (amount == 0) return bad("an entry of nothing");|    if (false) return bad("an entry of nothing");|' src/FinFold.mo
# two statements in one message, the first taken
try camt-two-statements-taken Camt \
  sed -i 's|    if (stmts.size() != 1) return #err(#camtShape { detail = Nat.toText(stmts.size()) # " Stmt elements; this system imports one statement per message" });|    if (stmts.size() == 0) return #err(#camtShape { detail = "no Stmt" });|' src/FinFold.mo
# a statement with no entry taken
try camt-no-entries-taken Camt \
  sed -i 's|    if (entries.size() == 0) return #err(#camtShape { detail = "a statement with no entry" });|    if (false) return #err(#camtShape { detail = "a statement with no entry" });|' src/FinFold.mo
# the counterparty never looked up: every line from nobody known, so the run matches nothing
try camt-counterparty-ignored Camt \
  sed -i 's|          case (?iban) { switch (c.partnerOfIban(companyId, Xml.trim(iban))) { case (?pid) pid; case null F.NO_ID } };|          case (?_) F.NO_ID;|' src/FinFold.mo
# the end-to-end id never read: every line referenced by the bank's entry reference
try camt-reference-ignored Camt \
  sed -i 's|      case (?t) { switch (Xml.textAt(t, \["Refs", "EndToEndId"\])) { case (?r) Xml.trim(r); case null { switch (Xml.textAt(e, \["NtryRef"\])) { case (?r) Xml.trim(r); case null "" } } } };|      case (?_) { switch (Xml.textAt(e, ["NtryRef"])) { case (?r) Xml.trim(r); case null "" } };|' src/FinFold.mo
# the closing balance declared taken from the opening
try camt-closing-is-the-opening Camt \
  sed -i 's|      balanceStart = F.zig(opening); balanceEndDeclared = F.zig(closing); balanceEndComputed = F.zig(computed);|      balanceStart = F.zig(opening); balanceEndDeclared = F.zig(opening); balanceEndComputed = F.zig(computed);|' src/FinFold.mo
# the size bound removed: a message past what a command carries
try camt-size-unbounded Camt \
  sed -i 's|    if (xml.size() > MAX_CAMT_BYTES) return #err(#camtTooLarge { bytes = xml.size(); max = MAX_CAMT_BYTES });|    if (false) return #err(#camtTooLarge { bytes = xml.size(); max = MAX_CAMT_BYTES });|' src/FinFold.mo
# an amount finer than the currency taken, rounded by truncation
try camt-amount-finer-than-the-currency Camt \
  sed -i 's|        if (seenPoint) { if (fracDigits >= exponent) return null; frac := frac \* 10 + d; fracDigits += 1 }|        if (seenPoint) { if (fracDigits < exponent) { frac := frac * 10 + d; fracDigits += 1 } }|' src/FinFold.mo

# ── credit terms on parties ───────────────────────────────────────────────────

# the limit never checked: a sale past it confirmed
try credit-limit-unchecked Credit \
  sed -i 's|        if (t.limit > 0 and t.exposure + amount > t.limit) return ?#creditLimitExceeded { partnerId; limit = t.limit; exposure = t.exposure; asked = amount };|        if (false) return ?#creditLimitExceeded { partnerId; limit = t.limit; exposure = t.exposure; asked = amount };|' src/CrdFold.mo
# a sale that reaches the limit exactly refused
try credit-limit-off-by-one Credit \
  sed -i 's|        if (t.limit > 0 and t.exposure + amount > t.limit) return|        if (t.limit > 0 and t.exposure + amount >= t.limit) return|' src/CrdFold.mo
# a confirmed sale not reserved: the exposure never moves
try credit-sale-not-reserved Credit \
  sed -i 's|    if (o.direction == #sale) c.creditReserve(companyId, o.partnerId, orderId, o.amountTotal);|    ignore o.amountTotal;|' src/OrderFold.mo
# the untaxed total reserved, not the total
try credit-tax-not-reserved Credit \
  sed -i 's|    if (o.direction == #sale) c.creditReserve(companyId, o.partnerId, orderId, o.amountTotal);|    if (o.direction == #sale) c.creditReserve(companyId, o.partnerId, orderId, o.amountUntaxed);|' src/OrderFold.mo
# a purchase reserved against the supplier as if it were a sale
try credit-purchase-reserved Credit \
  sed -i 's|    if (o.direction == #sale) c.creditReserve(companyId, o.partnerId, orderId, o.amountTotal);|    c.creditReserve(companyId, o.partnerId, orderId, o.amountTotal);|' src/OrderFold.mo
# a cancelled order keeps its room
try credit-cancel-keeps-the-room Credit \
  sed -i 's|    c.creditRelease(orderId);|    ignore orderId;|' src/OrderFold.mo
# the due day the invoice's day, the term ignored
try credit-due-day-is-the-invoice-day Credit \
  sed -i 's|          x with state = #open; moveId; dueDay = day + termDaysOf(c.crd, x.companyId, x.partnerId); lastBlock = c.block });|          x with state = #open; moveId; dueDay = day; lastBlock = c.block });|' src/CrdFold.mo
# the bill due the day it is matched
try credit-bill-due-today Credit \
  sed -i 's|amount; settled = 0; dueDay = day + termDaysOf(c.crd, companyId, partnerId);|amount; settled = 0; dueDay = day;|' src/CrdFold.mo
# a bank line reconciled to the invoice settles nothing
try credit-settlement-ignored Credit \
  sed -i 's|    c.creditSettled(moveId, amount);|    ignore (moveId, amount);|' src/FinFold.mo
# a match undone leaves the item settled
try credit-unsettle-ignored Credit \
  sed -i 's|    c.creditUnsettled(r.moveId, r.amount);|    ignore r.moveId;|' src/FinFold.mo
# the payment the hub accepted leaves the bill owed
try credit-payment-does-not-settle Credit \
  sed -i 's|    c.creditSettled(b.moveId, p.amount);|    ignore b.moveId;|' src/PmtFold.mo
# a settled item still found by its move
try credit-settled-item-still-live Credit \
  sed -i 's|        keyOf = func(_id : Nat, x : OpenItem) : ?Blob { if (x.moveId != 0 and isLive(x.state)) ?idKey(x.moveId) else null } },|        keyOf = func(_id : Nat, x : OpenItem) : ?Blob { if (x.moveId != 0) ?idKey(x.moveId) else null } },|' src/CrdRows.mo
# an item written for a partner without terms: an account that began before its terms
try credit-item-before-the-terms Credit \
  sed -i 's|    if (termsOf(c.crd, companyId, partnerId) == null) return;|    ignore termsOf(c.crd, companyId, partnerId);|' src/CrdFold.mo
# charges credited to any account
try credit-income-account-untyped Credit \
  sed -i 's|    if (a.accountType != #income) return #err(#incomeAccountNotIncome { account = accountTypeName(a.accountType) });|    if (false) return #err(#incomeAccountNotIncome { account = accountTypeName(a.accountType) });|' src/CrdFold.mo
# the late charge charged on every run
try credit-late-charge-twice Credit \
  sed -i 's|            let lateCharge = if (t.lateCharge > 0 and not x.lateCharged) t.lateCharge else 0;|            let lateCharge = t.lateCharge;|' src/CrdFold.mo
# interest rounded half up
try credit-interest-rounded-half-up Credit \
  sed -i 's|    AcctFold.roundHalfEven(outstanding \* rateHundredthsOfBp \* days, MAX_RATE \* DAYS_IN_YEAR)|    (outstanding * rateHundredthsOfBp * days * 2 + MAX_RATE * DAYS_IN_YEAR) / (2 * MAX_RATE * DAYS_IN_YEAR)|' src/CrdFold.mo
# interest counted from the due day every run, the last charge forgotten
try credit-interest-from-the-due-day-again Credit \
  sed -i 's|            let from = if (x.chargedThrough > x.dueDay) x.chargedThrough else x.dueDay;|            let from = x.dueDay;|' src/CrdFold.mo
# interest on the whole invoice, not on what is outstanding
try credit-interest-on-the-whole Credit \
  sed -i 's|            let outstanding = outstandingOf(x);|            let outstanding = x.amount;|' src/CrdFold.mo
# the grace ignored: an item inside it charged
try credit-grace-ignored Credit \
  sed -i 's|          if (x.dueDay + t.graceDays < run.throughDay) {|          if (x.dueDay < run.throughDay) {|' src/CrdFold.mo
# a payable walked and charged like a receivable
try credit-payable-charged Credit \
  sed -i 's|        keyOf = func(id : Nat, x : OpenItem) : ?Blob { if (x.kind == #receivable and x.state == #open) ?HR.companyKey(x.companyId, id) else null } },|        keyOf = func(id : Nat, x : OpenItem) : ?Blob { if (x.state == #open) ?HR.companyKey(x.companyId, id) else null } },|' src/CrdRows.mo
# a slice under another company's name
# (the opener posting the charges is not injected here: the ledger's own four eyes, `checkGenerated`,
# refuses the same act a second time, so removing the fold's check alone leaves the battery green - 
# the same double defence the expense and payment folds have)
try credit-slice-under-the-wrong-company Credit \
  sed -i 's|    if (run.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run.companyId });|    if (false) return #err(#wrongCompany { expected = companyId; found = run.companyId });|' src/CrdFold.mo
# a run through a day that has not come
try credit-run-before-its-day Credit \
  sed -i 's|    if (throughDay > c.day) return #err(#horizonNotReached { throughDay; day = c.day });|    if (false) return #err(#horizonNotReached { throughDay; day = c.day });|' src/CrdFold.mo
# a run into the locked period opened
try credit-run-into-the-lock Credit \
  sed -i 's|      case (?(_, l)) { if (throughDay <= l.lockedThroughDay) return #err(#periodLocked { throughDay; lockedThroughDay = l.lockedThroughDay }) };|      case (?(_, l)) { ignore l };|' src/CrdFold.mo
# a second run while one is open
try credit-second-run-while-open Credit \
  sed -i 's|    switch (openRunOf(c.crd, companyId)) { case (?(runId, _)) return #err(#interestRunOpen { companyId; runId }); case null {} };|    ignore openRunOf(c.crd, companyId);|' src/CrdFold.mo
# a slice of nothing, or past the page
try credit-slice-unbounded Credit \
  sed -i 's|    if (limit == 0 or limit > Page.MAX_LIMIT) return #err(#sliceBound { limit; max = Page.MAX_LIMIT });|    if (false) return #err(#sliceBound { limit; max = Page.MAX_LIMIT });|' src/CrdFold.mo
# the item not advanced: a charged item charged for the same days again
try credit-charged-through-not-advanced Credit \
  sed -i 's|        chargedThrough = run.throughDay; lastBlock = c.block });|        chargedThrough = x.chargedThrough; lastBlock = c.block });|' src/CrdFold.mo
# the fingerprint over an empty item store: an item changed without a block goes unnoticed
try credit-fingerprint-misses-the-items Credit \
  sed -i 's|    section<CrdRows.OpenItem>(s, f, "open_item", s.crd.items, CrdRows.openItem,|    section<CrdRows.OpenItem>(s, f, "open_item", RowStore.newStore<CrdRows.OpenItem>(CrdRows.openItem), CrdRows.openItem,|' src/State.mo

# ── consolidation ─────────────────────────────────────────────────────────────

# a member missing: fewer statements than standing members accepted
try consolidation-member-missing-accepted Consolidation \
  sed -i 's|    if (f.members.size() != standing.size()) return #err(#membersMismatch { given = f.members.size(); standing = standing.size() });|    if (false) return #err(#membersMismatch { given = f.members.size(); standing = standing.size() });|' src/GrpFold.mo
# a member named twice accepted
try consolidation-member-repeated-accepted Consolidation \
  sed -i 's|      while (j < i) { if (f.members\[j\].companyId == ms.companyId) return #err(#memberRepeated { companyId = ms.companyId }); j += 1 };|      while (j < i) { j += 1 };|' src/GrpFold.mo
# another company's statement accepted under a member's name
try consolidation-stranger-statement-accepted Consolidation \
  sed -i 's|      if (x.companyId != ms.companyId) return #err(#wrongCompany { expected = ms.companyId; found = x.companyId });|      if (false) return #err(#wrongCompany { expected = ms.companyId; found = x.companyId });|' src/GrpFold.mo
# a statement still being built accepted
try consolidation-building-statement-accepted Consolidation \
  sed -i 's|      if (x.state != #published) return #err(#statementNotPublished { statementId = ms.statementId; state = statementStateName(x.state) });|      if (false) return #err(#statementNotPublished { statementId = ms.statementId; state = statementStateName(x.state) });|' src/GrpFold.mo
# a statement of another kind accepted
try consolidation-kind-mismatch-accepted Consolidation \
  sed -i 's|      if (x.kind != f.kind) return #err(#statementKindMismatch { statementId = ms.statementId; kind = kindName(x.kind); wanted = kindName(f.kind) });|      if (false) return #err(#statementKindMismatch { statementId = ms.statementId; kind = kindName(x.kind); wanted = kindName(f.kind) });|' src/GrpFold.mo
# a statement over another window accepted
try consolidation-window-mismatch-accepted Consolidation \
  sed -i 's|      if (x.fromDay != f.fromDay or x.throughDay != f.throughDay) return #err(#statementWindowMismatch { statementId = ms.statementId; fromDay = x.fromDay; throughDay = x.throughDay });|      if (false) return #err(#statementWindowMismatch { statementId = ms.statementId; fromDay = x.fromDay; throughDay = x.throughDay });|' src/GrpFold.mo
# the parent declared but not standing as a member
# (a cumulative consolidation given a start is not injected: no member statement can be a trial
# balance or a balance sheet with a start, because the ledger refuses one, so the window check
# refuses the same act a second time and removing the fold's own check alone leaves the battery green)
try consolidation-parent-not-a-member Consolidation \
  sed -i 's|        RowStore.put<GR.GroupMember>(c.grp.members, GR.groupMember, mid, { groupId = id; companyId = f.companyId; isActive = true; lastBlock = c.block });|        RowStore.put<GR.GroupMember>(c.grp.members, GR.groupMember, mid, { groupId = id; companyId = f.companyId; isActive = false; lastBlock = c.block });|' src/GrpFold.mo
# a second consolidation while one is being built, and a link made meanwhile: the same line in both
try consolidation-second-while-open Consolidation \
  sed -i 's|    switch (openConsolidationOf(c.grp, f.groupId)) { case (?(consolidationId, _)) return #err(#consolidationOpen { groupId = f.groupId; consolidationId }); case null {} };|    ignore openConsolidationOf(c.grp, f.groupId);|' src/GrpFold.mo
# the membership and the links not frozen while one is being built: a member added, removed, a link undone
try consolidation-membership-not-frozen Consolidation \
  sed -i 's|    switch (openConsolidationOf(c.grp, groupId)) { case (?(consolidationId, _)) return #err(#consolidationOpen { groupId; consolidationId }); case null {} };|    ignore openConsolidationOf(c.grp, groupId);|' src/GrpFold.mo
# the parent removed from its own group
try consolidation-parent-removable Consolidation \
  sed -i 's|    if (companyId == g.companyId) return #err(#parentStays { groupId; companyId });|    if (false) return #err(#parentStays { groupId; companyId });|' src/GrpFold.mo
# a member removed while a link names it
try consolidation-member-with-links-removed Consolidation \
  sed -i 's|    if (links > 0) return #err(#memberHasLinks { groupId; companyId; links });|    if (false) return #err(#memberHasLinks { groupId; companyId; links });|' src/GrpFold.mo
# a member standing twice
try consolidation-member-stands-twice Consolidation \
  sed -i 's|    switch (memberOf(c.grp, groupId, companyId)) { case (?_) return #err(#alreadyAMember { groupId; companyId }); case null {} };|    ignore memberOf(c.grp, groupId, companyId);|' src/GrpFold.mo
# a member removed and added again on a new row, not its old one
try consolidation-removed-member-on-a-new-row Consolidation \
  sed -i 's|    for ((id, m) in memberRowsOf(c.grp, groupId).vals()) { if (m.companyId == companyId and not m.isActive) rowId := id };|    ignore memberRowsOf(c.grp, groupId);|' src/GrpFold.mo
# a company as its own counterparty
try consolidation-link-to-self Consolidation \
  sed -i 's|    if (f.companyId == f.counterpartyId) return #err(#linkToSelf { companyId = f.companyId });|    if (false) return #err(#linkToSelf { companyId = f.companyId });|' src/GrpFold.mo
# a counterparty that is not a member
try consolidation-link-to-a-stranger Consolidation \
  sed -i 's|    if (memberOf(c.grp, f.groupId, f.counterpartyId) == null) return #err(#notAMember { groupId = f.groupId; companyId = f.counterpartyId });|    if (false) return #err(#notAMember { groupId = f.groupId; companyId = f.counterpartyId });|' src/GrpFold.mo
# a partner of another company's books linked
try consolidation-foreign-partner-linked Consolidation \
  sed -i 's|    if (p.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });|    if (false) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });|' src/GrpFold.mo
# the difference to any account
try consolidation-difference-account-untyped Consolidation \
  sed -i 's|    if (a.accountType != #equity) return #err(#differenceAccountNotEquity { account = accountTypeName(a.accountType) });|    if (false) return #err(#differenceAccountNotEquity { account = accountTypeName(a.accountType) });|' src/GrpFold.mo
# every line naming a group company eliminated, cash and tax among them
try consolidation-cash-eliminated Consolidation \
  sed -i 's|                    if (isIntercompany(t) and (x.kind != #incomeStatement or pl)) {|                    if (x.kind != #incomeStatement or pl) {|' src/GrpFold.mo
# the balances eliminated on an income statement
try consolidation-balance-eliminated-on-income-statement Consolidation \
  sed -i 's|                    if (isIntercompany(t) and (x.kind != #incomeStatement or pl)) {|                    if (isIntercompany(t)) {|' src/GrpFold.mo
# no link ever found: nothing eliminated
try consolidation-links-never-found Consolidation \
  sed -i 's|    let k = GR.linkKey(groupId, companyId, partnerId);|    let k = GR.linkKey(groupId, companyId, 0);|' src/GrpFold.mo
# the reversal not reversed: the intercompany line added again instead
try consolidation-reversal-not-reversed Consolidation \
  sed -i 's|                      addPendingElimination(pendingEliminations, member, lk.counterpartyId, code, l.credit, l.debit);|                      addPendingElimination(pendingEliminations, member, lk.counterpartyId, code, l.debit, l.credit);|' src/GrpFold.mo
# a proposal never posted counted
try consolidation-unposted-move-counted Consolidation \
  sed -i 's|          let counted = m.state == #posted and (x.kind != #incomeStatement or m.moveType != #closing);|          let counted = (x.kind != #incomeStatement or m.moveType != #closing);|' src/GrpFold.mo
# the difference dropped: a trial balance that does not balance
try consolidation-difference-dropped Consolidation \
  sed -i 's|              if (x.kind != #incomeStatement and diff != 0) {|              if (false) {|' src/GrpFold.mo
# a difference line on an income statement
try consolidation-difference-on-income-statement Consolidation \
  sed -i 's|              if (x.kind != #incomeStatement and diff != 0) {|              if (diff != 0) {|' src/GrpFold.mo
# the result line stepped over when a member statement is gathered - the fault this extension met
try consolidation-result-line-skipped Consolidation \
  sed -i 's|    let lo = AR.closeLineKey(statementId, fromAccount);|    let lo = AR.closeLineKey(statementId, fromAccount + 1);|' src/GrpFold.mo
# a member's lines summed into the result line, not by code
try consolidation-gathered-into-one-line Consolidation \
  sed -i 's|          addPending(pending, code, l.debit, l.credit);|          addPending(pending, GR.zeroCode(), l.debit, l.credit);|' src/GrpFold.mo
# the tip not carried
try consolidation-tip-not-carried Consolidation \
  sed -i 's|                difference = if (x.kind == #incomeStatement) 0 else F.zig(diff); atBlock = c.block; tip = c.tip;|                difference = if (x.kind == #incomeStatement) 0 else F.zig(diff); atBlock = c.block; tip = AcctFold.zero32();|' src/GrpFold.mo
# the hash without the eliminations
try consolidation-hash-without-eliminations Consolidation \
  sed -i 's|                hash = consolidationHash(groupId, x.companyId, x.kind, x.fromDay, x.throughDay, c.block, c.tip, members, elims, chain);|                hash = consolidationHash(groupId, x.companyId, x.kind, x.fromDay, x.throughDay, c.block, c.tip, members, AcctFold.zero32(), chain);|' src/GrpFold.mo
# a slice of nothing, or past the page
try consolidation-slice-unbounded Consolidation \
  sed -i 's|    if (limit == 0 or limit > Page.MAX_LIMIT) return #err(#sliceBound { limit; max = Page.MAX_LIMIT });|    if (false) return #err(#sliceBound { limit; max = Page.MAX_LIMIT });|' src/GrpFold.mo
# a slice under another group's name
try consolidation-slice-under-the-wrong-group Consolidation \
  sed -i 's|    if (x.groupId != groupId) return #err(#wrongGroup { expected = groupId; found = x.groupId });|    if (false) return #err(#wrongGroup { expected = groupId; found = x.groupId });|' src/GrpFold.mo
# a consolidation cancelled twice (slicing a published one is refused a second time by the walk's
# own switch on the state, so that check is not injected alone)
try consolidation-cancelled-twice Consolidation \
  sed -i 's|    if (not GR.isBuilding(x.state)) return #err(#consolidationNotInState { consolidationId; state = stateName(x.state); wanted = "still being built" });|    if (false) return #err(#consolidationNotInState { consolidationId; state = stateName(x.state); wanted = "still being built" });|' src/GrpFold.mo
# the fingerprint over an empty line store: a consolidated line changed without a block goes unnoticed
try consolidation-fingerprint-misses-the-lines Consolidation \
  sed -i 's|    section<GrpRows.ConsolidationLine>(s, f, "consolidation_line", s.grp.lines, GrpRows.consolidationLine,|    section<GrpRows.ConsolidationLine>(s, f, "consolidation_line", RowStore.newStore<GrpRows.ConsolidationLine>(GrpRows.consolidationLine), GrpRows.consolidationLine,|' src/State.mo

# ── maintenance ───────────────────────────────────────────────────────────────

# a second piece on the same code: a new row instead of the one changed
try maintenance-code-not-unique Maintenance \
  sed -i 's|    switch (equipmentByCode(c.mnt, f.companyId, code)) {|    switch (null : ?(Nat, MNR.Equipment)) {|' src/MntFold.mo
# a location of another company accepted on the register
try maintenance-foreign-location-accepted Maintenance \
  sed -i 's|      if (l.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = l.companyId });|      if (false) return #err(#wrongCompany { expected = f.companyId; found = l.companyId });|' src/MntFold.mo
# an asset that is not there accepted
try maintenance-asset-unchecked Maintenance \
  sed -i 's|      let ?a = RowStore.get<AR.Asset>(c.acct.assets, AR.asset, f.assetId) else return #err(#noSuchAsset { assetId = f.assetId });|      let a = { companyId = f.companyId };|' src/MntFold.mo
# retired with work orders open
try maintenance-retired-with-open-work Maintenance \
  sed -i 's|    if (open > 0) return #err(#equipmentHasOpenWork { equipmentId; open });|    if (false) return #err(#equipmentHasOpenWork { equipmentId; open });|' src/MntFold.mo
# retired, its plans stay standing
try maintenance-retired-plans-stay Maintenance \
  sed -i 's|    for ((pid, p) in plansOf(c.mnt, equipmentId).vals()) {|    for ((pid, p) in ([] : [(Nat, MNR.MaintenancePlan)]).vals()) {|' src/MntFold.mo
# retired equipment takes a plan and a request (the one line stands in both)
try maintenance-retired-takes-work Maintenance \
  sed -i 's|    if (x.state == #retired) return #err(#equipmentRetired { equipmentId = f.equipmentId });|    if (false) return #err(#equipmentRetired { equipmentId = f.equipmentId });|' src/MntFold.mo
# an interval of nothing, or past ten years
try maintenance-interval-unbounded Maintenance \
  sed -i 's|    if (f.intervalDays == 0 or f.intervalDays > MAX_INTERVAL_DAYS) return #err(#intervalBound { days = f.intervalDays; max = MAX_INTERVAL_DAYS });|    if (false) return #err(#intervalBound { days = f.intervalDays; max = MAX_INTERVAL_DAYS });|' src/MntFold.mo
# a run through a day that has not come
try maintenance-run-before-its-day Maintenance \
  sed -i 's|    if (throughDay > c.day) return #err(#horizonNotReached { throughDay; day = c.day });|    if (false) return #err(#horizonNotReached { throughDay; day = c.day });|' src/MntFold.mo
# a second run while one is open
try maintenance-second-run-while-open Maintenance \
  sed -i 's|    switch (openRunOf(c.mnt, companyId)) { case (?(runId, _)) return #err(#maintenanceRunOpen { companyId; runId }); case null {} };|    ignore openRunOf(c.mnt, companyId);|' src/MntFold.mo
# the opener raising its own work orders
try maintenance-opener-slices Maintenance \
  sed -i 's|    if (c.caller == run.openedBy) return #err(#selfServing { opener = run.openedBy });|    if (false) return #err(#selfServing { opener = run.openedBy });|' src/MntFold.mo
# a slice of nothing, or past the page
try maintenance-slice-unbounded Maintenance \
  sed -i 's|    if (limit == 0 or limit > Page.MAX_LIMIT) return #err(#sliceBound { limit; max = Page.MAX_LIMIT });|    if (false) return #err(#sliceBound { limit; max = Page.MAX_LIMIT });|' src/MntFold.mo
# the plan advanced by one interval only: a plan missed three times raises three orders over three runs
try maintenance-plan-advanced-by-one Maintenance \
  sed -i 's|^      if (p\.intervalDays > 0) { while (nextDay <= run\.throughDay) { nextDay += p\.intervalDays } };$|      if (p.intervalDays > 0) { nextDay += p.intervalDays };|' src/MntFold.mo
# the order raised in the slicer's name, not the opener's
try maintenance-order-in-the-slicer-name Maintenance \
  sed -i 's|          description = p.name; openedBy = run.openedBy; closedBy = run.openedBy; lastBlock = c.block });|          description = p.name; openedBy = c.caller; closedBy = c.caller; lastBlock = c.block });|' src/MntFold.mo
# the order due the run's day, not the plan's
try maintenance-order-due-the-run-day Maintenance \
  sed -i 's|          requestedDay = p.nextDay; dueDay = p.nextDay; doneDay = 0; downtimeDays = 0; partsPickingId = 0;|          requestedDay = run.throughDay; dueDay = run.throughDay; doneDay = 0; downtimeDays = 0; partsPickingId = 0;|' src/MntFold.mo
# the run never closes: its last page leaves it running
# (a retired piece's plan raising an order is not injected: retirement cancels the piece's plans, so
# the slice never meets one and removing its own check alone leaves the battery green)
try maintenance-run-never-closes Maintenance \
  sed -i 's|    let lastPage = page.size() < limit;|    let lastPage = false;|' src/MntFold.mo
# a failure never takes the equipment down
try maintenance-failure-leaves-it-in-service Maintenance \
  sed -i 's|    RowStore.put<MNR.Equipment>(c.mnt.equipment, MNR.equipment, f.equipmentId, { x with state = #down; lastBlock = c.block });|    ignore x;|' src/MntFold.mo
# a second request while the equipment is down
try maintenance-second-request-while-down Maintenance \
  sed -i 's|      if (o.kind == #corrective) return #err(#equipmentDown { equipmentId = f.equipmentId; workOrderId = id });|      if (false) return #err(#equipmentDown { equipmentId = f.equipmentId; workOrderId = id });|' src/MntFold.mo
# a failure against a production that is not running
try maintenance-against-a-draft-production Maintenance \
  sed -i 's|      if (p.state != #confirmed and p.state != #inProgress) return #err(#productionNotRunning { productionId = f.productionId; state = productionStateName(p.state) });|      if (false) return #err(#productionNotRunning { productionId = f.productionId; state = productionStateName(p.state) });|' src/MntFold.mo
# the person who raised a work order signing it off
try maintenance-self-signing Maintenance \
  sed -i 's|    if (c.caller == o.openedBy) return #err(#selfSigning { opener = o.openedBy });|    if (false) return #err(#selfSigning { opener = o.openedBy });|' src/MntFold.mo
# signed off before it was raised
try maintenance-signed-off-before-raised Maintenance \
  sed -i 's|    if (f.day < o.requestedDay) return #err(#doneBeforeRequested { requestedDay = o.requestedDay; day = f.day });|    if (false) return #err(#doneBeforeRequested { requestedDay = o.requestedDay; day = f.day });|' src/MntFold.mo
# parts consumed onto a shelf
try maintenance-parts-onto-a-shelf Maintenance \
  sed -i 's|      if (not E.mayGoNegative(to.usage)) return #err(#consumeLocationNotVirtual { locationId = f.consumeLocationId });|      if (false) return #err(#consumeLocationNotVirtual { locationId = f.consumeLocationId });|' src/MntFold.mo
# the parts picking made before it is asked about: a short part leaves rows behind
try maintenance-parts-not-asked-first Maintenance \
  sed -i 's|      switch (c.checkPicking(facts, f.journalId)) { case (?r) return #err(#stock r); case null {} };|      ignore f.journalId;|' src/MntFold.mo
# the parts picking made and never validated: nothing leaves the store, nothing posts
try maintenance-parts-never-validated Maintenance \
  sed -i 's|        switch (c.validatePicking(f.companyId, ids\[0\], f.journalId)) { case (#err r) return #err(#stock r); case (#ok _) {} };|        ignore ids;|' src/MntFold.mo
# a corrective order signed off leaves the equipment down
try maintenance-stays-down-after-repair Maintenance \
  sed -i 's|    let backInService = o.kind == #corrective and eq.state == #down;|    let backInService = false;|' src/MntFold.mo
# the downtime row never written
try maintenance-downtime-row-dropped Maintenance \
  sed -i 's|    if (f.downtimeDays > 0) {|    if (false) {|' src/MntFold.mo
# the equipment's running total not moved
try maintenance-downtime-total-not-moved Maintenance \
  sed -i 's|      eq with state = if (backInService) #inService else eq.state; downtimeDays = eq.downtimeDays + f.downtimeDays; lastBlock = c.block });|      eq with state = if (backInService) #inService else eq.state; lastBlock = c.block });|' src/MntFold.mo
# a corrective order withdrawn leaves the equipment down
try maintenance-withdrawn-stays-down Maintenance \
  sed -i 's|        case (?eq) { if (eq.state == #down) RowStore.put<MNR.Equipment>(c.mnt.equipment, MNR.equipment, o.equipmentId, { eq with state = #inService; lastBlock = c.block }) };|        case (?eq) { ignore eq };|' src/MntFold.mo
# a work order signed off twice, or cancelled after it is done
try maintenance-done-order-reopened Maintenance \
  sed -i 's|    if (o.state != #open) return #err(#workOrderNotInState { workOrderId = f.workOrderId; state = workOrderStateText(o.state); wanted = "open" });|    if (false) return #err(#workOrderNotInState { workOrderId = f.workOrderId; state = workOrderStateText(o.state); wanted = "open" });|' src/MntFold.mo
# the fingerprint over an empty work-order store: an order changed without a block goes unnoticed
try maintenance-fingerprint-misses-the-orders Maintenance \
  sed -i 's|    section<MntRows.WorkOrder>(s, f, "work_order", s.mnt.workOrders, MntRows.workOrder,|    section<MntRows.WorkOrder>(s, f, "work_order", RowStore.newStore<MntRows.WorkOrder>(MntRows.workOrder), MntRows.workOrder,|' src/State.mo

# equipment held by people: handed to oneself, received back by its
# holder, two holders at once, a held piece retired, a piece handed to an inactive employee or to nobody on the
# register, a piece that is down handed out, a return that leaves the row open, the hand-overs outside the fingerprint
try equipment-handed-to-oneself Maintenance \
  sed -i 's|    if (c.caller == f.subject) return #err(#ownHolding { subject = c.caller }); // handed to oneself|    if (false) return #err(#ownHolding { subject = c.caller }); // handed to oneself|' src/MntFold.mo
try equipment-received-by-its-holder Maintenance \
  sed -i 's|    if (c.caller == h.subject) return #err(#ownHolding { subject = c.caller }); // received back by its holder|    if (false) return #err(#ownHolding { subject = c.caller }); // received back by its holder|' src/MntFold.mo
try equipment-two-holders Maintenance \
  sed -i 's|    switch (holdingOf(c.mnt, f.equipmentId)) {|    switch ((null : ?(Nat, MNR.Holding))) {|' src/MntFold.mo
try equipment-retired-while-held Maintenance \
  sed -i 's|    switch (holdingOf(c.mnt, equipmentId)) {|    switch ((null : ?(Nat, MNR.Holding))) {|' src/MntFold.mo
try equipment-to-an-inactive-employee Maintenance \
  sed -i 's|    if (not isActive) return #err(#inactiveEmployee { employeeId });|    if (false) return #err(#inactiveEmployee { employeeId });|' src/MntFold.mo
try equipment-to-nobody-on-the-register Maintenance \
  sed -i 's|c.employeeOf(f.companyId, f.subject)|(?(0, true) : ?(Nat, Bool))|' src/MntFold.mo
try equipment-down-handed-out Maintenance \
  sed -i 's|    if (x.state != #inService) return #err(#equipmentNotInService { equipmentId = f.equipmentId; state = x.state });|    if (x.state == #retired) return #err(#equipmentNotInService { equipmentId = f.equipmentId; state = x.state });|' src/MntFold.mo
try equipment-return-leaves-it-open Maintenance \
  sed -i 's|isReturned = true; receivedBy = c.caller;|isReturned = false; receivedBy = c.caller;|' src/MntFold.mo
try maintenance-fingerprint-misses-the-hand-overs Maintenance \
  sed -i 's|    section<MntRows.Holding>(s, f, "equipment_holding", s.mnt.holdings, MntRows.holding, func(_r) { \[\] });|    section<MntRows.Holding>(s, f, "equipment_holding", RowStore.newStore<MntRows.Holding>(MntRows.holding), MntRows.holding, func(_r) { [] });|' src/State.mo

# ── quality ───────────────────────────────────────────────────────────────────

# a second point on the same code: a new row instead of the one changed
try quality-code-not-unique Quality \
  sed -i 's|    switch (controlPointByCode(c.qc, f.companyId, code)) {|    switch (null : ?(Nat, QR.ControlPoint)) {|' src/QcFold.mo
# a category of another company accepted on a point
try quality-foreign-category-accepted Quality \
  sed -i 's|      if (cat.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });|      if (false) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });|' src/QcFold.mo
# a retired point still standing: the index keeps it
try quality-retired-point-still-holds Quality \
  sed -i 's|        keyOf = func(id : Nat, x : ControlPoint) : ?Blob { if (x.isActive) ?triggerKey(x.companyId, x.trigger, id) else null } },|        keyOf = func(id : Nat, x : ControlPoint) : ?Blob { ?triggerKey(x.companyId, x.trigger, id) } },|' src/QcRows.mo
# a retired point declared again stays retired
try quality-redeclared-stays-retired Quality \
  sed -i 's|          x with name; trigger = f.trigger; categoryId = f.categoryId; isActive = true; declaredBy = c.caller; lastBlock = c.block });|          x with name; trigger = f.trigger; categoryId = f.categoryId; isActive = x.isActive; declaredBy = c.caller; lastBlock = c.block });|' src/QcFold.mo
# a retired point takes checks
try quality-retired-point-takes-checks Quality \
  sed -i 's|    if (not pt.isActive) return #err(#controlPointRetired { controlPointId = f.controlPointId });|    if (false) return #err(#controlPointRetired { controlPointId = f.controlPointId });|' src/QcFold.mo
# THE HOLD NOT ASKED at the validation: a watched receipt or delivery moves unchecked
try quality-hold-not-asked-at-validation Quality \
  sed -i 's|    switch (qualityHoldOf(c, companyId, pickingId, fromLoc.usage, toLoc.usage, Array.map<(Nat, SR.StockMove), Nat>(stored, func((_id, m)) { m.categoryId }))) { case (?r) return #err(r); case null {} };|    ignore fromLoc; ignore toLoc;|' src/StockFold.mo
# the hold not asked before a picking is made: a production fed from a supplier location makes its
# components picking and is then refused at the validation, with the picking left behind
try quality-hold-not-asked-before-making Quality \
  sed -i 's|    switch (qualityHoldOf(c, f.companyId, 0, fromLoc.usage, toLoc.usage, Array.map<SF.MoveFacts, Nat>(f.moves, func(m) { m.categoryId }))) { case (?r) return ?r; case null {} };|    ignore fromLoc; ignore toLoc;|' src/StockFold.mo
# the hold on a production's output not asked: it books output unchecked
try quality-production-hold-not-asked Quality \
  sed -i 's|      case (?h) return #err(#heldForQuality { productionId; controlPointId = h.controlPointId; why = h.why });|      case (?h) { ignore h };|' src/MrpFold.mo
# a point on every category watches none
try quality-any-category-watches-none Quality \
  sed -i 's|    if (p.categoryId == 0) return true;|    if (p.categoryId == 0) return false;|' src/QcFold.mo
# a point on one category watches every category
try quality-one-category-watches-all Quality \
  sed -i 's|    for (cat in categoryIds.vals()) { if (cat == p.categoryId) return true };|    if (categoryIds.size() >= 0) return true;|' src/QcFold.mo
# unchecked goods released
try quality-unchecked-released Quality \
  sed -i 's|          case (#unchecked) return ?{ controlPointId = pid; why = "awaits its check" };|          case (#unchecked) {};|' src/QcFold.mo
# goods under an open non-conformance released
try quality-open-record-released Quality \
  sed -i 's|          case (#open ncId) return ?{ controlPointId = pid; why = "non-conformance " # Nat.toText(ncId) # " stands open" };|          case (#open _) {};|' src/QcFold.mo
# rework releases instead of holding until the re-check
try quality-rework-releases Quality \
  sed -i 's|          case (#rework ncId) return ?{ controlPointId = pid; why = "non-conformance " # Nat.toText(ncId) # " awaits a re-check after rework" };|          case (#rework _) {};|' src/QcFold.mo
# (goods disposed of releasing is not injected: a scrapped or returned subject is cancelled or closed
# by the disposition itself, so the slice never meets a ready one and removing the case alone leaves
# the battery green)
# use as is does not release
try quality-use-as-is-does-not-release Quality \
  sed -i 's|          case (#useAsIs) #released(c.nonConformanceId);|          case (#useAsIs) #open(c.nonConformanceId);|' src/QcFold.mo
# the person who made the picking checking it
try quality-self-checking Quality \
  sed -i 's|      if (c.caller == p.validatedBy) return #err(#selfChecking { maker = p.validatedBy });|      if (false) return #err(#selfChecking { maker = p.validatedBy });|' src/QcFold.mo
# a failure without a finding
try quality-failure-without-finding Quality \
  sed -i "s|    if (not f.passed and Text.size(f.note) == 0) return #err(#nameRequired { what = \"failed check's finding\" });|    if (false) return #err(#nameRequired { what = \"failed check's finding\" });|" src/QcFold.mo
# a check on a day that has not come, and a disposition likewise (the one line stands in both)
try quality-day-not-come-accepted Quality \
  sed -i 's|    if (f.day > c.day) return #err(#horizonNotReached { day = f.day; today = c.day });|    if (false) return #err(#horizonNotReached { day = f.day; today = c.day });|' src/QcFold.mo
# a point applied to goods it does not watch
try quality-point-applied-anywhere Quality \
  sed -i 's|    if (not applies(pt, categoryIds)) return #err(#controlPointDoesNotApply { controlPointId = f.controlPointId; why = "category " # Nat.toText(pt.categoryId) # " is not among these goods" });|    if (false) return #err(#controlPointDoesNotApply { controlPointId = f.controlPointId; why = "" });|' src/QcFold.mo
# a second check over a pass
try quality-second-check-over-pass Quality \
  sed -i 's|      case (#passed checkId) return #err(#alreadyPassed { checkId });|      case (#passed _) {};|' src/QcFold.mo
# a second check over an open non-conformance: the checker overrules the record alone
try quality-second-check-over-open-record Quality \
  sed -i 's|      case (#open ncId) return #err(#nonConformanceOpen { nonConformanceId = ncId });|      case (#open _) {};|' src/QcFold.mo
# a failure raises no record
try quality-failure-raises-no-record Quality \
  sed -i 's|    if (not f.passed) {|    if (false) {|' src/QcFold.mo
# the checker deciding the record they raised
try quality-self-deciding Quality \
  sed -i 's|    if (c.caller == nc.raisedBy) return #err(#selfDeciding { raiser = nc.raisedBy });|    if (false) return #err(#selfDeciding { raiser = nc.raisedBy });|' src/QcFold.mo
# decided before the failure
try quality-decided-before-raised Quality \
  sed -i 's|    if (f.day < nc.raisedDay) return #err(#decidedBeforeRaised { raisedDay = nc.raisedDay; day = f.day });|    if (false) return #err(#decidedBeforeRaised { raisedDay = nc.raisedDay; day = f.day });|' src/QcFold.mo
# a record decided twice
try quality-decided-twice Quality \
  sed -i 's|    if (nc.disposition != #undecided) return #err(#alreadyDecided { nonConformanceId = f.nonConformanceId; disposition = dispositionText(nc.disposition) });|    if (false) return #err(#alreadyDecided { nonConformanceId = f.nonConformanceId; disposition = dispositionText(nc.disposition) });|' src/QcFold.mo
# a return on a delivery or a production, recorded
try quality-return-on-a-delivery Quality \
  sed -i 's|          case (#delivery or #production) return #err(#dispositionNotForSubject { disposition = "return"; trigger = triggerText(nc.trigger) });|          case (#delivery or #production) {};|' src/QcFold.mo
# scrap onto a shelf
try quality-scrap-onto-a-shelf Quality \
  sed -i 's|            if (loss.usage != #inventory) return #err(#scrapLocationNotLoss { locationId = f.scrapLocationId });|            if (false) return #err(#scrapLocationNotLoss { locationId = f.scrapLocationId });|' src/QcFold.mo
# the scrap picking made before it is asked about: a bad journal leaves the delivery cancelled and a picking behind
try quality-scrap-not-asked-first Quality \
  sed -i 's|            switch (c.checkPicking(facts, f.journalId)) { case (?r) return #err(#stock r); case null {} };|            ignore f.journalId;|' src/QcFold.mo
# the scrap picking made and never validated: nothing leaves the store, nothing posts
try quality-scrap-never-validated Quality \
  sed -i 's|        switch (c.validatePicking(f.companyId, ids\[0\], f.journalId)) { case (#err r) return #err(#stock r); case (#ok _) {} };|        ignore f.journalId;|' src/QcFold.mo
# a disposition that cancels nothing: the held receipt and the scrapped delivery stay ready (the one line stands in both)
try quality-disposition-cancels-nothing Quality \
  sed -i 's|        switch (c.cancelPicking(f.companyId, pickingId)) { case (#err r) return #err(#stock r); case (#ok _) {} };|        ignore pickingId;|' src/QcFold.mo
# a scrapped production left running
try quality-production-scrap-not-closed Quality \
  sed -i 's|        switch (c.closeProductionShort(f.companyId, productionId)) { case (#err r) return #err(#mrp r); case (#ok _) {} };|        ignore productionId;|' src/QcFold.mo
# the fingerprint over an empty check store: a verdict flipped without a block goes unnoticed
try quality-fingerprint-misses-the-checks Quality \
  sed -i 's|    section<QcRows.QualityCheck>(s, f, "quality_check", s.qc.checks, QcRows.qualityCheck,|    section<QcRows.QualityCheck>(s, f, "quality_check", RowStore.newStore<QcRows.QualityCheck>(QcRows.qualityCheck), QcRows.qualityCheck,|' src/State.mo

# ── sales and purchase ────────────────────────────────────────────────────────

# the invoice generated CREDIT-ONLY, with no counterpart - the received `createInvoiceFromOrder`'s
# shape, whose own comment postpones double-entry to a later stage that shipped without it
try invoice-has-no-counterpart Orders \
  sed -i 's|      credit = if (isSale) 0 else total;|      credit = if (isSale) 0 else 0;|' src/OrderFold.mo

# a generated line whose account comes from nowhere - the received generator writes `accountId = 0`
try invoice-account-zero Orders \
  sed -i 's|      let account = if (isSale) cat.incomeAccountId else cat.expenseAccountId;|      let account = 0;|' src/OrderFold.mo

# an order invoiced twice, because the key is not checked.
#
# The pattern stops at the condition and does not reach the `#ok([...])` that follows it: `sed`'s
# pattern is a REGULAR EXPRESSION, and `[o.invoiceMoveId]` there is a character class matching one
# character, not the literal text. The first version of this line matched nothing, and `try` caught
# it - which is the third time an injection has silently failed and been refused rather than
# reported as a missed fault.
try invoice-not-idempotent Orders \
  sed -i 's|if (o.invoiceFingerprint == fingerprint) return|if (false) return|' src/OrderFold.mo

# AN ORDER WHOSE STORED TOTAL IS NOT ITS LINES.
#
# Same lesson as the payslip identity: removing the check was unobservable because nothing failed
# it. The fault now makes the stored total wrong, and the check in `issueInvoice` - which compares
# the order's totals with the sum of its lines - is what must refuse.
try order-totals-wrong Orders \
  sed -i 's|      amountUntaxed = untaxed; amountTax = tax; amountTotal = untaxed + tax;|      amountUntaxed = untaxed + 1; amountTax = tax; amountTotal = untaxed + tax;|' src/OrderFold.mo

# ── the class the order fold had, and the guard against it ────────────────────

# an id allocated BEFORE the checks that can refuse, so a refused command consumes one. This is the
# defect the fold check found in `placeOrder`; `Refusals` is the battery that makes it a property.
try refused-command-moves-a-counter Refusals \
  sed -i 's|    writeOrderRows(c, null, f, #draft, c.caller)|    let burn = c.ord.nextOrderId; c.ord.nextOrderId += 1; writeOrderRows(c, ?burn, f, #draft, c.caller)|' src/OrderFold.mo

# a refused command that has already written to the append-only arena
try refused-command-writes-the-arena Refusals \
  sed -i 's|    if (Text.size(f.name) == 0) return #err(#nameRequired { what = "partner" });|    ignore TA.put(c.arena, f.name); if (Text.size(f.name) == 0) return #err(#nameRequired { what = "partner" });|' src/OrderFold.mo

# ── inventory ─────────────────────────────────────────────────────────────────

# THE DEFECT THIS DOMAIN EXISTS TO CLOSE: a validation that applies each move as it goes and returns
# from inside the loop on a failure, leaving a prefix applied - the received `validatePicking`.
try picking-applies-part-way Inventory \
  sed -i 's|^        if (have - held < m\.quantity) {$|        if (false) {|' src/StockFold.mo

# an internal location that may go below zero. The battery exercises it on an AVCO category, where
# the FIFO layer walk does not already refuse for insufficiency and this guard is the only one.
try internal-location-goes-negative Inventory \
  sed -i 's|      if (not sourceMayGoNegative) {|      if (false) {|' src/StockFold.mo

# FIFO taking from the newest layer rather than the oldest
try fifo-takes-newest Inventory \
  sed -i 's|    for ((layerId, l) in layers.vals()) {|    for ((layerId, l) in Array.reverse(layers).vals()) {|' src/StockFold.mo

# a category that may move without a costing rule - stock moving and valuing nothing, which is the
# received module in its entirety
try stock-moves-without-costing Inventory \
  sed -i 's|        case null { return ?(#noCosting { categoryId = m.categoryId }) };|        case null { };|' src/StockFold.mo

# a validation that moves stock and posts NOTHING
try stock-posts-nothing Inventory \
  sed -i 's|    if (totalValue > 0 and (sourceIsInternal or destIsInternal)) {|    if (false) {|' src/StockFold.mo

# A COSTING METHOD CHANGED WHILE THE CATEGORY HOLDS STOCK, which leaves the value behind.
#
# This replaces a fault on `#noCostForOutgoing`, which no battery could observe: the quantity guard
# refuses an empty location first, so that refusal is unreachable. A fault nothing can observe proves
# nothing about the battery, and pretending otherwise is the thing this whole control exists to stop.
# the components picking made before the whole of it was asked: a ledger refusal at validation
# leaves the picking behind
try production-picking-made-before-asked Manufacturing \
  sed -i 's|    switch (c.checkPicking(consume, journalId)) {|    switch (null : ?SFold.Refusal) {|' src/MrpFold.mo

# two moves of one category planned against the untouched store: the second sees the whole holding
try split-moves-planned-apart Inventory \
  sed -i 's|        let have = onHand(c.stock, companyId, p.fromLocationId, m.categoryId) - already;|        let have = onHand(c.stock, companyId, p.fromLocationId, m.categoryId);|' src/StockFold.mo

# two moves of one category valued on the same layers twice
try split-moves-valued-twice Inventory \
  sed -i 's|      let left : Nat = if (l.quantityRemaining > before) l.quantityRemaining - before else 0;|      let left : Nat = l.quantityRemaining;|' src/StockFold.mo

try costing-method-changed-with-stock Inventory \
  sed -i 's|        if (existing.method != f.method and categoryHasStock(c, f.companyId, f.categoryId)) {|        if (false) {|' src/StockFold.mo

# ── manufacturing ─────────────────────────────────────────────────────────────

# THE DEFECT THIS DOMAIN EXISTS TO CLOSE: components consumed from a location back to ITSELF, so the
# movements net to zero and manufacturing changes nothing - the received `produceProduct`.
try production-moves-nothing Manufacturing \
  sed -i 's|      companyId; fromLocationId = p.sourceLocationId; toLocationId = p.wipLocationId;|      companyId; fromLocationId = p.sourceLocationId; toLocationId = p.sourceLocationId;|' src/MrpFold.mo

# a bill of materials that may contain itself, at any depth
try bom-cycle-allowed Manufacturing \
  sed -i 's|        case (?_depth) { return ?#bomCycle { parentId = f.categoryId; childId = l.categoryId } };|        case (?_depth) { };|' src/MrpFold.mo

# component quantities scaled by truncating integer division, which drops the remainder of every
# component of every order
try component-scaling-truncates Manufacturing \
  sed -i 's|    let scaled = Dec.quantize(exact, 0, #halfEven);|    let scaled = Dec.quantize(exact, 0, #down);|' src/MrpFold.mo

# an order that always reports its full planned quantity, whatever came off the line
try production-always-full Manufacturing \
  sed -i 's|    let produced = p.producedQty + quantity;|    let produced = p.plannedQty;|' src/MrpFold.mo

# an explosion with no depth bound
try explosion-unbounded Manufacturing \
  sed -i 's|      if (depth > bound) {|      if (false) {|' src/MrpFold.mo

# a production that creates its picking BEFORE checking the components are there - the class the
# `Refusals` battery exists for, found for the second time here
try produce-writes-then-refuses Refusals \
  sed -i 's|    switch (c.checkPicking(consume, journalId)) {|    switch (null : ?SFold.Refusal) {|' src/MrpFold.mo

# ── projects, tasks and time ──────────────────────────────────────────────────

# a task whose assignee and project are not resolved - so a task can be assigned to somebody who is
# not a member, which is what an HR task with no company amounts to
try task-references-unchecked Projects \
  sed -i 's|    switch (checkTaskRefs(c, f)) { case (?r) return #err(r); case null {} };|    ignore checkTaskRefs(c, f);|' src/ProjFold.mo

# a project whose manager, customer or cost account resolves to nothing - the received row's two
# `?Nat`s, whose comments say their modules are postponed
try project-references-unresolved Projects \
  sed -i 's|    switch (checkProjectRefs(c, f)) { case (?r) return #err(r); case null {} };|    ignore checkProjectRefs(c, f);|' src/ProjFold.mo

# logging time that posts immediately, rather than on approval
try time-posts-on-logging Projects \
  sed -i 's|    if (sheet.state != #submitted) return #err(#timesheetNotSubmitted { timesheetId; state = timeStateName(sheet.state) });|    if (false) return #err(#timesheetNotSubmitted { timesheetId; state = timeStateName(sheet.state) });|' src/ProjFold.mo

# the submitter approving their own timesheet
try self-approved-timesheet Projects \
  sed -i 's|    if (sheet.subject == c.caller) return #err(#selfApproval { subject = sheet.subject });|    if (false) return #err(#selfApproval { subject = sheet.subject });|' src/ProjFold.mo

# time costed by truncating rather than exactly - ninety minutes at 187.50 an hour is 281.25, and
# fifty minutes is 156.25; integer division makes them 187.50 and nothing
try time-cost-truncates Projects \
  sed -i 's|      let hours = Dec.div(Dec.fromNat(e.minutes), Dec.fromNat(60), Dec.PREC);|      let hours = Dec.fromNat(e.minutes / 60);|' src/ProjFold.mo

# an approved entry that may still be voided - the received `deleteTimeEntry` removes any of them
try approved-entry-voidable Projects \
  sed -i 's|    if (e.state == #approved) return #err(#entryNotDraft { entryId; state = "approved" });|    if (false) return #err(#entryNotDraft { entryId; state = "approved" });|' src/ProjFold.mo


# ── the CRM ───────────────────────────────────────────────────────────────────

# THE MARK IS NOT WRITTEN. The received tick reminds and records nothing, so the same hundred are
# reminded every hour for ever and the sweep never ends.
try reminder-mark-not-written Crm \
  sed -i 's|        a with remindedDay = c.day; lastBlock = c.block|        a with remindedDay = a.remindedDay; lastBlock = c.block|' src/CrmFold.mo

# THE INDEX IS NOT PARTIAL ON THE MARK, so a reminded activity stays in the range the sweep walks
# and is reminded again - the same behaviour reached by the other door.
try reminder-index-keeps-the-reminded Crm \
  sed -i 's|          if (x.isDone or x.isArchived or x.remindedDay != 0) null|          if (x.isDone or x.isArchived) null|' src/CrmRows.mo

# THE RUN RECORDS NOTHING IT DID, which is the state an upgrade would have to preserve and the
# received timer keeps nowhere at all.
try sweep-progress-not-recorded Crm \
  sed -i 's|      run with cursor = last; scanned = run.scanned + due.size(); acted = run.acted + due.size();|      run with cursor = 0; scanned = run.scanned + due.size(); acted = 0;|' src/CrmFold.mo

# A DEADLINE MOVED KEEPS THE OLD REMINDER, so an activity moved to a later date is never reminded
# about the date it now has.
try moved-deadline-stays-reminded Crm \
  sed -i 's|    let remindedDay = if (f.deadlineDay != existing.deadlineDay) 0 else existing.remindedDay;|    let remindedDay = existing.remindedDay;|' src/CrmFold.mo

# THE RECEIVED MAILING DEFECT EXACTLY: the list ends at the first window that produced nobody, and
# the mailing is finished - having reached none of the leads after it.
# (anchored to the line's end: the campaign's remainder mailing shares the wording on a line that
# continues, and an injection that hit both did not compile, which is a miss)
try mailing-ends-at-an-empty-window Crm \
  sed -i 's|      state = if (lastPage) #ready else #planning;$|      state = if (List.size(chosen) == 0) #ready else #planning;|' src/CrmFold.mo

# A FAILURE IS TERMINAL AT THE FIRST ATTEMPT - the effect of the received handler advancing its
# cursor past the batch it did not send.
try failed-recipient-never-retried Crm \
  sed -i 's|          r with state = if (terminal) #failed else #pending; attempts; reason; lastBlock = c.block|          r with state = #failed; attempts; reason; lastBlock = c.block|' src/CrmFold.mo

# THE RETRY BOUND IS NOT A BOUND, so a recipient that always fails is retried for ever.
try retry-bound-ignored Crm \
  sed -i 's|        let terminal = attempts >= m.attemptBound;|        let terminal = false;|' src/CrmFold.mo

# ONE ADDRESS, TWO COPIES: the same person receives the same mailing twice.
try recipient-not-deduplicated Crm \
  sed -i 's|          if (not already and not seenInSlice) {|          if (true) {|' src/CrmFold.mo

# AN ADDRESS THAT ASKED NOT TO BE WRITTEN TO IS WRITTEN TO.
try suppression-ignored Crm \
  sed -i 's|            let suppressedHere = switch (activeSuppression(c, companyId, key)) { case (?_) true; case null false };|            let suppressedHere = false;|' src/CrmFold.mo

# THE CONTENT IS NOT WHAT WAS APPROVED: the body of a launched mailing can still be edited, which
# the received `updateMailing` allows while the mailing is `#sending`.
try launched-content-still-editable Crm \
  sed -i 's|    if (m.state != #draft) return #err(#contentLocked { mailingId });|    if (false) return #err(#contentLocked { mailingId });|' src/CrmFold.mo

# A SEND CLAIMED AGAINST A LIST THAT IS NOT THE LIST.
try send-not-bound-to-the-plan Crm \
  sed -i 's|    if (m.rollingHash != planHash) return #err(#planHashMismatch { runId = mailingId });|    if (false) return #err(#planHashMismatch { runId = mailingId });|' src/CrmFold.mo

# THE PLAN HASH DEPENDS ON HOW THE PLAN WAS BUILT, so the same recipient set hashes differently at
# different slice sizes and "this is the list that was approved" stops meaning anything.
try plan-hash-depends-on-the-slicing Crm \
  sed -i 's|      rolling := chain(rolling, x.key);|      rolling := chain(rolling, CR.addressKey(Nat.toText(List.size(chosen))));|' src/CrmFold.mo

# THE RULES MOVE UNDER THE RUN and the run does not notice - half the company scored by one rule
# set and half by another, which is what `scoreAllLeads` cannot even ask about.
try scoring-rules-not-rechecked Crm \
  sed -i 's|    if (now != run.planHash) return #err(#rulesMovedUnderRun { runId });|    if (false) return #err(#rulesMovedUnderRun { runId });|' src/CrmFold.mo

# A COMPLETED PLAN RUN AGAIN.
try completed-plan-rerunnable Crm \
  sed -i 's|      case (?(runId, _)) { return #err(#planAlreadyRun { companyId; runId }) };|      case (?(_runId, _)) { };|' src/CrmFold.mo

# THE RECEIVED SCORING DEFECT EXACTLY: "has an open activity" is answered from the first ten
# activities of the lead, so a lead with ten closed ones and an open eleventh has none.
try open-activity-read-from-the-first-ten Crm \
  sed -i 's|    let (lo, hi) = CR.leadOwnerRange(companyId, leadId);|    let (lo, hi) = (CR.leadOwnerKey(companyId, leadId, 0), CR.leadOwnerKey(companyId, leadId, 10));|' src/CrmFold.mo

# A TAG THAT IS NO LONGER CARRIED STILL ANSWERS "every lead tagged X".
try retired-tag-still-in-the-index Crm \
  sed -i 's|          if (x.isActive) ?tagNameKey(x.companyId, x.tag, id) else null|          ?tagNameKey(x.companyId, x.tag, id)|' src/CrmRows.mo

# THE WEIGHTED FIGURE IS SUPPLIED RATHER THAN DERIVED, so a lead can record a forecast its own
# expectation and probability do not produce - which the received row permits.
try weighted-revenue-not-derived Crm \
  sed -i 's|      plannedRevenue = planned(f.expectedRevenue, f.probability);|      plannedRevenue = f.expectedRevenue;|' src/CrmFold.mo

# A STAGE MARKED WON DOES NOT WIN THE LEAD - the received auto-transition, dropped.
try won-stage-does-not-win Crm \
  sed -i 's|    let won = s.isWon and l.state != #won;|    let won = false;|' src/CrmFold.mo

# A LEAD SITS IN ANOTHER COMPANY'S PIPELINE STAGE. `CrmStageStore.Stage` has no company field at
# all, so in the received tree this is not a defect but the design.
try stage-not-company-scoped Crm \
  sed -i 's|      if (s.companyId != f.companyId) return ?(#wrongCompany { expected = f.companyId; found = s.companyId });|      if (false) return ?(#wrongCompany { expected = f.companyId; found = s.companyId });|' src/CrmFold.mo

# AN ACTIVITY ASSIGNED TO SOMEBODY WHO IS NOT A MEMBER - the received `userId : ?Nat` names nothing
# and is checked against nothing.
try activity-assignee-unchecked Refusals \
  sed -i 's|      case null { return ?(#notAMember { companyId = f.companyId; subject = f.assignee }) };|      case null { };|' src/CrmFold.mo

# AN ACTIVITY WITH NO DEADLINE, which is never due and so never reminded and never overdue.
try activity-without-a-deadline Refusals \
  sed -i 's|    if (f.deadlineDay == 0) return ?(#deadlineRequired);|    if (false) return ?(#deadlineRequired);|' src/CrmFold.mo


# ── evidence and signatures ───────────────────────────────────────────────────

# ERASURE THAT DOES NOT DESTROY THE KEY. The record says erased and the document still opens - 
# which is what `deleteDocument` amounts to: a map entry removed and the bytes wherever they were.
try erasure-keeps-the-key Evidence \
  sed -i 's|    switch (Evidence.erase(c.evs.ev, d.evidenceId, c.day, reason)) {|    switch (#ok({ dedupEpoch = 0 }) : { #ok : { dedupEpoch : Nat }; #err : Evidence.Error }) {|' src/EvFold.mo

# ERASURE FOR NO STATED REASON. A destruction nobody has to account for.
try erasure-without-a-reason Evidence \
  sed -i 's|    if (Text.size(reason) == 0) return #err(#nameRequired { what = "reason for erasure" });|    if (false) return #err(#nameRequired { what = "reason for erasure" });|' src/EvFold.mo

# AN IDENTITY PAPER WITH NO EXPIRY, which is what the received row allows - and a paper that never
# expires is one the sweep can never find.
try identity-paper-without-an-expiry Evidence \
  sed -i 's|    if (expiryRequired(f.docType) and f.expiryDay == 0) return #err(#expiryRequired { docType = docTypeName(f.docType) });|    if (false) return #err(#expiryRequired { docType = docTypeName(f.docType) });|' src/EvFold.mo

# THE MARK IS NOT WRITTEN, so the sweep reads the same head for ever - the received reminder shape.
try expiry-mark-not-written Evidence \
  sed -i 's|      RowStore.put<EV.Document>(c.evs.documents, EV.document, id, { d with remindedDay = c.day; lastBlock = c.block });|      RowStore.put<EV.Document>(c.evs.documents, EV.document, id, { d with remindedDay = d.remindedDay; lastBlock = c.block });|' src/EvFold.mo

# THE INDEX IS NOT PARTIAL ON THE MARK, so a reminded document stays in the range and is reminded
# again.
try expiry-index-keeps-the-reminded Evidence \
  sed -i 's|          if (x.state != #active or x.expiryDay == 0 or x.remindedDay != 0) null|          if (x.state != #active or x.expiryDay == 0) null|' src/EvRows.mo

# THE RUN RECORDS NOTHING IT DID - the state an upgrade would have to preserve.
try document-sweep-progress-not-recorded Evidence \
  sed -i 's|      run with cursor = last; scanned = run.scanned + due.size(); acted = run.acted + due.size();|      run with cursor = 0; scanned = run.scanned + due.size(); acted = 0;|' src/EvFold.mo

# A MOVED EXPIRY KEEPS ITS OLD REMINDER, so a document renewed to a later date is never reminded
# about the date it now has.
try moved-expiry-stays-reminded Evidence \
  sed -i 's|    let remindedDay = if (expiryDay != d.expiryDay or reminderDays != d.reminderDays) 0 else d.remindedDay;|    let remindedDay = d.remindedDay;|' src/EvFold.mo

# A SIGNATURE OVER THE WRONG DIGEST. The verifier is handed a hash that is not the content's, so
# what the signature attests to is not what was signed - the received request's mutable
# `content : Text` by another door.
try signature-over-the-wrong-digest Evidence \
  sed -i 's|      f.clientDataB64, f.authDataB64, f.signatureB64, Canonical.hex(r.contentHash))) {|      f.clientDataB64, f.authDataB64, f.signatureB64, "deadbeef")) {|' src/EvFold.mo

# A SLICE NOT BOUND TO ITS RUN'"'"'S PLAN.
try document-sweep-plan-not-checked Evidence \
  sed -i 's|    if (run.planHash != planHash) return #err(#planHashMismatch { runId });|    if (false) return #err(#planHashMismatch { runId });|' src/EvFold.mo

# ONE PERSON, TWO ANSWERS on the same request: whose turn it is no longer moves off a signer who
# has signed, so they could sign again. (The guard this injection once removed, `alreadyAnswered`,
# went with the ordered flow; the turn is the rule now, and this is its fault.)
try answered-twice-allowed Evidence \
  sed -i 's|    for ((id, x) in signersOf(st, companyId, requestId).vals()) { if (x.state == #pending) return ?(id, x) };|    for ((id, x) in signersOf(st, companyId, requestId).vals()) { return ?(id, x) };|' src/EvFold.mo

# THE ARENA IS STATE, AND A REFUSED COMMAND MOVES NONE OF IT. This restores the order the first
# version of `registerDocument` had - the title and the description written into the append-only
# arena before the evidence store is asked, so a refused registration leaves two strings a replay
# never writes. The fold fingerprint found it once; this keeps it found.
try arena-written-before-the-refusal Refusals \
  sed -i 's|    let stored = switch (Evidence.add(|    let #ok(early1) = put(c.arena, "title", f.title) else return #err(#nameRequired { what = "document" });\n    let #ok(early2) = put(c.arena, "description", f.description) else return #err(#nameRequired { what = "document" });\n    ignore early1; ignore early2;\n    let stored = switch (Evidence.add(|' src/EvFold.mo

# AN EMPLOYEE DOCUMENT FOR SOMEBODY WHO IS NOT A MEMBER.
try employee-document-for-a-stranger Refusals \
  sed -i 's|        case null { return #err(#notAMember { companyId = f.companyId; subject = f.subject }) };|        case null { };|' src/EvFold.mo


# ── currencies, taxes, banking and the tax-authority filing ───────────────────

# THE RECEIVED FORMATTER EXACTLY: the sign thrown away, as `etaAmountToText` throws it away for
# every amount between −0.99 and −0.01, so a credit note's small lines are filed as charges.
try filing-amount-loses-its-sign Finance \
  sed -i 's|    let sign = if (value < 0) "-" else "";|    let sign = "";|' src/Outcall.mo

# THE SCALE HARD-CODED AT TWO, which is what `etaAmountToText` does with its comment "minor units
# → whole EGP" - and there are three-decimal currencies in this very battery.
try filing-scale-hard-coded Finance \
  sed -i 's|    if (exponent == 0) return sign # Nat.toText(magnitude);|    if (false) return sign # Nat.toText(magnitude);|' src/Outcall.mo

# A STATEMENT CONFIRMED WITHOUT ITS BALANCES AGREEING - the received row's `balanceEndReal`, typed
# in by the caller and compared to nothing.
try statement-balance-not-checked Finance \
  sed -i 's|    if (st.balanceEndComputed != st.balanceEndDeclared) {|    if (false) {|' src/FinFold.mo

# A LINE MATCHED TO AN ENTRY FOR A DIFFERENT AMOUNT. `reconcileStatementLine(lineId, moveId)`
# checks only that the move is posted.
try match-ignores-the-line-amount Finance \
  sed -i 's|    if (amount > lineLeft) return #err(#overMatchesLine { lineId; remaining = lineLeft; asked = amount });|    if (false) return #err(#overMatchesLine { lineId; remaining = lineLeft; asked = amount });|' src/FinFold.mo

# ONE ENTRY MATCHED BY EVERY LINE OF THE STATEMENT.
try match-ignores-the-entry-total Finance \
  sed -i 's|    if (amount > moveLeft) return #err(#overMatchesMove { moveId; remaining = moveLeft; asked = amount });|    if (false) return #err(#overMatchesMove { moveId; remaining = moveLeft; asked = amount });|' src/FinFold.mo

# NOT INJECTED: the filing's three-way total cross-check.
#
# `prepareEtaFiling` refuses when the lines' sum, the order's total and the move's total disagree.
# Removing that check changes nothing observable - the order fold computes its total from the same
# lines and the invoice generator posts that same figure - so an injection here would go green and
# be counted as a miss, which is exactly what this control found when it was injected. A fault that
# nothing can observe proves nothing; the check stays, with a comment in the fold saying it carries
# no control fault and why. The same reasoning as `#noCostForOutgoing` in the inventory domain.

# A RESULT RECORDED AGAINST A PAYLOAD THAT IS NOT THE FILING'S, so what the authority answered and
# what was sent need not be the same document.
try filing-result-not-bound-to-the-payload Eta \
  sed -i 's|    if (x.payloadHash != f.payloadHash) return #err(#payloadChanged { filingId = f.filingId });|    if (false) return #err(#payloadChanged { filingId = f.filingId });|' src/FinFold.mo

# ONE ORDER FILED TWICE.
try order-filed-twice Finance \
  sed -i 's|      case (?(filingId, _)) { return #err(#alreadyFiled { orderId = f.orderId; filingId }) };|      case (?(_filingId, _)) { };|' src/FinFold.mo

# TWO RATES EFFECTIVE FROM ONE DAY, so "the rate in force" is a question of which row the index
# happens to return.
try two-rates-on-one-day Finance \
  sed -i 's|      case (?_) { return #err(#rateAlreadyOnThatDay { code = f.code; day = f.effectiveDay }) };|      case (?_) { };|' src/FinFold.mo

# A TAX WITH NOWHERE TO POST - the received row has no account at all. The rule is the ACCOUNT
# READ and the company check on what it finds; a separate `accountId == 0` guard was here too, this
# control found that removing it changed nothing, and it is gone.
try tax-account-not-this-company Finance \
  sed -i '0,/    if (a.companyId != f.companyId) return #err(#wrongCompany { expected = f.companyId; found = a.companyId });/s||    if (false) return #err(#wrongCompany { expected = f.companyId; found = a.companyId });|' src/FinFold.mo

# A LINE MATCHED TO A JOURNAL ENTRY IN ANOTHER CURRENCY.
try match-ignores-the-currency Finance \
  sed -i 's|    if (m.currency != st.currency) {|    if (false) {|' src/FinFold.mo

# A LINE MATCHED TO AN ENTRY MONTHS AWAY FROM IT.
try match-ignores-the-date Finance \
  sed -i 's|    if (absDiff(l.transactionDay, m.businessDay) > MATCH_WINDOW_DAYS) {|    if (false) {|' src/FinFold.mo


# ── the person record and conduct ─────────────────────────────────────────────

# AN ANONYMOUS GRIEVANCE NAMES ITS COMPLAINANT - `main.mo:22669` writes `complainantId = caller`
# unconditionally and stores `isAnonymous` beside it.
try anonymous-grievance-names-its-complainant People \
  sed -i 's|      complainant = if (f.isAnonymous) anonymous() else c.caller;|      complainant = c.caller;|' src/PeopleFold.mo

# AN ANONYMOUS INCIDENT NAMES ITS REPORTER.
try anonymous-incident-names-its-reporter People \
  sed -i 's|      reporter = if (f.isAnonymous) anonymous() else c.caller;|      reporter = c.caller;|' src/PeopleFold.mo

# A COMPLAINT WITHDRAWN BY SOMEBODY WHO IS NOT THE COMPLAINANT, which for an anonymous one is the
# only thing the blinded key is for.
try grievance-withdrawn-without-the-key People \
  sed -i 's|    if (x.blindedComplainant != blinded) return #err(#blindedKeyRequired);|    if (false) return #err(#blindedKeyRequired);|' src/PeopleFold.mo

# A BLINDED KEY THAT IS NOT ONE.
try grievance-key-not-checked People \
  sed -i 's|    if (f.blindedComplainant.size() != W.HASH) return #err(#blindedKeyRequired);|    if (false) return #err(#blindedKeyRequired);|' src/PeopleFold.mo

# SOMEBODY FINALISING THEIR OWN PROBATION.
try self-finalised-probation People \
  sed -i 's|    if (Principal.equal(p.subject, c.caller)) return #err(#selfDecision { subject = p.subject });|    if (false) return #err(#selfDecision { subject = p.subject });|' src/PeopleFold.mo

# A WARNING THAT NEVER STOPS COUNTING - `expiryDate : ?Text`, a string nothing can compare. The rule
# is the RANGE CHECK: an expiry of zero is before any issue day. A separate `expiryDay == 0` guard
# was here, this control found that removing it changed nothing, and it is gone.
try warning-expiry-before-its-issue People \
  sed -i 's|    if (f.expiryDay < f.issueDay) return #err(#rangeBackwards { fromDay = f.issueDay; toDay = f.expiryDay });|    if (false) return #err(#rangeBackwards { fromDay = f.issueDay; toDay = f.expiryDay });|' src/PeopleFold.mo

# A WARNING WHOSE TEXT IS A FIELD RATHER THAN EVIDENCE, editable after the employee has seen it.
try warning-without-a-document People \
  sed -i 's|    if (f.incidentDocumentId == F.NO_ID) return #err(#nameRequired { what = "document setting out the incident" });|    if (false) return #err(#nameRequired { what = "document setting out the incident" });|' src/PeopleFold.mo

# THE MARK IS NOT WRITTEN, so the expiry sweep reads the same head for ever.
try warning-expiry-not-marked People \
  sed -i 's|        x with state = #expired; lastBlock = c.block|        x with lastBlock = c.block|' src/PeopleFold.mo

# THE EXPIRY INDEX IS NOT PARTIAL ON THE STATE, so an expired warning stays in the range.
try warning-expiry-index-keeps-the-expired People \
  sed -i 's|if ((x.state == #active or x.state == #acknowledged) and x.expiryDay != 0) ?CR.dueKey(x.companyId, x.expiryDay, id) else null|if (x.expiryDay != 0) ?CR.dueKey(x.companyId, x.expiryDay, id) else null|' src/PeopleRows.mo

# A DEPENDANT CLAIMED ON A POLICY WITH NOTHING PROVING THE RELATION.
try dependant-without-a-document People \
  sed -i 's|    if (f.isDependent and f.documentId == F.NO_ID) return #err(#nameRequired { what = "document proving the relation" });|    if (false) return #err(#nameRequired { what = "document proving the relation" });|' src/PeopleFold.mo

# A FIELD'"'"'S KIND CHANGED UNDER THE VALUES ALREADY STORED AGAINST IT.
try field-kind-changed-underneath People \
  sed -i 's|    if (f.kind != x.kind) return #err(#valueDoesNotFitField { fieldId; kind = "the kind it was declared with" });|    if (false) return #err(#valueDoesNotFitField { fieldId; kind = "the kind it was declared with" });|' src/PeopleFold.mo

# AN EXPENSE PAST THE BUDGET THAT WAS APPROVED.
try relocation-expense-past-the-budget People \
  sed -i 's|    if (x.budget != 0 and spent > x.budget) {|    if (false) {|' src/PeopleFold.mo

# AN INJURY CLOSED WITH NO RECORD OF WHAT WAS LOOKED INTO.
try injury-closed-without-an-investigation People \
  sed -i 's|    if (state == #closed and x.injuryOccurred) {|    if (false) {|' src/PeopleFold.mo

# AN IMPORT THAT TAKES MORE ROWS THAN IT WAS OPENED FOR.
try import-count-not-bounded People \
  sed -i 's|    if (run.acted + rows.size() > run.cursor) {|    if (false) {|' src/PeopleFold.mo

# A PLAN THAT DOES NOT RECORD THE ENGAGEMENT IT BELONGS TO - which is what
# `"plan:" # principal # ":" # companyId` amounts to: one per person per company, for ever, and a
# rehire overwrites the first. A separate `contractId == 0` guard was here and removing it changed
# nothing, because the read below already refuses an id that names nothing; it is gone, and what is
# injected is the link itself.
try plan-does-not-record-its-engagement People \
  sed -i 's|      contractId = f.contractId; startDay = f.startDay; state = #pending;|      contractId = 0; startDay = f.startDay; state = #pending;|' src/PeopleFold.mo

# SOMEBODY NAMED AS THEIR OWN SUCCESSOR.
try own-successor People \
  sed -i 's|    if (Principal.equal(p.incumbent, f.candidate)) return #err(#selfDecision { subject = f.candidate });|    if (false) return #err(#selfDecision { subject = f.candidate });|' src/PeopleFold.mo

# SOMEBODY REVIEWING THEIR OWN HEADCOUNT SUBMISSION.
try self-reviewed-headcount People \
  sed -i 's|    if (state == #reviewed and Principal.equal(p.submittedBy, c.caller)) {|    if (false) {|' src/PeopleFold.mo

# TWO PEOPLE WITH ONE EMPLOYEE NUMBER.
try employee-number-not-unique People \
  sed -i 's|        case (?(_, other)) { if (not Principal.equal(other.subject, subject)) return #err(#codeTaken { code = employeeNumber }) };|        case (?(_, _other)) { };|' src/PeopleFold.mo

# ── shifts, breaks, overtime, holidays, working from home and the devices ─────

# THE DEVICE'"'"'S SIGNATURE NOT CHECKED - which is `ingestDevicePunches` comparing a shared secret
# with `==` over a scan, and the whole of the authority on a method that writes the attendance
# record payroll is computed from.
try device-signature-unchecked Attendance \
  sed -i 's|    if (not P256.verify(qx, qy, P256.natOf(Blob.toArray(digest)), r, s)) {|    if (false) {|' src/AttFold.mo

# THE UNIQUE (device, counter) INDEX IS NOT INJECTED HERE, and this says why rather than leaving a
# gap for a reader to wonder about. A device counts upwards and the fold refuses a counter that is
# not ahead of the one on the device row, so every batch that index would refuse the rule below
# refuses first: an injection removing the index leaves the battery GREEN, which is a missed fault
# by this control's own standard and not a battery that has stopped working. The index is kept for
# the read it serves - which counters a device has spent, answered from the receipts rather than
# from one mutable field - and `src/AttRows.mo` records that it cannot be the sole reason for a
# refusal. This is the second kind of unreachable check the index amendment names: kept, and
# saying so.

# THE COUNTER NOT REQUIRED TO ADVANCE.
try device-counter-not-monotonic Attendance \
  sed -i 's|    if (f.counter <= d.lastCounter) return #err(#counterNotAhead { asked = f.counter; last = d.lastCounter });||' src/AttFold.mo

# A REVOKED DEVICE STILL BELIEVED.
try revoked-device-believed Attendance \
  sed -i 's|    if (d.isRevoked) return #err(#deviceRevoked { deviceId = f.deviceId });||' src/AttFold.mo

# ONE PUBLIC KEY REGISTERED TWICE, so two devices answer to one identity.
try device-key-not-unique Attendance \
  sed -i 's|      case (?_) { return #err(#keyAlreadyRegistered) };|      case (?_) { };|' src/AttFold.mo

# A KEY THAT IS NOT A KEY ACCEPTED AT REGISTRATION, so the fault surfaces later as a bad signature.
try device-key-unparsed Attendance \
  sed -i 's|    let ?_ = P256.parseSpki(f.publicKey) else return #err(#publicKeyMalformed);||' src/AttFold.mo

# A DEVICE PLACING A PUNCH IN THE FUTURE.
try device-punch-in-future Attendance \
  sed -i 's|      if (p.businessDay > c.day) return #err(#dayInFuture { day = p.businessDay; today = c.day });||' src/AttFold.mo

# AN UNBOUNDED BATCH - the received ingest takes a thousand punches and resolves each one by walking
# every membership in the contract.
try device-batch-unbounded Attendance \
  sed -i 's|    if (f.punches.size() > MAX_BATCH_PUNCHES) return #err(#batchTooLarge { asked = f.punches.size(); max = MAX_BATCH_PUNCHES });||' src/AttFold.mo

# AN EMPLOYEE SUPPLYING THEIR OWN OVERTIME RATE - `requestOvertime` takes `hourlyRate` and
# `multiplier` from the claimant. Here the rate is simply not read from the compensation row.
try overtime-rate-not-read Attendance \
  sed -i 's|      reviewedDay = c.day; hourlyRate = comp.hourlyRate; multiplier; currency = comp.currency;|      reviewedDay = c.day; hourlyRate = 9_999; multiplier; currency = comp.currency;|' src/AttFold.mo

# THE STATUTORY PREMIUM IGNORED, and a compiled-in figure used instead - the exact shape
# `PayEngine` had until this extension.
try overtime-premium-compiled-in Attendance \
  sed -i 's|    let multiplier = PR.overtimeMultiplierFor(profile, o.category);|    let multiplier = 1_500_000;|' src/AttFold.mo

# A PROFILE WITH NO PREMIUM APPLYING A ZERO - a person working a Saturday for nothing.
try overtime-premium-zero-allowed Attendance \
  sed -i 's|    if (multiplier == 0) return #err(#noOvertimePremium { profileId = comp.profileId; category = categoryName(o.category) });||' src/AttFold.mo

# A PAYROLL SLICE NAMING OVERTIME NOBODY APPROVED.
try payroll-overtime-unapproved Attendance \
  sed -i 's|        return #err(#overtimeDisagrees { subject; claimed = f.overtimeMinutes\[i\]; approved = approvedMinutes });||' src/PayFold.mo

# SOMEBODY APPROVING THEIR OWN OVERTIME.
try self-approved-overtime Attendance \
  sed -i 's|    if (o.subject == c.caller) return #err(#selfDecision { subject = c.caller });||' src/AttFold.mo

# TIME IN LIEU GRANTED BY THE PERSON SPENDING IT - `useCompTime` checks membership and decrements.
try self-granted-time-in-lieu Attendance \
  sed -i 's|    if (u.subject == c.caller) return #err(#selfDecision { subject = c.caller });||' src/AttFold.mo

# A BALANCE SPENT BELOW ZERO, because the balance is checked when the request is raised and not
# when it is granted - which is exactly what two pending requests against one balance produce.
try time-in-lieu-below-zero Attendance \
  sed -i 's|    if (u.minutes > available) return #err(#balanceTooLow { asked = u.minutes; available });||' src/AttFold.mo

# A TIME-IN-LIEU BALANCE THAT IS NOT DERIVED FROM THE CLAIMS THAT EARNED IT - `totalHours` is
# derived from nothing in the received tree.
try time-in-lieu-balance-invented Attendance \
  sed -i 's|          b with earnedMinutes = b.earnedMinutes + o.minutes; asOfDay = c.day; lastBlock = c.block });|          b with earnedMinutes = b.earnedMinutes + o.minutes + 5; asOfDay = c.day; lastBlock = c.block });|' src/AttFold.mo

# A SWAP DECIDED WITHOUT THE CONSENT OF THE PERSON ASKED TO TAKE IT.
try swap-without-consent Attendance \
  sed -i 's|    if (s.targetAnswer == #pending) return #err(#targetHasNotAnswered { swapId });||' src/AttFold.mo

# A SWAP DECIDED BY ONE OF ITS OWN SIDES.
try swap-decided-by-a-side Attendance \
  sed -i 's|    if (c.caller == s.requester or c.caller == s.target) return #err(#selfDecision { subject = c.caller });||' src/AttFold.mo

# TWO OPEN SWAPS ON ONE SHIFT.
try two-open-swaps Attendance \
  sed -i 's|      case (?_) { return #err(#swapAlreadyOpen { assignmentId = f.assignmentId }) };|      case (?_) { };|' src/AttFold.mo

# TWO PLANNED SHIFTS FOR ONE PERSON ON ONE DAY - `assignShift` writes a new record every time.
try two-shifts-one-day Attendance \
  sed -i 's|      case (?_) { return #err(#shiftAlreadyAssigned { subject = f.subject; day = f.businessDay }) };|      case (?_) { };|' src/AttFold.mo

# TWO OPEN BREAKS FOR ONE PERSON - `startBreak` answers this by walking every break entry of every
# company; the partial index is what makes it a point read, and this takes the index away.
try two-open-breaks Attendance \
  sed -i 's|        keyOf = func(id : Nat, x : BreakEntry) : ?Blob { ignore id; if (x.isOpen) ?HR.memberKey(x.companyId, x.subject) else null } },|        keyOf = func(id : Nat, x : BreakEntry) : ?Blob { if (x.isOpen) ?CR.activityAssigneeKey(x.companyId, x.subject, id) else null } },|' src/AttRows.mo

# A BREAK TIMED BY SOMETHING OTHER THAN THE BLOCK.
try break-not-timed-by-the-block Attendance \
  sed -i 's|      startMinute = c.block % MINUTES_IN_DAY; endMinute = 0; isOpen = true; overLimit = false;|      startMinute = 0; endMinute = 0; isOpen = true; overLimit = false;|' src/AttFold.mo

# TWO HOLIDAYS ON ONE DAY, so "is this a working day" has two answers.
try two-holidays-one-day Attendance \
  sed -i 's|      case (?_) { return #err(#holidayTaken { day = f.businessDay }) };|      case (?_) { };|' src/AttFold.mo

# A WITHDRAWN HOLIDAY STILL ANSWERING - the index made total rather than partial.
try withdrawn-holiday-still-counts Attendance \
  sed -i 's|        keyOf = func(id : Nat, x : CompanyHoliday) : ?Blob { ignore id; if (x.isActive) ?holidayDayKey(x.companyId, x.businessDay) else null } },|        keyOf = func(id : Nat, x : CompanyHoliday) : ?Blob { ignore id; ?holidayDayKey(x.companyId, x.businessDay) } },|' src/AttRows.mo

# TWO LIVE WORKING-FROM-HOME REQUESTS FOR ONE PERSON ON ONE DAY.
try two-live-wfh-requests Attendance \
  sed -i 's|      case (?_) { return #err(#wfhAlreadyLive { subject = c.caller; day = f.businessDay }) };|      case (?_) { };|' src/AttFold.mo

# SOMEBODY APPROVING THEIR OWN DAY AT HOME.
try self-approved-wfh Attendance \
  sed -i 's|    if (r.subject == c.caller) return #err(#selfDecision { subject = c.caller });||' src/AttFold.mo

# TWO WORKING WEEKS FOR ONE COMPANY, because the settings table has no unique index.
try two-working-weeks Attendance \
  sed -i 's|        keyOf = func(id : Nat, x : WorkingHours) : ?Blob { ignore id; ?companyOnlyKey(x.companyId) } },|        keyOf = func(id : Nat, x : WorkingHours) : ?Blob { ?HR.companyKey(x.companyId, id) } },|' src/AttRows.mo

# A LADDER OF LATE DEDUCTIONS WITH TWO RUNGS AT ONE MINUTE.
try ladder-not-ascending Attendance \
  sed -i 's|      if (not first and t.afterMinutes <= previous) return #err(#minuteOutOfDay { minute = t.afterMinutes });||' src/AttFold.mo

# A REPLACED LADDER WHOSE OLD RUNGS ARE STILL IN THE INDEX.
try replaced-ladder-still-live Attendance \
  sed -i 's|      RowStore.put<AT.LateTier>(c.att.lateTiers, AT.lateTier, tid, { t with isActive = false; lastBlock = c.block });||' src/AttFold.mo

# AN AUTOMATIC CLOCK-OUT AFTER NO TIME AT ALL, which closes every shift the moment it opens.
try instant-auto-clock-out Attendance \
  sed -i 's|    if (f.autoClockOutEnabled and f.autoClockOutAfterMinutes == 0) return #err(#minutesZero { what = "an automatic clock-out" });||' src/AttFold.mo

# A SCHEDULED REPORT THAT REACHES NOBODY - the shape the CRM mailing had.
try report-reaches-nobody Attendance \
  sed -i 's|    if (f.recipients.size() == 0) return #err(#tooMany { what = "report recipients (a report reaching nobody)"; max = MAX_RECIPIENTS });||' src/AttFold.mo

# A SWEEP THAT NEVER TERMINATES, because a schedule it has run is still due inside the run'"'"'s own
# range - which is what taking the next run day from the message rather than from the plan does, and
# is the defect this battery found the first time it ran.
try sweep-never-terminates Attendance \
  sed -i 's|        s with lastRunDay = c.day; nextRunDay = run.throughDay + cadenceDays(s.cadence);|        s with lastRunDay = c.day; nextRunDay = c.day + cadenceDays(s.cadence);|' src/AttFold.mo

# A SWEEP WITH NO PLAN, so it becomes a function of what was created while it ran.
try report-sweep-no-plan Attendance \
  sed -i 's|    if (run.planHash != planHash) return #err(#planHashMismatch { runId });||' src/AttFold.mo

# TWO RUNS AT ONCE.
try two-report-runs Attendance \
  sed -i 's|      case (?(runId, _)) { return #err(#runAlreadyRunning { companyId; runId }) };|      case (?(runId, _)) { ignore runId };|' src/AttFold.mo

# A FACE TEMPLATE ENROLLED FOR SOMEBODY ELSE.
try face-enrolled-for-another Attendance \
  sed -i 's|    if (f.subject != c.caller) return #err(#notTheClaimant { id = 0; caller = c.caller });||' src/AttFold.mo

# TWO LIVE FACE TEMPLATES FOR ONE PERSON.
try two-live-face-templates Attendance \
  sed -i 's|        keyOf = func(id : Nat, x : FaceTemplate) : ?Blob { ignore id; if (x.isActive) ?HR.memberKey(x.companyId, x.subject) else null } },|        keyOf = func(id : Nat, x : FaceTemplate) : ?Blob { if (x.isActive) ?CR.activityAssigneeKey(x.companyId, x.subject, id) else null } },|' src/AttRows.mo

# ── recruitment: the careers page, offers, interviews, checks ─────────────────

# THE CAREERS PAGE WITH NO PRICE - which is `submitPublicApplication` as received: a `public shared
# func` with no caller check, no cost and no ceiling, on a substrate where anonymous principals are
# free.
try careers-no-proof-of-work Recruitment \
  sed -i 's|      case (#err e) return #err(#stamp { reason = Stamp.errorText(e) });|      case (#err _) {};|' src/RecFold.mo

# A STAMP THAT DOES NOT BIND THE DAY, so work bought once is spent for ever.
try careers-stamp-not-bound-to-the-day Recruitment \
  sed -i 's|    w.nat(day);|    w.nat(0);|' src/RecFold.mo

# A STAMP THAT DOES NOT BIND THE APPLICANT, so one stamp covers a thousand of them.
try careers-stamp-not-bound-to-the-applicant Recruitment \
  sed -i 's|    w.blob(fingerprint);|    w.blob(Blob.fromArray([]));|' src/RecFold.mo

# NO CEILING FOR THE DAY.
try careers-no-daily-ceiling Recruitment \
  sed -i 's|    if (used >= policy.dailyCeiling) return #err(#dailyCeilingReached { companyId = f.companyId; ceiling = policy.dailyCeiling });||' src/RecFold.mo

# NO CEILING FOR THE POSTING.
try careers-no-posting-ceiling Recruitment \
  sed -i 's|      return #err(#postingCeilingReached { postingId = f.postingId; ceiling = policy.perPostingCeiling });||' src/RecFold.mo

# THE SAME ADDRESS APPLYING TO ONE POSTING TWICE - the uniqueness taken off the index.
try careers-duplicate-application Recruitment \
  sed -i 's|        keyOf = func(id : Nat, x : PublicApplication) : ?Blob { ignore id; if (x.erasedDay == 0) ?postingFingerprintKey(x.companyId, x.postingId, x.fingerprint) else null } },|        keyOf = func(id : Nat, x : PublicApplication) : ?Blob { if (x.erasedDay == 0) ?CR.leadOwnerKey(x.companyId, x.postingId, id) else null } },|' src/RecRows.mo

# AN UNBOUNDED APPLICATION, from somebody the company has never met.
try careers-unbounded-application Recruitment \
  sed -i 's|      return #err(#tooMany { what = "bytes in one application"; max = MAX_APPLICATION_BYTES });||' src/RecFold.mo

# A CLOSED PAGE THAT STILL TAKES APPLICATIONS.
try careers-closed-page-still-open Recruitment \
  sed -i 's|    if (not policy.isOpen) return #err(#careersClosed { companyId = f.companyId });||' src/RecFold.mo

# AN APPLICATION TO A POSTING NOBODY OPENED.
try careers-applies-to-a-draft Recruitment \
  sed -i 's|    if (p.state != #open) return #err(#notInState { what = "posting"; id = f.postingId; state = postingStateName(p.state); wanted = "open" });||' src/RecFold.mo

# ERASURE THAT LEAVES NOTHING BEHIND - the hard delete the received tree does, spelled as a row
# that never records the day.
try erasure-leaves-no-record Recruitment \
  sed -i 's|      a with erasedDay = c.day; state = #withdrawn; lastBlock = c.block });|      a with state = #withdrawn; lastBlock = c.block });|' src/RecFold.mo

# ERASING A CANDIDATE AND LEAVING THE NOTES ABOUT THEM.
try erasure-leaves-the-notes Recruitment \
  sed -i 's|      switch (Evidence.erase(c.evs.ev, n.evidenceId, c.day, reason)) {|      switch (#ok({ dedupEpoch = 0 }) : { #ok : { dedupEpoch : Nat }; #err : Evidence.Error }) {|' src/RecFold.mo

# AN ERASED CANDIDATE STILL FOUND BY THEIR ADDRESS.
try erased-candidate-still-indexed Recruitment \
  sed -i 's|        keyOf = func(id : Nat, x : Candidate) : ?Blob { ignore id; if (x.erasedDay == 0) ?fingerprintKey(x.companyId, x.fingerprint) else null } },|        keyOf = func(id : Nat, x : Candidate) : ?Blob { ignore id; ?fingerprintKey(x.companyId, x.fingerprint) } },|' src/RecRows.mo

# THE SAME PERSON ADDED AS A CANDIDATE TWICE.
try candidate-not-unique Recruitment \
  sed -i 's|      case (?(candidateId, _)) { return #err(#candidateKnown { candidateId }) };|      case (?(candidateId, _)) { ignore candidateId };|' src/RecFold.mo

# ANYBODY IN THE COMPANY ANSWERING SOMEBODY ELSE'"'"'S OFFER - the received `respondToOffer` exactly.
try anybody-answers-an-offer Recruitment \
  sed -i 's|    if (o.subject != c.caller) return #err(#notTheCandidate { offerId; caller = c.caller });||' src/RecFold.mo

# AN OFFER THAT NEVER EXPIRES.
try offer-never-expires Recruitment \
  sed -i 's|      return #err(#offerStandsTooLong { days = f.expiryDay - c.day; max = MAX_OFFER_DAYS });||' src/RecFold.mo

# AN OFFER MADE IN A CURRENCY THE COMPANY HAS NEVER DECLARED - the received `createOffer` takes
# `currencyCode : Text` and stores whatever arrives, so the exponent that formats the figure is an
# assumption rather than a row.
try offer-currency-not-declared Recruitment \
  sed -i 's|      case null null;   // a code this company has not declared is not a currency it can be paid in|      case null ?field;|' src/RecFold.mo

# AN OFFER OF NOTHING.
try offer-of-no-salary Recruitment \
  sed -i 's|    if (f.baseMonthly == 0) return #err(#amountZero);||' src/RecFold.mo

# THE SAME PERSON WRITING AN OFFER AND SENDING IT.
try offer-written-and-sent-by-one Recruitment \
  sed -i 's|    if (o.createdBy == c.caller) return #err(#selfDecision { subject = c.caller });||' src/RecFold.mo

# AN ACCEPTED COUNTER-OFFER THAT LEAVES THE ORIGINAL SALARY ON THE OFFER - which is what keeping
# the counter in a field beside it amounts to.
try counter-offer-not-merged Recruitment \
  sed -i 's|      o with baseMonthly = k.baseMonthly; bonusRate = k.bonusRate; startDay = k.startDay;|      o with startDay = k.startDay;|' src/RecFold.mo

# THE CANDIDATE DECIDING THEIR OWN COUNTER-OFFER.
try candidate-decides-own-counter Recruitment \
  sed -i 's|    if (Principal.equal(o.subject, c.caller)) return #err(#selfDecision { subject = c.caller });||' src/RecFold.mo

# A CONTRACT WHOSE SALARY IS NOT THE OFFER'"'"'S.
try contract-salary-differs Recruitment \
  sed -i 's|      subject = o.subject; startDay = o.startDay; endDay = 0; value = o.baseMonthly;|      subject = o.subject; startDay = o.startDay; endDay = 0; value = o.baseMonthly + 1;|' src/RecFold.mo

# TWO CONTRACTS FROM ONE OFFER.
try two-contracts-from-one-offer Recruitment \
  sed -i 's|    if (o.contractId != F.NO_ID) return #err(#contractAlreadyMade { offerId; contractId = o.contractId });||' src/RecFold.mo

# AN OFFER THAT DOES NOT LEAVE THE DUE INDEX WHEN IT EXPIRES, so the sweep never terminates.
try offer-sweep-never-terminates Recruitment \
  sed -i 's|        keyOf = func(id : Nat, x : Offer) : ?Blob { ignore id; if (x.state == #sent or x.state == #underNegotiation) ?CR.dueKey(x.companyId, x.expiryDay, id) else null } },|        keyOf = func(id : Nat, x : Offer) : ?Blob { ?CR.dueKey(x.companyId, x.expiryDay, id) } },|' src/RecRows.mo

# A SWEEP WITH NO PLAN.
try offer-sweep-no-plan Recruitment \
  sed -i 's|    if (run.planHash != planHash) return #err(#planHashMismatch { runId });||' src/RecFold.mo

# AN INTERVIEW WITH NOBODY IN THE ROOM.
try interview-with-no-panel Recruitment \
  sed -i 's|    if (f.panelists.size() == 0) return #err(#tooMany { what = "interviewers (an interview with nobody in it)"; max = MAX_PANELISTS });||' src/RecFold.mo

# THE SAME PERSON TWICE ON ONE PANEL.
try panelist-twice Recruitment \
  sed -i 's|          return #err(#tooMany { what = "times one person may sit on one panel"; max = 1 });||' src/RecFold.mo

# A HIRING DECISION WITH NOTHING BEHIND IT - `makeHiringDecision` as received.
try hiring-decision-with-no-scorecard Recruitment \
  sed -i 's|    if (cards.size() == 0) return #err(#noScorecards { interviewId });||' src/RecFold.mo

# A SCORECARD FROM SOMEBODY WHO WAS NOT IN THE ROOM.
try scorecard-from-a-stranger Recruitment \
  sed -i 's|      case null { return #err(#notTheApplicant { id = f.interviewId; caller = c.caller }) };|      case null { };|' src/RecFold.mo

# TWO VERDICTS FROM ONE INTERVIEWER.
try two-scorecards-one-interviewer Recruitment \
  sed -i 's|        keyOf = func(id : Nat, x : Scorecard) : ?Blob { ignore id; ?interviewPersonKey(x.companyId, x.interviewId, x.interviewer) } },|        keyOf = func(id : Nat, x : Scorecard) : ?Blob { ?CR.leadOwnerKey(x.companyId, x.interviewId, id) } },|' src/RecRows.mo

# AN INTERVIEW COMPLETED BY A STATE SETTER, which is the way round the rule above.
try interview-completed-by-a-setter Recruitment \
  sed -i 's|      return #err(#notInState { what = "interview"; id = interviewId; state = "completed by makeHiringDecision"; wanted = "a state this command may set" });|      ignore interviewId;|' src/RecFold.mo

# A CHECK WITH NO CONSENT - the received check exactly.
try check-without-consent Recruitment \
  sed -i 's|    let ?consent = RowStore.get<RC.CheckConsent>(c.rec.consents, RC.checkConsent, f.consentId) else return #err(#noSuchConsent { consentId = f.consentId });|    let ?consent = RowStore.get<RC.CheckConsent>(c.rec.consents, RC.checkConsent, F.NO_ID) else return #err(#noSuchConsent { consentId = f.consentId });|' src/RecFold.mo

# A CHECK THAT IS NEVER ERASED - both halves of the rule, because either alone refuses a zero and
# the injection has to be the CLASS rather than one line of it.
try check-without-retention Recruitment \
  sed -i -e 's|    switch (checkDay(f.retentionDay)) { case (?r) return #err(r); case null {} };||' \
         -e 's|    if (f.retentionDay <= c.day) return #err(#dayInPast { day = f.retentionDay; today = c.day });||' src/RecFold.mo

# A CHECK WHOSE ANSWER IS A FIELD RATHER THAN THE PROVIDER'"'"'S OWN DOCUMENT.
try check-answer-without-a-document Recruitment \
  sed -i 's|    if (resultDocId == F.NO_ID) return #err(#nameRequired { what = "the provider.s answer, as a document" });||' src/RecFold.mo

# ONE CONSENT SPENT ON TWO CHECKS.
try consent-spent-twice Recruitment \
  sed -i 's|    if (consent.checkId != F.NO_ID) return #err(#alreadyAnswered { what = "consent"; id = f.consentId });||' src/RecFold.mo

# THE PERSON WHO OPENED A CHECK RECORDING ITS ANSWER.
try check-opened-and-answered-by-one Recruitment \
  sed -i 's|    if (k.createdBy == c.caller) return #err(#selfDecision { subject = c.caller });||' src/RecFold.mo

# A REWARD PAID TWICE.
try referral-reward-paid-twice Recruitment \
  sed -i 's|    if (r.rewardPayslipId != F.NO_ID) return #err(#rewardAlreadyPaid { referralId });||' src/RecFold.mo

# A REWARD PAID ON A REFERRAL NOBODY WAS HIRED FROM.
try referral-reward-without-a-hire Recruitment \
  sed -i 's|    if (r.state != #hired) return #err(#notInState { what = "referral"; id = referralId; state = referralStateName(r.state); wanted = "hired" });||' src/RecFold.mo

# THE REFERRER MOVING THEIR OWN REFERRAL TO HIRED.
try referrer-hires-their-own Recruitment \
  sed -i 's|    if (Principal.equal(r.referrer, c.caller)) return #err(#selfDecision { subject = c.caller });||' src/RecFold.mo

# SOMEBODY ELSE SUBMITTING A LEAVER'"'"'S OWN WORDS.
try exit-interview-submitted-by-another Recruitment \
  sed -i 's|    if (x.subject != c.caller) return #err(#notTheApplicant { id = f.exitId; caller = c.caller });||' src/RecFold.mo

# A REQUISITION APPROVED BY THE PERSON WHO RAISED IT.
try requisition-self-approved Recruitment \
  sed -i 's|    if (q.raisedBy == c.caller) return #err(#selfDecision { subject = c.caller });||' src/RecFold.mo

# A POSTING UNDER A REQUISITION NOBODY APPROVED.
try posting-without-an-approved-requisition Recruitment \
  sed -i 's|      if (q.state != #approved) return ?(#notInState { what = "requisition"; id = f.requisitionId; state = requisitionStateName(q.state); wanted = "approved" });||' src/RecFold.mo

# AN APPLICATION REVIEWED BY THE PERSON WHO MADE IT.
try application-self-reviewed Recruitment \
  sed -i 's|    if (a.subject == c.caller) return #err(#selfDecision { subject = c.caller });||' src/RecFold.mo


# ── the three-way match ───────────────────────────────────────────────────────
#
# Each of these makes a business pay for something it did not order, did not receive, or did not
# agree a price for. They are the reason the match exists, so each has a fault against it.

# THE KEYSTONE: billed for more than arrived. Without this check a supplier's invoice is paid on
# the supplier's own say-so and the delivery note is decoration.
try bill-exceeds-received Purchase \
  sed -i 's|          if (billedTotal > ol.quantityReceived) {|          if (false) {|' src/OrderFold.mo

# The price agreed is the price paid.
try bill-price-not-checked Purchase \
  sed -i 's|          if (ol.priceUnit != bl.priceUnit) {|          if (false) {|' src/OrderFold.mo

# A bill for something that was never on the order.
try bill-line-not-on-order Purchase \
  sed -i 's|      if (not matched) return #err(#billLineNotOnOrder { billId; categoryId = bl.categoryId });||' src/OrderFold.mo

# Four eyes on the act that decides money is owed.
try self-matched-bill Purchase \
  sed -i 's|    if (Principal.equal(b.recordedBy, c.caller)) return #err(#selfMatchedBill { recorder = b.recordedBy });||' src/OrderFold.mo

# A delivery counted twice: the same goods received once and billed twice.
try receipt-assigned-twice Purchase \
  sed -i 's|      case (?(_, existing)) return #err(#receiptAlreadyAssigned { pickingId; orderId = existing.orderId });|      case (?(_, _existing)) {};|' src/OrderFold.mo

# More delivered than ordered, accepted without anybody agreeing to buy it.
try receipt-exceeds-ordered Purchase \
  sed -i 's|          if (total > l.quantity) {|          if (false) {|' src/OrderFold.mo

# Nothing has arrived until the receipt is validated.
try receipt-not-validated Purchase \
  sed -i 's|    if (not r.isValidated) return #err(#receiptNotValidated { pickingId });||' src/OrderFold.mo

# A bill matched twice posts the liability twice.
try bill-matched-twice Purchase \
  sed -i 's|    if (b.state != #recorded) return #err(#billNotRecorded { billId; state = billStateName(b.state) });||' src/OrderFold.mo

# ── the migration ─────────────────────────────────────────────────────────────

# the splice one field early: quantityInvoiced lands where quantityBilled goes, and lastBlock's
# bytes shift. Observable only because the battery invoices an order first.
try splice-misplaced Migration \
  sed -i 's|      if (i < SPLICE_AT) old\[i\]|      if (i < SPLICE_AT - W.QTY) old[i]|' src/Migration.mo

# a carried counter left at genesis: the next line would take an id already on the store
try counter-not-carried Migration \
  sed -i 's|    s.nextOrderLineId := old.nextOrderLineId;||' src/Migration.mo

# the lines written without their index: the primary hashes right and nothing can find a line by
# its order. This is why the battery pages through the index and does not stop at the digest.
try index-not-derived Migration \
  sed -i 's|        RowStore.put<OR.OrderLine>(s.orderLines, OR.orderLine, id, OR.orderLine.decode(spliceLine(raw)));|        RowStore.put<OR.OrderLine>(s.orderLines, { OR.orderLine with indexes = [] }, id, OR.orderLine.decode(spliceLine(raw)));|' src/Migration.mo

# a table not carried: the orders store handed back empty
try table-not-carried Migration \
  sed -i 's|    s.orders := old.orders;||' src/Migration.mo

# the three-way match's counters dropped from the digest again - the fault this extension found
try new-counters-not-fingerprinted Migration \
  sed -i 's|      w.nat(s.ord.nextReceiptLinkId); w.nat(s.ord.nextBillId); w.nat(s.ord.nextBillLineId);||' src/State.mo

# ── the tax authority's document, its seal and its filing ─────────────────────

# the sealing certificate's taxpayer identifier not compared with the company's: any taxpayer's
# seal accepted on this company's document
try seal-identity-not-checked Eta \
  sed -i 's|    if (orgId != "VATEG-" # issuerTaxId) return #err(#sealNotForThisCompany { certificate = orgId; company = "VATEG-" # issuerTaxId });||' src/FinFold.mo

# a lapsed certificate accepted
try seal-validity-not-checked Eta \
  sed -i 's|    if (not X509.validOn(v.certificate, c.day)) return #err(#sealCertificateNotValidOnDay { day = c.day; notBefore = v.certificate.notBefore; notAfter = v.certificate.notAfter });||' src/FinFold.mo

# a certificate nobody vouches for accepted
try seal-anchor-not-checked Eta \
  sed -i 's|    if (not X509.issuedBy(v.certificate, anchor, H.sha256)) return #err(#sealNotAnchored);||' src/FinFold.mo

# the preparer sealing their own filing
try self-sealed Eta \
  sed -i 's|    if (x.preparedBy == c.caller) return #err(#selfSealed { preparer = c.caller });||' src/FinFold.mo

# a submission recorded for a filing that carries no seal
try unsealed-submission-allowed Eta \
  sed -i 's|    if (x.state != #sealed) return #err(#filingNotInState { filingId; state = filingStateName(x.state); wanted = "sealed" });||' src/FinFold.mo

# the serialisation with the property names left as they are: a digest the authority would not
# compute. Caught by the frozen vector, which was sealed over the upper-cased form.
try serialisation-not-uppercased Eta \
  sed -i 's|          let name = quoted(Text.toUpper(k));|          let name = quoted(k);|' src/EtaDocument.mo

# the array rule dropped: elements no longer preceded by the array's name
try serialisation-array-rule-dropped Eta \
  sed -i 's|              for (x in xs.vals()) { out #= name # serialize(x) };|              for (x in xs.vals()) { out #= serialize(x) };|' src/EtaDocument.mo

# a credit note past what was invoiced
try credit-exceeds-invoiced Eta \
  sed -i 's|      if (already + cl.quantity > l.quantityInvoiced) {|      if (false) {|' src/OrderFold.mo

# a credit note's filing prepared before the invoice was accepted: nothing to reference
try credit-filing-before-acceptance Eta \
  sed -i 's|    if (inv.state != #accepted) return #err(#invoiceNotAccepted { orderId = cn.orderId });||' src/FinFold.mo

# a document derived with a double quote in a field, which the authority's serialisation does not define
try unfilable-text-allowed Eta \
  sed -i 's|#err(#textNotFilable { field }) else #ok|#ok else #ok|' src/FinFold.mo

# ── the signers in order, and the seal ────────────────────────────────────────

# anybody signs, in any order: the turn not checked
try signature-out-of-turn Sign \
  sed -i 's|    if (not Principal.equal(next.signer, c.caller)) return #err(#notYourTurn { requestId; expected = next.signer; ordinal = next.ordinal });||' src/EvFold.mo

# somebody the request is not addressed to signs
try signer-not-named Sign \
  sed -i 's|    if (signerRow(c.evs, companyId, requestId, c.caller) == null) return #err(#notASigner { requestId; subject = c.caller });||' src/EvFold.mo

# a request signable though addressed to nobody
try unaddressed-request-signable Sign \
  sed -i 's|    let ?(nid, next) = nextSigner(c.evs, companyId, requestId) else return #err(#noSigners { requestId });|    let (nid, next) = switch (nextSigner(c.evs, companyId, requestId)) { case (?x) x; case null (0, { companyId; requestId; ordinal = 1; signer = c.caller; state = #pending; recordId = 0; lastBlock = 0 }) };|' src/EvFold.mo

# a request addressed twice: the order rewritten after somebody signed
try order-rewritten Sign \
  sed -i 's|    if (signersOf(c.evs, companyId, requestId).size() != 0) return #err(#signersAlreadyNamed { requestId });||' src/EvFold.mo

# the same person twice in one order
try signer-named-twice Sign \
  sed -i 's|      while (j < i) { if (Principal.equal(signers\[j\], p)) return #err(#signerRepeated { subject = p }); j += 1 };||' src/EvFold.mo

# a signature after the deadline
try signature-after-deadline Sign \
  sed -i 's|    if (c.day > r.deadlineDay) return #err(#requestExpired { requestId; deadlineDay = r.deadlineDay; day = c.day });||' src/EvFold.mo

# the calendar closing a request before its deadline
try expired-before-deadline Sign \
  sed -i 's|    if (c.day <= r.deadlineDay) return #err(#notYetExpired { requestId; deadlineDay = r.deadlineDay; day = c.day });||' src/EvFold.mo

# the last signature not completing the request: it stays open, and no seal is written
try completion-never-sealed Sign \
  sed -i 's|      case (?_) #ok(\[recordId, g.id\]);|      case _ #ok([recordId, g.id]);|' src/EvFold.mo

# the seal not covering the signatures: the content alone
try seal-ignores-the-signatures Sign \
  sed -i 's|    for ((_, x) in signers.vals()) {|    for ((_, x) in ([] : [(Nat, EV.SignatureSigner)]).vals()) {|' src/EvFold.mo

# a decline not closing the request
try decline-leaves-it-open Sign \
  sed -i 's|    RowStore.put<EV.SignatureRequest>(c.evs.requests, EV.signatureRequest, requestId, { r with state = #declined; lastBlock = c.block });||' src/EvFold.mo

# a post-quantum signature before the passkey turn
try post-quantum-before-passkey Sign \
  sed -i 's|    if (mine.state != #signed) return #err(#passkeyFirst { requestId = f.requestId; subject = c.caller });||' src/EvFold.mo

# ── the campaign: the audience, the deal, the calendar, the relay, the winner ──

# the deal ignores the rule: everybody is dealt into arm A
try deal-not-the-rule Campaign \
  sed -i 's|    if (r < testShare / 2) #a else if (r < testShare) #b else #remainder|    if (r < testShare / 2) #a else if (r < testShare) #a else #a|' src/CrmFold.mo

# the segment's rule moves under a running campaign and nobody notices
try segment-moved-unnoticed Campaign \
  sed -i 's|    if (s.ruleHash != cp.segmentHash) return #err(#segmentMovedUnderCampaign { campaignId });||' src/CrmFold.mo

# the campaign's audience deduplicated by nothing: four spellings of one address are four people
try audience-not-deduplicated Campaign \
  sed -i 's|          let dk = CR.recipientAddressKey(companyId, campaignId, key);|          let dk = CR.recipientAddressKey(companyId, campaignId, CR.addressKey(Nat.toText(leadId)));|' src/CrmFold.mo

# the audience's count not held to what the launcher declared
try audience-count-unchecked Campaign \
  sed -i 's|    if (total > cp.expected or (lastPage and total != cp.expected)) {|    if (false) {|' src/CrmFold.mo

# whoever made the campaign launches it
try self-launch-allowed Campaign \
  sed -i 's|    if (Principal.equal(cp.createdBy, c.caller)) return #err(#selfLaunch { subject = c.caller });||' src/CrmFold.mo

# an arm planned, launched or cancelled as a mailing of its own: the ownership check gone from
# all three mailing commands
try arm-plannable-as-a-mailing Campaign \
  sed -i 's|    switch (notOwned(c, companyId, mailingId)) { case (?r) return #err(r); case null {} };|    ignore notOwned(c, companyId, mailingId);|' src/CrmFold.mo

# the schedule not enforced: a claim before the scheduled day goes out
try schedule-not-the-calendars Campaign \
  sed -i 's|    if (c.day < m.scheduledDay) return #err(#notYetScheduled { mailingId; scheduledDay = m.scheduledDay; day = c.day });||' src/CrmFold.mo

# the claim does not read the suppression list: a late unsubscribe is sent to
try claim-ignores-late-suppression Campaign \
  sed -i 's|        case (?_) List.add(silenced, (id, r));|        case (?_) List.add(claimable, (id, r));|' src/CrmFold.mo

# the remainder's filling does not read the suppression list
try remainder-ignores-late-suppression Campaign \
  sed -i 's|      let suppressedHere = switch (activeSuppression(c, companyId, x.addressKey)) { case (?_) true; case null false };|      let suppressedHere = false;|' src/CrmFold.mo

# the winner decided before the decision day
try decision-before-its-day Campaign \
  sed -i 's|    if (c.day < cp.decideDay) return #err(#tooEarlyToDecide { campaignId; decideDay = cp.decideDay; day = c.day });||' src/CrmFold.mo

# the winner decided while an arm is still sending
try decision-while-arm-sending Campaign \
  sed -i 's|    if (mB.state != #done) return #err(#armStillSending { campaignId; mailingId = cp.mailingB });||' src/CrmFold.mo

# the winner rule ignored: opens decide a campaign that recorded clicks
try winner-rule-ignored Campaign \
  sed -i 's|    let figureA = switch (cp.winnerRule) { case (#opens) armA.opens; case (#clicks) armA.clicks };|    let figureA = armA.opens;|; s|    let figureB = switch (cp.winnerRule) { case (#opens) armB.opens; case (#clicks) armB.clicks };|    let figureB = armB.opens;|' src/CrmFold.mo

# a tie goes to B
try tie-goes-to-b Campaign \
  sed -i 's|    let aWins = if (mA.sent == 0) false else if (mB.sent == 0) true else figureA \* mB.sent >= figureB \* mA.sent;|    let aWins = if (mA.sent == 0) false else if (mB.sent == 0) true else figureA * mB.sent > figureB * mA.sent;|' src/CrmFold.mo

# the remainder sent arm A's content whoever won
try remainder-not-the-winners Campaign \
  sed -i 's|    let winnerMailing = if (aWins) mA else mB;|    let winnerMailing = mA;|' src/CrmFold.mo

# the same acknowledgement recorded twice: an open is however many times the pixel fired
try engagement-counted-twice Campaign \
  sed -i 's|      if (engagementRecorded(c, f.companyId, f.mailingId, rid, kind)) {|      if (false) {|' src/CrmFold.mo

# an acknowledgement about somebody who was never sent to
try engagement-for-the-unsent Campaign \
  sed -i 's|      if (r.state != #sent) return #err(#recipientNotSent { recipientId = rid; state = recipientStateName(r.state) });||' src/CrmFold.mo

# an unsubscribe counted and not honoured
try unsubscribe-not-a-suppression Campaign \
  sed -i 's|        case (#unsubscribe) { unsubscribes += 1; suppressByEvent(c, f.companyId, r, #unsubscribed) };|        case (#unsubscribe) { unsubscribes += 1 };|' src/CrmFold.mo

# the campaign completes with an arm still sending
try completes-with-an-arm-unfinished Campaign \
  sed -i 's|            if (m.state != #done) return #err(#notEveryArmDone { campaignId; mailingId = a.mailingId });||' src/CrmFold.mo

# cancelling the campaign leaves its arms live
try cancel-leaves-arms-live Campaign \
  sed -i 's|                if (m.state != #done and m.state != #cancelled) {|                if (false) {|' src/CrmFold.mo

# the campaign table left out of the fingerprint
try fingerprint-misses-the-campaigns Campaign \
  sed -i 's|    section<CrmRows.Campaign>(s, f, "campaign", s.crm.campaigns, CrmRows.campaign, func(r) { \[r.name\] });||' src/State.mo

# the engagement table left out of the fingerprint
try fingerprint-misses-the-engagement Campaign \
  sed -i 's|    section<CrmRows.Engagement>(s, f, "engagement", s.crm.engagements, CrmRows.engagement, func(_r) { \[\] });||' src/State.mo

# the seals left out of the fingerprint
try fingerprint-misses-the-seals Sign \
  sed -i 's|    section<EvRows.SignatureSeal>(s, f, "signature_seal", s.evs.seals, EvRows.signatureSeal, func(_r) { \[\] });||' src/State.mo

# ── the helpdesk ─────────────────────────────────────────────────────────────

# a second team on the same code: a new row instead of the one changed
try helpdesk-team-code-not-unique Helpdesk \
  sed -i 's|    switch (teamByCode(c\.hd, f\.companyId, code)) {|    switch (null : ?(Nat, HDR.HelpdeskTeam)) {|' src/HdFold.mo

# a lead who is not a member of the company accepted
try helpdesk-lead-not-a-member Helpdesk \
  sed -i 's|    if (not c\.isMember(f\.companyId, f\.lead)) return #err(#notAMember { companyId = f\.companyId; subject = f\.lead });|    if (false) return #err(#notAMember { companyId = f.companyId; subject = f.lead });|' src/HdFold.mo

# a retired team declared again stays retired
try helpdesk-redeclared-stays-retired Helpdesk \
  sed -i 's|        RowStore\.put<HDR\.HelpdeskTeam>(c\.hd\.teams, HDR\.helpdeskTeam, id, { x with name; lead = f\.lead; isActive = true; declaredBy = c\.caller; lastBlock = c\.block });|        RowStore.put<HDR.HelpdeskTeam>(c.hd.teams, HDR.helpdeskTeam, id, { x with name; lead = f.lead; isActive = x.isActive; declaredBy = c.caller; lastBlock = c.block });|' src/HdFold.mo

# a team retired with tickets still open
try helpdesk-retired-with-open-tickets Helpdesk \
  sed -i 's|    if (t\.openTickets > 0) return #err(#teamHasOpenTickets { teamId; open = t\.openTickets });|    if (false) return #err(#teamHasOpenTickets { teamId; open = t.openTickets });|' src/HdFold.mo

# a retired team still takes tickets, stages and promises
try helpdesk-retired-team-takes-tickets Helpdesk \
  sed -i 's|    if (not t\.isActive) return #err(#teamRetired { teamId });|    if (false) return #err(#teamRetired { teamId });|' src/HdFold.mo

# a second stage on the same code: a new column instead of the one changed
try helpdesk-stage-code-not-unique Helpdesk \
  sed -i 's|    switch (stageByCode(c\.hd, f\.teamId, code)) {|    switch (null : ?(Nat, HDR.TicketStage)) {|' src/HdFold.mo

# a ticket enters a stage that closes
try helpdesk-first-stage-may-close Helpdesk \
  sed -i 's|    for ((id, s) in stagesOf(st, teamId)\.vals()) { if (not s\.closes) return ?(id, s) };|    for ((id, s) in stagesOf(st, teamId).vals()) { return ?(id, s) };|' src/HdFold.mo

# the board ordered by id, not by ordinal
try helpdesk-board-not-in-order Helpdesk \
  sed -i 's|        keyOf = func(id : Nat, x : TicketStage) : ?Blob { ?teamOrdinalKey(x\.teamId, x\.ordinal, id) } },|        keyOf = func(id : Nat, x : TicketStage) : ?Blob { ?teamOrdinalKey(x.teamId, 0, id) } },|' src/HdRows.mo

# an ordinal beyond the board accepted
try helpdesk-ordinal-unbounded Helpdesk \
  sed -i 's|    if (f\.ordinal > MAX_ORDINAL) return #err(#ordinalBound { ordinal = f\.ordinal; max = MAX_ORDINAL });|    if (false) return #err(#ordinalBound { ordinal = f.ordinal; max = MAX_ORDINAL });|' src/HdFold.mo

# a resolution promised before the answer
try helpdesk-resolve-before-response Helpdesk \
  sed -i 's|    if (f\.resolveDays < f\.responseDays) return #err(#resolveBeforeResponse { responseDays = f\.responseDays; resolveDays = f\.resolveDays });|    if (false) return #err(#resolveBeforeResponse { responseDays = f.responseDays; resolveDays = f.resolveDays });|' src/HdFold.mo

# an answer in no days, or beyond the year
try helpdesk-sla-days-unbounded Helpdesk \
  sed -i 's|    if (f\.responseDays == 0 or f\.responseDays > MAX_SLA_DAYS) return #err(#daysBound { days = f\.responseDays; max = MAX_SLA_DAYS });|    if (false) return #err(#daysBound { days = f.responseDays; max = MAX_SLA_DAYS });|' src/HdFold.mo

# a ticket at a priority the team promised nothing for
try helpdesk-no-promise-takes-ticket Helpdesk \
  sed -i 's|    let ?(_, sla) = serviceLevelOf(c\.hd, f\.teamId, f\.priority) else return #err(#noServiceLevel { teamId = f\.teamId; priority = priorityText(f\.priority) });|    let sla : HDR.ServiceLevel = switch (serviceLevelOf(c.hd, f.teamId, f.priority)) { case (?(_, l)) l; case null { { companyId = 0; teamId = 0; priority = f.priority; responseDays = 1; resolveDays = 1; setBy = c.caller; lastBlock = 0 } } };|' src/HdFold.mo

# a ticket raised by somebody who is not a member
# Not injected, and why: helpdesk-stranger-raises-ticket - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# THE CLOCK COUNTS A HOLIDAY as a working day
try helpdesk-clock-ignores-holidays Helpdesk \
  sed -i 's|    inWorkingWeek(c\.workingWeek(companyId), day) and not c\.isHoliday(companyId, day)|    inWorkingWeek(c.workingWeek(companyId), day)|' src/HdFold.mo

# THE CLOCK COUNTS THE REST DAYS of the working week
try helpdesk-clock-ignores-rest-days Helpdesk \
  sed -i 's|      case (?m) (m / (2 \*\* weekBit(day))) % 2 == 1;|      case (?m) { ignore m; true };|' src/HdFold.mo

# the clock counts calendar days: the walk never skips
try helpdesk-clock-counts-calendar-days Helpdesk \
  sed -i 's|      while (not isWorking(d) and rest < MAX_REST_RUN) { d += 1; rest += 1 };|      if (false) { d += 1; rest += 1 };|' src/HdFold.mo

# the week read off by a day: Sunday in bit 6
try helpdesk-week-bit-off-by-one Helpdesk \
  sed -i 's|  public func weekBit(day : Nat) : Nat { (day + 4) % 7 };|  public func weekBit(day : Nat) : Nat { (day + 3) % 7 };|' src/HdFold.mo

# a company with no working week declared works no day
try helpdesk-no-week-works-nothing Helpdesk \
  sed -i 's|      case null true;|      case null false;|' src/HdFold.mo

# the requester's own word stops the response clock
try helpdesk-requester-word-stops-clock Helpdesk \
  sed -i 's|    let kind : E\.TicketMessageKind = if (c\.caller == t\.requester) #requester else #agent;|    let kind : E.TicketMessageKind = #agent;|' src/HdFold.mo

# every agent's word moves the response clock, not the first
try helpdesk-later-word-moves-clock Helpdesk \
  sed -i 's|    let firstResponseDay = if (kind == #agent and t\.firstResponseDay == 0) c\.day else t\.firstResponseDay;|    let firstResponseDay = if (kind == #agent) c.day else t.firstResponseDay;|' src/HdFold.mo

# a stranger writes on a ticket
# Not injected, and why: helpdesk-stranger-writes - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# THE REQUESTER ASSIGNS their own ticket
try helpdesk-requester-assigns Helpdesk \
  sed -i 's|    if (c\.caller == t\.requester) return #err(#requesterActing { requester = t\.requester; act = "assign" });|    if (false) return #err(#requesterActing { requester = t.requester; act = "assign" });|' src/HdFold.mo

# a ticket assigned to somebody who is not a member
try helpdesk-assign-to-stranger Helpdesk \
  sed -i 's|    if (not c\.isMember(companyId, assignee)) return #err(#notAMember { companyId; subject = assignee });|    if (false) return #err(#notAMember { companyId; subject = assignee });|' src/HdFold.mo

# THE REQUESTER MOVES AND CLOSES their own ticket
try helpdesk-requester-moves Helpdesk \
  sed -i 's|    if (c\.caller == t\.requester) return #err(#requesterActing { requester = t\.requester; act = "move" });|    if (false) return #err(#requesterActing { requester = t.requester; act = "move" });|' src/HdFold.mo

# a ticket moved onto another team's board
try helpdesk-stage-of-another-board Helpdesk \
  sed -i 's|    if (s\.teamId != t\.teamId) return #err(#stageNotOfTeam { stageId; teamId = t\.teamId });|    if (false) return #err(#stageNotOfTeam { stageId; teamId = t.teamId });|' src/HdFold.mo

# a stage that closes leaves the ticket open
try helpdesk-closing-stage-does-not-close Helpdesk \
  sed -i 's|    if (s\.closes) {|    if (false) {|' src/HdFold.mo

# a closed ticket still moved, assigned and written on
try helpdesk-closed-ticket-still-moves Helpdesk \
  sed -i 's|    if (t\.state != #open) return #err(#ticketClosed { ticketId });|    if (false) return #err(#ticketClosed { ticketId });|' src/HdFold.mo

# the team's open count not kept
try helpdesk-team-counts-not-kept Helpdesk \
  sed -i 's|    RowStore\.put<HDR\.HelpdeskTeam>(c\.hd\.teams, HDR\.helpdeskTeam, f\.teamId, { team with ticketsOpened = team\.ticketsOpened + 1; openTickets = team\.openTickets + 1; lastBlock = c\.block });|    RowStore.put<HDR.HelpdeskTeam>(c.hd.teams, HDR.helpdeskTeam, f.teamId, { team with ticketsOpened = team.ticketsOpened + 1; openTickets = team.openTickets; lastBlock = c.block });|' src/HdFold.mo

# THE OPENER OF THE SWEEP slices it
try helpdesk-sweep-opener-slices Helpdesk \
  sed -i 's|    if (c\.caller == run\.openedBy) return #err(#selfEscalating { opener = run\.openedBy });|    if (false) return #err(#selfEscalating { opener = run.openedBy });|' src/HdFold.mo

# a sweep through a day that has not come
try helpdesk-sweep-horizon-not-checked Helpdesk \
  sed -i 's|    if (throughDay > c\.day) return #err(#horizonNotReached { throughDay; day = c\.day });|    if (false) return #err(#horizonNotReached { throughDay; day = c.day });|' src/HdFold.mo

# the sweep reads no head: nothing is ever escalated
try helpdesk-sweep-walks-nothing Helpdesk \
  sed -i 's|    let page = breached(c\.hd, companyId, run\.throughDay, limit);|    let page = breached(c.hd, companyId, 0, limit);|' src/HdFold.mo

# every escalation is level 1: the sweep revisits forever
try helpdesk-escalation-level-stuck Helpdesk \
  sed -i 's|      let level = if (t\.escalation == 0 and t\.firstResponseDay == 0) 1 else 2;|      let level = 1;|' src/HdFold.mo

# an escalation leaves the priority where it was
try helpdesk-priority-not-raised Helpdesk \
  sed -i 's|      RowStore\.put<HDR\.Ticket>(c\.hd\.tickets, HDR\.ticket, ticketId, { t with escalation = level; priority = raised(t\.priority); assignee = lead; messages = t\.messages + 1; lastBlock = c\.block });|      RowStore.put<HDR.Ticket>(c.hd.tickets, HDR.ticket, ticketId, { t with escalation = level; priority = t.priority; assignee = lead; messages = t.messages + 1; lastBlock = c.block });|' src/HdFold.mo

# an escalated ticket stays on the desk it was on
try helpdesk-escalation-not-to-the-lead Helpdesk \
  sed -i 's|      RowStore\.put<HDR\.Ticket>(c\.hd\.tickets, HDR\.ticket, ticketId, { t with escalation = level; priority = raised(t\.priority); assignee = lead; messages = t\.messages + 1; lastBlock = c\.block });|      RowStore.put<HDR.Ticket>(c.hd.tickets, HDR.ticket, ticketId, { t with escalation = level; priority = raised(t.priority); assignee = t.assignee; messages = t.messages + 1; lastBlock = c.block });|' src/HdFold.mo

# an answered ticket is still held to its response deadline
try helpdesk-pending-ignores-the-answer Helpdesk \
  sed -i 's|    if (t\.escalation == 0 and t\.firstResponseDay == 0) return ?t\.responseDueDay;|    if (t.escalation == 0) return ?t.responseDueDay;|' src/HdRows.mo

# a ticket escalated twice is held to its resolution a third time
try helpdesk-escalated-twice-still-held Helpdesk \
  sed -i 's|    if (t\.escalation < 2) return ?t\.resolveDueDay;|    if (t.escalation < 3) return ?t.resolveDueDay;|' src/HdRows.mo

# a closed ticket is still held to a deadline, and swept
try helpdesk-closed-still-held Helpdesk \
  sed -i 's|    if (t\.state != #open) return null;|    if (false) return null;|' src/HdRows.mo

# the last page does not close the run
try helpdesk-run-never-closes Helpdesk \
  sed -i 's|    let lastPage = page\.size() < limit;|    let lastPage = false;|' src/HdFold.mo

# the ticket table left out of the fingerprint
try helpdesk-fingerprint-misses-the-tickets Helpdesk \
  sed -i 's|    section<HdRows\.Ticket>(s, f, "ticket", s\.hd\.tickets, HdRows\.ticket, func(r) { \[r\.subject, r\.description\] });||' src/State.mo

# ── field service ────────────────────────────────────────────────────────────

# a second rate for the company: a new row instead of the one changed
try fieldservice-rate-not-unique Fieldservice \
  sed -i 's|    switch (rateOf(c\.fs, f\.companyId)) {|    switch (null : ?(Nat, FSR.ServiceRate)) {|' src/FsFold.mo

# an hour sold for nothing, or beyond its field
try fieldservice-rate-of-nothing Fieldservice \
  sed -i 's|    if (f\.hourlyRate == 0 or f\.hourlyRate > MAX_RATE) return #err(#rateBound { what = "an hourly rate"; value = f\.hourlyRate; max = MAX_RATE });|    if (false) return #err(#rateBound { what = "an hourly rate"; value = f.hourlyRate; max = MAX_RATE });|' src/FsFold.mo

# a rate under another company's category
try fieldservice-rate-foreign-category Fieldservice \
  sed -i 's|    if (cat\.companyId != f\.companyId) return #err(#wrongCompany { expected = f\.companyId; found = cat\.companyId });|    if (false) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });|' src/FsFold.mo

# A VISIT PLANNED TO A SUPPLIER
try fieldservice-visit-to-a-supplier Fieldservice \
  sed -i 's|    if (not p\.isCustomer) return #err(#partnerNotACustomer { partnerId = f\.partnerId });|    if (false) return #err(#partnerNotACustomer { partnerId = f.partnerId });|' src/FsFold.mo

# a visit for another company's customer
try fieldservice-visit-partner-of-another-company Fieldservice \
  sed -i 's|    if (p\.companyId != f\.companyId) return #err(#wrongCompany { expected = f\.companyId; found = p\.companyId });|    if (false) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });|' src/FsFold.mo

# (a technician who is not a member is defended twice - the project fold refuses the task's assignee as
# well - so removing this fold's check alone leaves the battery green; it is not injected. One visit per
# task is an index no command can violate, since every visit makes its own task; not injected either.)
# a tax rate beyond sense accepted
try fieldservice-rate-tax-unbounded Fieldservice \
  sed -i 's|    if (f\.taxRate > MAX_TAX_RATE) return #err(#rateBound { what = "a tax rate"; value = f\.taxRate; max = MAX_TAX_RATE });|    if (false) return #err(#rateBound { what = "a tax rate"; value = f.taxRate; max = MAX_TAX_RATE });|' src/FsFold.mo

# THE PLANNER DISPATCHES THEMSELVES
try fieldservice-self-dispatch Fieldservice \
  sed -i 's|    if (f\.technician == c\.caller) return #err(#selfDispatch { planner = c\.caller });|    if (false) return #err(#selfDispatch { planner = c.caller });|' src/FsFold.mo

# a visit from a closed ticket
try fieldservice-closed-ticket-visited Fieldservice \
  sed -i 's|      if (t\.state != #open) return #err(#ticketClosed { ticketId = f\.ticketId });|      if (false) return #err(#ticketClosed { ticketId = f.ticketId });|' src/FsFold.mo

# a visit from a ticket about another customer
try fieldservice-ticket-of-another-partner Fieldservice \
  sed -i 's|      if (t\.partnerId != 0 and t\.partnerId != f\.partnerId) return #err(#ticketOfAnotherPartner { ticketId = f\.ticketId; partnerId = t\.partnerId });|      if (false) return #err(#ticketOfAnotherPartner { ticketId = f.ticketId; partnerId = t.partnerId });|' src/FsFold.mo

# a window that runs backwards
try fieldservice-window-backwards Fieldservice \
  sed -i 's|    if (f\.windowToDay < f\.windowFromDay) return #err(#windowBackwards { fromDay = f\.windowFromDay; toDay = f\.windowToDay });|    if (false) return #err(#windowBackwards { fromDay = f.windowFromDay; toDay = f.windowToDay });|' src/FsFold.mo

# a window that has passed
try fieldservice-window-passed Fieldservice \
  sed -i 's|    if (f\.windowToDay < c\.day) return #err(#windowPassed { toDay = f\.windowToDay; day = c\.day });|    if (false) return #err(#windowPassed { toDay = f.windowToDay; day = c.day });|' src/FsFold.mo

# the visit's task made on the planner's desk
try fieldservice-task-not-on-the-technicians-desk Fieldservice \
  sed -i 's|    let taskFacts : JF\.TaskFacts = { companyId = f\.companyId; projectId = 0; origin = #fieldService; title = f\.title; assignee = f\.technician; priority = f\.priority; dueDay = f\.windowToDay };|    let taskFacts : JF.TaskFacts = { companyId = f.companyId; projectId = 0; origin = #fieldService; title = f.title; assignee = c.caller; priority = f.priority; dueDay = f.windowToDay };|' src/FsFold.mo

# a cancelled visit leaves its task open
try fieldservice-cancel-leaves-the-task Fieldservice \
  sed -i 's|    switch (c\.setTaskState(companyId, v\.taskId, #cancelled)) { case (#err r) return #err(#proj r); case (#ok _) {} };|    ignore v.taskId;|' src/FsFold.mo

# a visit acted on whatever its state
try fieldservice-visit-state-not-checked Fieldservice \
  sed -i 's|    if (v\.state != wanted) return #err(#visitNotInState { visitId; state = stateText(v\.state); wanted = stateText(wanted) });|    if (false) return #err(#visitNotInState { visitId; state = stateText(v.state); wanted = stateText(wanted) });|' src/FsFold.mo

# ANYBODY COMPLETES THE TECHNICIAN'S VISIT
try fieldservice-anybody-completes Fieldservice \
  sed -i 's|    if (c\.caller != v\.technician) return #err(#notTheTechnician { technician = v\.technician });|    if (false) return #err(#notTheTechnician { technician = v.technician });|' src/FsFold.mo

# a visit completed on a day that has not come
try fieldservice-completed-tomorrow Fieldservice \
  sed -i 's|    if (f\.day > c\.day) return #err(#horizonNotReached { day = f\.day; today = c\.day });|    if (false) return #err(#horizonNotReached { day = f.day; today = c.day });|' src/FsFold.mo

# PARTS DELIVERED TO A SHELF, not to the customer
try fieldservice-parts-to-a-shelf Fieldservice \
  sed -i 's|      if (to\.usage != #customer) return #err(#partsLocationNotCustomer { locationId = f\.toLocationId });|      if (false) return #err(#partsLocationNotCustomer { locationId = f.toLocationId });|' src/FsFold.mo

# the parts delivery not asked about whole: a refusal leaves the picking behind
try fieldservice-parts-not-asked-whole Fieldservice \
  sed -i 's|      switch (c\.checkPicking(facts, f\.journalId)) { case (?r) return #err(#stock r); case null {} };|      ignore facts;|' src/FsFold.mo

# the task stays open after the visit: time keeps being logged on it
try fieldservice-task-not-closed-with-the-visit Fieldservice \
  sed -i 's|    switch (c\.setTaskState(f\.companyId, v\.taskId, #done)) { case (#err r) return #err(#proj r); case (#ok _) {} };|    ignore v.taskId;|' src/FsFold.mo

# every visit counted as inside its window
try fieldservice-window-not-judged Fieldservice \
  sed -i 's|      v with state = #done; doneDay = f\.day; inWindow = f\.day >= v\.windowFromDay and f\.day <= v\.windowToDay; partsPickingId = pickingId; note; lastBlock = c\.block });|      v with state = #done; doneDay = f.day; inWindow = true; partsPickingId = pickingId; note; lastBlock = c.block });|' src/FsFold.mo

# THE TECHNICIAN INVOICES THEIR OWN VISIT
try fieldservice-technician-invoices Fieldservice \
  sed -i 's|    if (c\.caller == v\.technician) return #err(#selfInvoicing { technician = v\.technician });|    if (false) return #err(#selfInvoicing { technician = v.technician });|' src/FsFold.mo

# time still on an undecided sheet invoiced
try fieldservice-pending-time-invoiced Fieldservice \
  sed -i 's|    if (time\.pending > 0) return #err(#timeNotApproved { taskId = v\.taskId; pendingMinutes = time\.pending });|    if (false) return #err(#timeNotApproved { taskId = v.taskId; pendingMinutes = time.pending });|' src/FsFold.mo

# THE SALE NOT ASKED ABOUT WHOLE: a customer past their limit leaves an order behind
try fieldservice-sale-not-asked-whole Fieldservice \
  sed -i 's|    switch (c\.checkSale(order, journalId)) { case (?r) return #err(#order r); case null {} };|    ignore order;|' src/FsFold.mo

# the labour line's quantity in minutes, not hours
try fieldservice-labour-in-minutes Fieldservice \
  sed -i 's|      List\.add(out, { categoryId = rate\.labourCategoryId; name = "labour " # Nat\.toText(approvedMinutes) # " min"; quantity = hoursThousandths(approvedMinutes); priceUnit = rate\.hourlyRate; taxRate = rate\.taxRate });|      List.add(out, { categoryId = rate.labourCategoryId; name = "labour " # Nat.toText(approvedMinutes) # " min"; quantity = approvedMinutes * 1_000; priceUnit = rate.hourlyRate; taxRate = rate.taxRate });|' src/FsFold.mo

# hours to the thousandth rounded down, not half to even
try fieldservice-hours-rounded-down Fieldservice \
  sed -i 's|    PE\.quantiseWithResidue(exact, { code = "H"; minorUnits = 0 })\.units|    ignore exact; minutes * 1_000 / 60|' src/FsFold.mo

# the parts invoiced at nothing
try fieldservice-parts-not-priced Fieldservice \
  sed -i 's|      List\.add(out, { categoryId = p\.categoryId; name = "part " # Nat\.toText(p\.ordinal); quantity = p\.quantity; priceUnit = p\.priceUnit; taxRate = rate\.taxRate });|      List.add(out, { categoryId = p.categoryId; name = "part " # Nat.toText(p.ordinal); quantity = p.quantity; priceUnit = 0; taxRate = rate.taxRate });|' src/FsFold.mo

# the approved minutes not fixed on the invoiced visit
try fieldservice-labour-minutes-not-fixed Fieldservice \
  sed -i 's|    RowStore\.put<FSR\.Visit>(c\.fs\.visits, FSR\.visit, visitId, { v with state = #invoiced; labourMinutes = time\.approved; orderId; invoiceMoveId = moveId; invoicedBy = c\.caller; lastBlock = c\.block });|    RowStore.put<FSR.Visit>(c.fs.visits, FSR.visit, visitId, { v with state = #invoiced; labourMinutes = 0; orderId; invoiceMoveId = moveId; invoicedBy = c.caller; lastBlock = c.block });|' src/FsFold.mo

# the order fold's dry run skips the customer's credit
try fieldservice-dry-run-misses-the-credit Fieldservice \
  sed -i 's|      switch (c\.creditCheck(f\.companyId, f\.partnerId, pricing\.untaxed + pricing\.tax)) { case (?r) return ?(#credit r); case null {} };|      ignore pricing;|' src/OrderFold.mo

# a visit without a place
try fieldservice-visit-without-a-place Fieldservice \
  sed -i 's|    if (Text\.size(f\.location) == 0) return #err(#nameRequired { what = "visit'\''s location" });|    if (false) return #err(#nameRequired { what = "visit'\''s location" });|' src/FsFold.mo

# the visit table left out of the fingerprint
try fieldservice-fingerprint-misses-the-visits Fieldservice \
  sed -i 's|    section<FsRows\.Visit>(s, f, "visit", s\.fs\.visits, FsRows\.visit, func(r) { \[r\.location, r\.note\] });||' src/State.mo

# ── appointments ─────────────────────────────────────────────────────────────

# a second resource on the same code: a new row instead of the one changed
try appointments-resource-code-not-unique Appointments \
  sed -i 's|    switch (resourceByCode(c\.apt, f\.companyId, code)) {|    switch (null : ?(Nat, APR.BookableResource)) {|' src/AptFold.mo

# hours that end before they begin accepted
try appointments-hours-backwards Appointments \
  sed -i 's|    if (f\.closeMinute <= f\.openMinute) return #err(#hoursBackwards { startMinute = f\.openMinute; endMinute = f\.closeMinute });|    if (false) return #err(#hoursBackwards { startMinute = f.openMinute; endMinute = f.closeMinute });|' src/AptFold.mo

# a week of no days accepted
try appointments-week-of-no-days Appointments \
  sed -i 's|    if (f\.daysMask == 0) return #err(#daysMaskEmpty);|    if (false) return #err(#daysMaskEmpty);|' src/AptFold.mo

# a week with bits beyond it accepted
try appointments-week-beyond-a-week Appointments \
  sed -i 's|    if (f\.daysMask > 127) return #err(#daysMaskOutOfRange { mask = f\.daysMask });|    if (false) return #err(#daysMaskOutOfRange { mask = f.daysMask });|' src/AptFold.mo

# a notice beyond the year accepted
try appointments-notice-unbounded Appointments \
  sed -i 's|    if (f\.cancelNoticeDays > MAX_NOTICE_DAYS) return #err(#noticeBound { days = f\.cancelNoticeDays; max = MAX_NOTICE_DAYS });|    if (false) return #err(#noticeBound { days = f.cancelNoticeDays; max = MAX_NOTICE_DAYS });|' src/AptFold.mo

# A KEEPER WHO IS NOT A MEMBER accepted
try appointments-keeper-not-a-member Appointments \
  sed -i 's|    if (not c\.isMember(f\.companyId, f\.keeper)) return #err(#notAMember { companyId = f\.companyId; subject = f\.keeper });|    if (false) return #err(#notAMember { companyId = f.companyId; subject = f.keeper });|' src/AptFold.mo

# a retired resource declared again stays retired
try appointments-redeclared-stays-retired Appointments \
  sed -i 's|          cancelNoticeDays = f\.cancelNoticeDays; keeper = f\.keeper; isActive = true; lastBlock = c\.block });|          cancelNoticeDays = f.cancelNoticeDays; keeper = f.keeper; isActive = x.isActive; lastBlock = c.block });|' src/AptFold.mo

# a retired resource still takes bookings
try appointments-retired-takes-bookings Appointments \
  sed -i 's|    if (not r\.isActive) return #err(#resourceRetired { resourceId = f\.resourceId });|    if (false) return #err(#resourceRetired { resourceId = f.resourceId });|' src/AptFold.mo

# A STRANGER BOOKS
# Not injected, and why: appointments-stranger-books - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# a booking on a day that has passed
try appointments-day-passed-booked Appointments \
  sed -i 's|    if (f\.day < c\.day) return #err(#dayPassed { day = f\.day; today = c\.day });|    if (false) return #err(#dayPassed { day = f.day; today = c.day });|' src/AptFold.mo

# a slot that ends before it begins accepted
try appointments-slot-backwards Appointments \
  sed -i 's|    if (f\.endMinute <= f\.startMinute) return #err(#hoursBackwards { startMinute = f\.startMinute; endMinute = f\.endMinute });|    if (false) return #err(#hoursBackwards { startMinute = f.startMinute; endMinute = f.endMinute });|' src/AptFold.mo

# a resource booked on a day it is closed
try appointments-closed-day-booked Appointments \
  sed -i 's|    if (not openOn(c, r, f\.day)) return #err(#resourceClosedThatDay { resourceId = f\.resourceId; day = f\.day });|    if (false) return #err(#resourceClosedThatDay { resourceId = f.resourceId; day = f.day });|' src/AptFold.mo

# THE CALENDAR'S HOLIDAY IGNORED by the resource
try appointments-holiday-ignored Appointments \
  sed -i 's|    HdFold\.inWorkingWeek(?r\.daysMask, day) and not c\.isHoliday(r\.companyId, day)|    HdFold.inWorkingWeek(?r.daysMask, day)|' src/AptFold.mo

# the resource's week ignored: open every day
try appointments-week-ignored Appointments \
  sed -i 's|    HdFold\.inWorkingWeek(?r\.daysMask, day) and not c\.isHoliday(r\.companyId, day)|    not c.isHoliday(r.companyId, day)|' src/AptFold.mo

# a slot outside the open hours accepted
try appointments-outside-hours-booked Appointments \
  sed -i 's|    if (f\.startMinute < r\.openMinute or f\.endMinute > r\.closeMinute) return #err(#outsideOpenHours { openMinute = r\.openMinute; closeMinute = r\.closeMinute });|    if (false) return #err(#outsideOpenHours { openMinute = r.openMinute; closeMinute = r.closeMinute });|' src/AptFold.mo

# A TAKEN SLOT BOOKED AGAIN
try appointments-taken-slot-booked Appointments \
  sed -i 's|    switch (holderOf(c\.apt, f\.resourceId, f\.day, f\.startMinute, f\.endMinute)) { case (?bookingId) return #err(#slotTaken { bookingId }); case null {} };|    ignore f.startMinute;|' src/AptFold.mo

# two slots meeting end to start treated as overlapping
try appointments-slots-meet-end-to-start Appointments \
  sed -i 's|  public func overlaps(aStart : Nat, aEnd : Nat, bStart : Nat, bEnd : Nat) : Bool { aStart < bEnd and bStart < aEnd };|  public func overlaps(aStart : Nat, aEnd : Nat, bStart : Nat, bEnd : Nat) : Bool { aStart <= bEnd and bStart <= aEnd };|' src/AptFold.mo

# a slot inside another not seen as overlapping
try appointments-overlap-misses-the-inside Appointments \
  sed -i 's|  public func overlaps(aStart : Nat, aEnd : Nat, bStart : Nat, bEnd : Nat) : Bool { aStart < bEnd and bStart < aEnd };|  public func overlaps(aStart : Nat, aEnd : Nat, bStart : Nat, bEnd : Nat) : Bool { aStart <= bStart and bStart < aEnd };|' src/AptFold.mo

# a cancelled booking keeps its slot
try appointments-cancelled-keeps-the-slot Appointments \
  sed -i 's|        keyOf = func(id : Nat, x : Booking) : ?Blob { if (x\.state == #confirmed) ?slotKey(x\.resourceId, x\.day, x\.startMinute, id) else null } },|        keyOf = func(id : Nat, x : Booking) : ?Blob { ?slotKey(x.resourceId, x.day, x.startMinute, id) } },|' src/AptRows.mo

# ANYBODY CANCELS a booking
try appointments-anybody-cancels Appointments \
  sed -i 's|      return #err(#notTheBooker { bookedBy = b\.bookedBy; keeper = r\.keeper });|      ignore r.keeper;|' src/AptFold.mo

# THE BOOKER CANCELS INSIDE THE NOTICE
try appointments-booker-cancels-inside-the-notice Appointments \
  sed -i 's|      if (inside) return #err(#insideCancellationWindow { day = b\.day; noticeDays = r\.cancelNoticeDays; today = c\.day });|      if (false) return #err(#insideCancellationWindow { day = b.day; noticeDays = r.cancelNoticeDays; today = c.day });|' src/AptFold.mo

# a late cancellation not marked
try appointments-late-not-marked Appointments \
  sed -i 's|    RowStore\.put<APR\.Booking>(c\.apt\.bookings, APR\.booking, bookingId, { b with state = #cancelled; cancelledBy = c\.caller; cancelledDay = c\.day; lateCancellation = inside; lastBlock = c\.block });|    RowStore.put<APR.Booking>(c.apt.bookings, APR.booking, bookingId, { b with state = #cancelled; cancelledBy = c.caller; cancelledDay = c.day; lateCancellation = false; lastBlock = c.block });|' src/AptFold.mo

# the notice counted one day too long
try appointments-window-edge-off-by-one Appointments \
  sed -i 's|    let inside = c\.day + r\.cancelNoticeDays > b\.day;|    let inside = c.day + r.cancelNoticeDays >= b.day;|' src/AptFold.mo

# a booking whose day has passed cancelled
try appointments-passed-day-cancelled Appointments \
  sed -i 's|    if (b\.day < c\.day) return #err(#dayPassed { day = b\.day; today = c\.day });|    if (false) return #err(#dayPassed { day = b.day; today = c.day });|' src/AptFold.mo

# a booking cancelled twice
try appointments-cancelled-twice Appointments \
  sed -i 's|    if (b\.state != #confirmed) return #err(#bookingCancelled { bookingId });|    if (false) return #err(#bookingCancelled { bookingId });|' src/AptFold.mo

# the booking table left out of the fingerprint
try appointments-fingerprint-misses-the-bookings Appointments \
  sed -i 's|    section<AptRows\.Booking>(s, f, "booking", s\.apt\.bookings, AptRows\.booking, func(r) { \[r\.title, r\.notes\] });||' src/State.mo

# ── subscriptions ────────────────────────────────────────────────────────────

# (a start day beyond its field is defended twice - the first period's day is checked too; a rise in a
# journal that is not there is refused by the ledger's own check inside the dry run as well - neither
# is injected.)
# A SUBSCRIPTION SOLD TO A SUPPLIER
try subscriptions-sold-to-a-supplier Subscriptions \
  sed -i 's|    if (not p\.isCustomer) return #err(#partnerNotACustomer { partnerId = f\.partnerId });|    if (false) return #err(#partnerNotACustomer { partnerId = f.partnerId });|' src/SubFold.mo

# a subscription for another company's customer
try subscriptions-partner-of-another-company Subscriptions \
  sed -i 's|    if (p\.companyId != f\.companyId) return #err(#wrongCompany { expected = f\.companyId; found = p\.companyId });|    if (false) return #err(#wrongCompany { expected = f.companyId; found = p.companyId });|' src/SubFold.mo

# a tax beyond sense accepted
try subscriptions-tax-unbounded Subscriptions \
  sed -i 's|    if (f\.taxRate > MAX_TAX_RATE) return #err(#rateBound { what = "a tax rate"; value = f\.taxRate; max = MAX_TAX_RATE });|    if (false) return #err(#rateBound { what = "a tax rate"; value = f.taxRate; max = MAX_TAX_RATE });|' src/SubFold.mo

# a subscription in no currency accepted
try subscriptions-no-currency Subscriptions \
  sed -i 's|    if (Text\.size(f\.currency) == 0) return #err(#codeDoesNotFit { code = f\.currency; max = W\.CURRENCY_CODE });|    if (false) return #err(#codeDoesNotFit { code = f.currency; max = W.CURRENCY_CODE });|' src/SubFold.mo

# THE PERIOD NOT CLAMPED TO THE MONTH: the 31st of February
try subscriptions-period-not-clamped Subscriptions \
  sed -i 's|    switch (CivilDate\.fromCivil(y2, m2, if (d > last) last else d)) {|    switch (CivilDate.fromCivil(y2, m2, d)) {|' src/SubFold.mo

# a quarter and a year counted as a month
try subscriptions-every-period-a-month Subscriptions \
  sed -i 's|    let idx = m - 1 + k \* E\.subscriptionPeriodMonths(period);|    let idx = m - 1 + k * 1;|' src/SubFold.mo

# the proration rounded down, not half to even
try subscriptions-proration-rounded-down Subscriptions \
  sed -i 's|    PE\.quantiseWithResidue(exact, { code = "M"; minorUnits = 0 })\.units|    ignore exact; (newTotal - oldTotal) * remainingDays / (1_000 * periodDays)|' src/SubFold.mo

# a fall prorated: the arithmetic runs below nothing
try subscriptions-fall-prorated Subscriptions \
  sed -i 's|    if (newTotal <= oldTotal or periodDays == 0) return 0;|    if (periodDays == 0) return 0;|' src/SubFold.mo

# a change before any invoice prorated
try subscriptions-prorated-outside-an-invoiced-period Subscriptions \
  sed -i 's|    if (x\.periodsInvoiced > 0 and c\.day < x\.nextInvoiceDay) {|    if (true) {|' src/SubFold.mo

# the days remaining counted one too many
try subscriptions-proration-counts-a-day-too-many Subscriptions \
  sed -i 's|      prorated := proration(x\.quantity, x\.priceUnit, f\.quantity, f\.priceUnit, x\.nextInvoiceDay - c\.day, x\.nextInvoiceDay - periodFrom);|      prorated := proration(x.quantity, x.priceUnit, f.quantity, f.priceUnit, x.nextInvoiceDay - c.day + 1, x.nextInvoiceDay - periodFrom);|' src/SubFold.mo

# a change that changes nothing accepted
try subscriptions-no-change-accepted Subscriptions \
  sed -i 's|    if (f\.quantity == x\.quantity and f\.priceUnit == x\.priceUnit) return #err(#noChange { subscriptionId = f\.subscriptionId });|    if (false) return #err(#noChange { subscriptionId = f.subscriptionId });|' src/SubFold.mo

# a closed subscription changed and closed again
try subscriptions-closed-still-acted-on Subscriptions \
  sed -i 's|    if (x\.state != #active) return #err(#subscriptionClosed { subscriptionId });|    if (false) return #err(#subscriptionClosed { subscriptionId });|' src/SubFold.mo

# a run through a day that has not come
try subscriptions-run-horizon-not-checked Subscriptions \
  sed -i 's|    if (throughDay > c\.day) return #err(#horizonNotReached { throughDay; day = c\.day });|    if (false) return #err(#horizonNotReached { throughDay; day = c.day });|' src/SubFold.mo

# a run in a journal that is not there
try subscriptions-run-journal-unchecked Subscriptions \
  sed -i 's|    if (not c\.journalOpen(companyId, journalId)) return #err(#noSuchJournal { journalId });|    if (false) return #err(#noSuchJournal { journalId });|' src/SubFold.mo

# two runs open at once
try subscriptions-two-runs-open Subscriptions \
  sed -i 's|    switch (openRunOf(c\.sub, companyId)) { case (?(runId, _)) return #err(#subscriptionRunOpen { companyId; runId }); case null {} };|    ignore companyId;|' src/SubFold.mo

# THE OPENER SLICES THEIR OWN RUN
try subscriptions-opener-slices Subscriptions \
  sed -i 's|    if (c\.caller == run\.openedBy) return #err(#selfInvoicing { opener = run\.openedBy });|    if (false) return #err(#selfInvoicing { opener = run.openedBy });|' src/SubFold.mo

# a slice of nothing, or beyond the page
try subscriptions-slice-unbounded Subscriptions \
  sed -i 's|    if (limit == 0 or limit > Page\.MAX_LIMIT) return #err(#sliceBound { limit; max = Page\.MAX_LIMIT });|    if (false) return #err(#sliceBound { limit; max = Page.MAX_LIMIT });|' src/SubFold.mo

# THE SALES NOT ASKED ABOUT WHOLE: a customer past their limit leaves orders behind
try subscriptions-sale-not-asked-whole Subscriptions \
  sed -i 's|        switch (c\.checkSale(o, run\.journalId)) { case (?r) return #err(#order r); case null {} };|        ignore o;|' src/SubFold.mo

# every period behind raised in one slice
try subscriptions-periods-per-slice-unbounded Subscriptions \
  sed -i 's|      while (periodStart(x\.startDay, x\.period, k) <= run\.throughDay and n < MAX_PERIODS_PER_SLICE) {|      while (periodStart(x.startDay, x.period, k) <= run.throughDay and true) {|' src/SubFold.mo

# the run closes with periods still due
try subscriptions-run-closes-early Subscriptions \
  sed -i 's|    let lastPage = page\.size() < limit and caughtUp;|    let lastPage = page.size() < limit;|' src/SubFold.mo

# the invoice dated the period's first day, not the run's
try subscriptions-invoice-dated-the-period Subscriptions \
  sed -i 's|        let o = saleOf(x, companyId, c\.day, currency, "period " # Nat\.toText(k + 1), x\.quantity, x\.priceUnit, "subscription " # Nat\.toText(sid) # " period " # Nat\.toText(k + 1));|        let o = saleOf(x, companyId, from, currency, "period " # Nat.toText(k + 1), x.quantity, x.priceUnit, "subscription " # Nat.toText(sid) # " period " # Nat.toText(k + 1));|' src/SubFold.mo

# an invoiced subscription stays due
try subscriptions-next-day-not-advanced Subscriptions \
  sed -i 's|      RowStore\.put<SBR\.Subscription>(c\.sub\.subscriptions, SBR\.subscription, sid, { x with periodsInvoiced = ordinal; nextInvoiceDay = to; lastBlock = c\.block });|      RowStore.put<SBR.Subscription>(c.sub.subscriptions, SBR.subscription, sid, { x with periodsInvoiced = ordinal; nextInvoiceDay = x.nextInvoiceDay; lastBlock = c.block });|' src/SubFold.mo

# a closed subscription still walked by the run
try subscriptions-closed-still-due Subscriptions \
  sed -i 's|        keyOf = func(id : Nat, x : Subscription) : ?Blob { if (x\.state == #active) ?dueKey(x\.companyId, x\.nextInvoiceDay, id) else null } },|        keyOf = func(id : Nat, x : Subscription) : ?Blob { ?dueKey(x.companyId, x.nextInvoiceDay, id) } },|' src/SubRows.mo

# the subscription invoice table left out of the fingerprint
try subscriptions-fingerprint-misses-the-invoices Subscriptions \
  sed -i 's|    section<SubRows\.SubscriptionInvoice>(s, f, "subscription_invoice", s\.sub\.invoices, SubRows\.subscriptionInvoice, func(_r) { \[\] });||' src/State.mo

# ── rental ───────────────────────────────────────────────────────────────────

# a second item on the same code: a new row instead of the one changed
try rental-item-code-not-unique Rental \
  sed -i 's|    switch (itemByCode(c\.rnt, f\.companyId, code)) {|    switch (null : ?(Nat, RNR.RentalItem)) {|' src/RntFold.mo

# A LOT OF ANOTHER CATEGORY accepted as the unit
try rental-lot-of-another-category Rental \
  sed -i 's|      if (lot\.categoryId != f\.categoryId) return #err(#lotNotOfCategory { lotId = f\.lotId; categoryId = f\.categoryId });|      if (false) return #err(#lotNotOfCategory { lotId = f.lotId; categoryId = f.categoryId });|' src/RntFold.mo

# a customer location as the yard
try rental-yard-not-internal Rental \
  sed -i 's|    if (yard\.usage != #internal) return #err(#yardNotInternal { locationId = f\.yardLocationId });|    if (false) return #err(#yardNotInternal { locationId = f.yardLocationId });|' src/RntFold.mo

# an item for hire at no rate
try rental-item-at-no-rate Rental \
  sed -i 's|    if (f\.dailyRate == 0) return #err(#rateRequired);|    if (false) return #err(#rateRequired);|' src/RntFold.mo

# a retired item declared again stays retired
try rental-redeclared-stays-retired Rental \
  sed -i 's|          currency; taxRate = f\.taxRate; isActive = true; declaredBy = c\.caller; lastBlock = c\.block });|          currency; taxRate = f.taxRate; isActive = x.isActive; declaredBy = c.caller; lastBlock = c.block });|' src/RntFold.mo

# an item retired with rentals reserved or out
try rental-retired-with-live-rentals Rental \
  sed -i 's|    if (x\.liveRentals > 0) return #err(#itemHasLiveRentals { itemId; live = x\.liveRentals });|    if (false) return #err(#itemHasLiveRentals { itemId; live = x.liveRentals });|' src/RntFold.mo

# a retired item still takes rentals
try rental-retired-item-reserved Rental \
  sed -i 's|    if (not x\.isActive) return #err(#itemRetired { itemId });|    if (false) return #err(#itemRetired { itemId });|' src/RntFold.mo

# A RESERVATION FOR A SUPPLIER
try rental-to-a-supplier Rental \
  sed -i 's|    if (not p\.isCustomer) return #err(#partnerNotACustomer { partnerId = f\.partnerId });|    if (false) return #err(#partnerNotACustomer { partnerId = f.partnerId });|' src/RntFold.mo

# a rental beyond the year
try rental-beyond-the-year Rental \
  sed -i 's|    if (agreedDays(f\.fromDay, f\.toDay) > MAX_RENTAL_DAYS) return #err(#daysBound { days = agreedDays(f\.fromDay, f\.toDay); max = MAX_RENTAL_DAYS });|    if (false) return #err(#daysBound { days = agreedDays(f.fromDay, f.toDay); max = MAX_RENTAL_DAYS });|' src/RntFold.mo

# a rental from a day that has passed
try rental-from-a-passed-day Rental \
  sed -i 's|    if (f\.fromDay < c\.day) return #err(#dayPassed { day = f\.fromDay; today = c\.day });|    if (false) return #err(#dayPassed { day = f.fromDay; today = c.day });|' src/RntFold.mo

# TAKEN DAYS RESERVED AGAIN
try rental-taken-days-reserved Rental \
  sed -i 's|    switch (holderOf(c\.rnt, f\.itemId, f\.fromDay, f\.toDay)) { case (?rentalId) return #err(#itemTaken { rentalId }); case null {} };|    ignore f.itemId;|' src/RntFold.mo

# a rental ending on a day and one beginning the next treated as overlapping
try rental-adjacent-days-meet Rental \
  sed -i 's|  public func overlaps(aFrom : Nat, aTo : Nat, bFrom : Nat, bTo : Nat) : Bool { aFrom <= bTo and bFrom <= aTo };|  public func overlaps(aFrom : Nat, aTo : Nat, bFrom : Nat, bTo : Nat) : Bool { aFrom <= bTo + 1 and bFrom <= aTo + 1 };|' src/RntFold.mo

# a day inside another rental not seen as overlapping
try rental-overlap-misses-the-inside Rental \
  sed -i 's|  public func overlaps(aFrom : Nat, aTo : Nat, bFrom : Nat, bTo : Nat) : Bool { aFrom <= bTo and bFrom <= aTo };|  public func overlaps(aFrom : Nat, aTo : Nat, bFrom : Nat, bTo : Nat) : Bool { aFrom <= bFrom and bFrom <= aTo };|' src/RntFold.mo

# a cancelled rental keeps its days
try rental-cancelled-keeps-its-days Rental \
  sed -i 's|        keyOf = func(id : Nat, x : Rental) : ?Blob { if (x\.state == #reserved or x\.state == #out) ?itemDayKey(x\.itemId, x\.fromDay, id) else null } },|        keyOf = func(id : Nat, x : Rental) : ?Blob { ?itemDayKey(x.itemId, x.fromDay, id) } },|' src/RntRows.mo

# the item's live count not kept
try rental-live-count-not-kept Rental \
  sed -i 's|    RowStore\.put<RNR\.RentalItem>(c\.rnt\.items, RNR\.rentalItem, f\.itemId, { x with liveRentals = x\.liveRentals + 1; lastBlock = c\.block });|    RowStore.put<RNR.RentalItem>(c.rnt.items, RNR.rentalItem, f.itemId, { x with liveRentals = x.liveRentals; lastBlock = c.block });|' src/RntFold.mo

# THE RESERVER HANDS THE THING OVER
try rental-reserver-hands-over Rental \
  sed -i 's|    if (c\.caller == r\.reservedBy) return #err(#selfHandover { reserver = r\.reservedBy });|    if (false) return #err(#selfHandover { reserver = r.reservedBy });|' src/RntFold.mo

# THE RESERVER TAKES THE THING BACK
try rental-reserver-takes-back Rental \
  sed -i 's|    if (c\.caller == r\.reservedBy) return #err(#selfHandover { reserver = r\.reservedBy });   // the return as the handover|    if (false) return #err(#selfHandover { reserver = r.reservedBy });|' src/RntFold.mo

# the unit handed into a customer location: sold, not hired
try rental-out-to-a-customer-location Rental \
  sed -i 's|    if (out\.usage != #transit) return #err(#outLocationNotTransit { locationId = f\.outLocationId });|    if (false) return #err(#outLocationNotTransit { locationId = f.outLocationId });|' src/RntFold.mo

# the handover's picking not asked about whole: a refusal leaves it behind
try rental-handover-not-asked-whole Rental \
  sed -i 's|    switch (c\.checkPicking(facts, f\.journalId)) { case (?e) return #err(#stock e); case null {} };|    ignore facts;|' src/RntFold.mo

# (the return's picking not asked about whole is defended twice - the stock fold refuses a picking it cannot
# make at its creation, and the journal the picking posts in is the journal the charge is checked in - so
# removing the check alone leaves the battery green; it is not injected.)

# THE CHARGE NOT ASKED ABOUT WHOLE: a customer past their limit gets the thing back and an order left behind
try rental-charge-not-asked-whole Rental \
  sed -i 's|    switch (c\.checkSale(order, f\.journalId)) { case (?e) return #err(#order e); case null {} };|    ignore order;|' src/RntFold.mo

# the days late never counted
try rental-late-days-not-counted Rental \
  sed -i 's|    let late = lateDays(r\.toDay, c\.day);|    let late = 0;|' src/RntFold.mo

# the days late counted one too many
try rental-late-days-off-by-one Rental \
  sed -i 's|  public func lateDays(toDay : Nat, returnedDay : Nat) : Nat { if (returnedDay > toDay) returnedDay - toDay else 0 };|  public func lateDays(toDay : Nat, returnedDay : Nat) : Nat { if (returnedDay > toDay) returnedDay - toDay + 1 else 0 };|' src/RntFold.mo

# the agreed days counted without the last
try rental-agreed-days-exclusive Rental \
  sed -i 's|  public func agreedDays(fromDay : Nat, toDay : Nat) : Nat { toDay - fromDay + 1 };|  public func agreedDays(fromDay : Nat, toDay : Nat) : Nat { toDay - fromDay };|' src/RntFold.mo

# the late days not charged
try rental-late-not-charged Rental \
  sed -i 's|    if (late > 0 and x\.lateRatePerDay > 0) {|    if (false) {|' src/RntFold.mo

# a rental acted on whatever its state
try rental-state-not-checked Rental \
  sed -i 's|    if (r\.state != wanted) return #err(#rentalNotInState { rentalId; state = stateText(r\.state); wanted = stateText(wanted) });|    if (false) return #err(#rentalNotInState { rentalId; state = stateText(r.state); wanted = stateText(wanted) });|' src/RntFold.mo

# the rental table left out of the fingerprint
try rental-fingerprint-misses-the-rentals Rental \
  sed -i 's|    section<RntRows\.Rental>(s, f, "rental", s\.rnt\.rentals, RntRows\.rental, func(_r) { \[\] });||' src/State.mo

# ── point of sale ────────────────────────────────────────────────────────────

# Not injected, and why: the receipts each asked about before any is posted (`checkPost`) - no act
# the battery can take makes a LATER receipt of one slice refuse while an earlier one posts, so the
# dry run cannot be shown to matter; the Z move asked about before it is posted (`postGenerated`
# asks `checkGenerated` again itself); a walk-in customer with no receivable (`createPartner` refuses
# a customer without one first); the cashier posting a session with a receipt or a move in it (the
# ledger refuses the maker as checker on every one - the fold's own rule is caught on the empty session).

# a second shop on the same code: a new row instead of the one changed
try pos-shop-code-not-unique Pos \
  sed -i 's|    switch (shopByCode(c\.pos, f\.companyId, code)) {|    switch (null : ?(Nat, PR.Shop)) {|' src/PosFold.mo

# A SHELF THAT IS NOT INTERNAL accepted
try pos-shelf-not-internal Pos \
  sed -i 's|    if (shelf\.usage != #internal) return #err(#shopLocationNotInternal { locationId = f\.stockLocationId });|    if (false) return #err(#shopLocationNotInternal { locationId = f.stockLocationId });|' src/PosFold.mo

# goods sold into a location that is not a customer's
try pos-goods-sold-to-a-shelf Pos \
  sed -i 's|    if (cust\.usage != #customer) return #err(#customerLocationNotCustomer { locationId = f\.customerLocationId });|    if (false) return #err(#customerLocationNotCustomer { locationId = f.customerLocationId });|' src/PosFold.mo

# a supplier as the walk-in customer
try pos-supplier-as-the-public Pos \
  sed -i 's|    if (not p\.isCustomer) return #err(#partnerNotACustomer { partnerId = f\.partnerId });|    if (false) return #err(#partnerNotACustomer { partnerId = f.partnerId });|' src/PosFold.mo

# A CUSTOMER ON CREDIT TERMS as the public: a till sells for cash
try pos-public-on-credit Pos \
  sed -i 's|    if (c\.hasCreditTerms(f\.companyId, f\.partnerId)) return #err(#partnerOnCredit { partnerId = f\.partnerId });|    if (false) return #err(#partnerOnCredit { partnerId = f.partnerId });|' src/PosFold.mo

# the cash, card and difference accounts of any type
try pos-account-of-any-type Pos \
  sed -i 's|    if (a\.accountType != t) return ?(#accountNotOfType { accountId; wanted });|    if (false) return ?(#accountNotOfType { accountId; wanted });|' src/PosFold.mo

# the cash and the card on one account
try pos-cash-and-card-one-account Pos \
  sed -i 's|    if (f\.cashAccountId == f\.cardAccountId) return #err(#accountsNotDistinct { accountId = f\.cashAccountId });|    if (false) return #err(#accountsNotDistinct { accountId = f.cashAccountId });|' src/PosFold.mo

# a retired shop opening a till, listing a price
try pos-retired-shop-stands Pos \
  sed -i 's|    if (not x\.isActive) return #err(#shopRetired { shopId });|    if (false) return #err(#shopRetired { shopId });|' src/PosFold.mo

# a shop under the wrong company
try pos-wrong-company-shop Pos \
  sed -i 's|    if (x\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x\.companyId });|    if (false) return #err(#wrongCompany { expected = companyId; found = x.companyId });|' src/PosFold.mo

# ONE LIVE SESSION PER SHOP not kept, and a shop with a session live retired (one line in two functions, both removed)
try pos-live-session-ignored Pos \
  sed -i 's|    switch (liveSessionOf(c\.pos, shopId)) { case (?(sessionId, _)) return #err(#shopHasLiveSession { shopId; sessionId }); case null {} };|    ignore shopId;|' src/PosFold.mo

# a price of nothing
try pos-price-of-nothing Pos \
  sed -i 's|    if (f\.priceUnit == 0) return #err(#priceRequired);|    if (false) return #err(#priceRequired);|' src/PosFold.mo

# a tax beyond sense
try pos-tax-beyond-sense Pos \
  sed -i 's|    if (f\.taxRate > MAX_TAX_RATE) return #err(#priceBound { what = "a tax rate"; value = f\.taxRate; max = MAX_TAX_RATE });|    if (false) return #err(#priceBound { what = "a tax rate"; value = f.taxRate; max = MAX_TAX_RATE });|' src/PosFold.mo

# a withdrawn article set again stays withdrawn
try pos-withdrawn-price-stays-withdrawn Pos \
  sed -i 's|        RowStore\.put<PR\.Price>(c\.pos\.prices, PR\.price, id, { x with priceUnit = f\.priceUnit; taxRate = f\.taxRate; movesStock = f\.movesStock; isActive = true; lastBlock = c\.block });|        RowStore.put<PR.Price>(c.pos.prices, PR.price, id, { x with priceUnit = f.priceUnit; taxRate = f.taxRate; movesStock = f.movesStock; isActive = x.isActive; lastBlock = c.block });|' src/PosFold.mo

# a stranger opening a till, or posting a session (one line in two functions, both removed)
# Not injected, and why: pos-non-member-acts - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# SOMEBODY OTHER THAN THE CASHIER RINGING UP in the session
try pos-anyone-rings-up Pos \
  sed -i 's|^    if (c\.caller != s\.cashier) return #err(#notTheCashier { cashier = s\.cashier });$|    if (false) return #err(#notTheCashier { cashier = s.cashier });|' src/PosFold.mo

# somebody other than the cashier counting the drawer
try pos-anyone-counts Pos \
  sed -i 's|    if (c\.caller != s\.cashier) return #err(#notTheCashier { cashier = s\.cashier });   // the count as the sale|    if (false) return #err(#notTheCashier { cashier = s.cashier });|' src/PosFold.mo

# Not injected either: a sale of no lines and a line of nothing - the order fold refuses both inside
# the dry run, so removing the till's own check changes no verdict. The tender and the quantity bounds,
# which are the till's alone, stand in for them.
# cash tendered beyond its field
try pos-cash-beyond-its-field Pos \
  sed -i 's|    if (f\.cashTendered > MAX_MONEY) return #err(#moneyBound { what = "cash tendered"; value = f\.cashTendered; max = MAX_MONEY });|    if (false) return #err(#moneyBound { what = "cash tendered"; value = f.cashTendered; max = MAX_MONEY });|' src/PosFold.mo

# a line beyond the bound
try pos-quantity-beyond-the-bound Pos \
  sed -i 's|      if (l\.quantity > MAX_LINE_QUANTITY) return #err(#quantityBound { ordinal; quantity = l\.quantity; max = MAX_LINE_QUANTITY });|      if (false) return #err(#quantityBound { ordinal; quantity = l.quantity; max = MAX_LINE_QUANTITY });|' src/PosFold.mo

# A WITHDRAWN ARTICLE sold
try pos-withdrawn-article-sold Pos \
  sed -i 's|      if (not p\.isActive) return #err(#notForSale { categoryId = l\.categoryId });|      if (false) return #err(#notForSale { categoryId = l.categoryId });|' src/PosFold.mo

# the tax the list carries not charged in the sale's total
try pos-tax-not-charged Pos \
  sed -i 's|      let a = OFold\.lineAmounts(l\.quantity, p\.priceUnit, p\.taxRate, cur);|      let a = OFold.lineAmounts(l.quantity, p.priceUnit, 0, cur);|' src/PosFold.mo

# a card payment over the total
try pos-card-over-total Pos \
  sed -i 's|    if (f\.cardTendered > total) return #err(#cardOverTotal { total; card = f\.cardTendered });|    if (false) return #err(#cardOverTotal { total; card = f.cardTendered });|' src/PosFold.mo

# tender short of the total
try pos-tender-short Pos \
  sed -i 's|    if (f\.cashTendered + f\.cardTendered < total) return #err(#tenderShort { total; tendered = f\.cashTendered + f\.cardTendered });|    if (false) return #err(#tenderShort { total; tendered = f.cashTendered + f.cardTendered });|' src/PosFold.mo

# THE SHELF NOT READ: the eleventh of ten sold
try pos-shelf-not-read Pos \
  sed -i 's|      if (have < sold + quantity) return #err(#notOnShelf { categoryId; have = have - sold; wanted = quantity });|      if (false) return #err(#notOnShelf { categoryId; have = have - sold; wanted = quantity });|' src/PosFold.mo

# the shelf read without what the session already sold
try pos-shelf-forgets-the-session Pos \
  sed -i 's|      let sold = switch (kindOf(c\.pos, f\.sessionId, categoryId)) { case (?(_, k)) k\.quantity; case null 0 };|      let sold = 0;|' src/PosFold.mo

# a service taken off the shelf
try pos-service-off-the-shelf Pos \
  sed -i 's|      if (p\.movesStock) {|      if (true) {|' src/PosFold.mo

# THE SALE NOT ASKED ABOUT WHOLE: an order left behind by a refused invoice
try pos-sale-not-asked-whole Pos \
  sed -i 's|    switch (c\.checkSale(order, shop\.journalId)) { case (?e) return #err(#order e); case null {} };|    ignore order;|' src/PosFold.mo

# the cash takings not summed
try pos-takings-not-summed Pos \
  sed -i 's|      s with cashTakings = s\.cashTakings + cashPaid; cardTakings = s\.cardTakings + f\.cardTendered; ordersCount = s\.ordersCount + 1;|      s with cashTakings = s.cashTakings; cardTakings = s.cardTakings + f.cardTendered; ordersCount = s.ordersCount + 1;|' src/PosFold.mo

# the change not given
try pos-change-not-given Pos \
  sed -i 's|      changeGiven = f\.cashTendered + f\.cardTendered - total; day = c\.day; isPosted = false; lastBlock = c\.block });|      changeGiven = 0; day = c.day; isPosted = false; lastBlock = c.block });|' src/PosFold.mo

# a session's state not checked: a sale after the count, a count twice, a posting of an open session
try pos-state-not-checked Pos \
  sed -i 's|    if (s\.state != wanted) return #err(#sessionNotInState { sessionId; state = stateText(s\.state); wanted = stateText(wanted) });|    if (false) return #err(#sessionNotInState { sessionId; state = stateText(s.state); wanted = stateText(wanted) });|' src/PosFold.mo

# THE SHORTFALL AND THE EXCESS not computed at the count
try pos-shortfall-not-computed Pos \
  sed -i 's|      s with state = #counted; closedDay = c\.day; countedCash; shortBy = shortBy(expected, countedCash); overBy = overBy(expected, countedCash); lastBlock = c\.block });|      s with state = #counted; closedDay = c.day; countedCash; shortBy = 0; overBy = 0; lastBlock = c.block });|' src/PosFold.mo

# the drawer expected to hold the takings without the float
try pos-expected-cash-without-the-float Pos \
  sed -i 's|  public func expectedCash(openingFloat : Nat, cashTakings : Nat) : Nat { openingFloat + cashTakings };|  public func expectedCash(openingFloat : Nat, cashTakings : Nat) : Nat { ignore openingFloat; cashTakings };|' src/PosFold.mo

# THE CASHIER POSTING THEIR OWN SESSION (the fold's rule; the ledger's catches it only where a receipt or a move is posted)
try pos-cashier-posts-own-session Pos \
  sed -i 's|    if (c\.caller == s\.cashier) return #err(#cashierPosting { cashier = s\.cashier });|    if (false) return #err(#cashierPosting { cashier = s.cashier });|' src/PosFold.mo

# a slice of nothing, or beyond a picking
try pos-slice-unbounded Pos \
  sed -i 's|    if (limit == 0 or limit > MAX_SLICE) return #err(#sliceBound { limit; max = MAX_SLICE });|    if (false) return #err(#sliceBound { limit; max = MAX_SLICE });|' src/PosFold.mo

# a posted receipt not marked, so the next slice posts it again
try pos-receipts-not-marked-posted Pos \
  sed -i 's|        RowStore\.put<PR\.Sale>(c\.pos\.sales, PR\.sale, id, { x with isPosted = true; lastBlock = c\.block });|        RowStore.put<PR.Sale>(c.pos.sales, PR.sale, id, { x with lastBlock = c.block });|' src/PosFold.mo

# THE RECEIPTS NEVER POSTED: the Z report skips to the goods
try pos-receipts-never-posted Pos \
  sed -i 's|    if (pending\.size() > 0) {|    if (false) {|' src/PosFold.mo

# THE GOODS NOT ASKED ABOUT WHOLE: a picking left behind by a quality hold
try pos-goods-not-asked-whole Pos \
  sed -i 's|      switch (c\.checkPicking(facts, shop\.journalId)) { case (?e) return #err(#stock e); case null {} };|      ignore facts;|' src/PosFold.mo

# a moved kind not marked, so the next slice moves it again off an empty shelf
try pos-kinds-not-marked-moved Pos \
  sed -i 's|      for ((kid, k) in kinds\.vals()) RowStore\.put<PR\.Kind>(c\.pos\.kinds, PR\.kind, kid, { k with pickingId = ids\[0\]; lastBlock = c\.block });|      for ((kid, k) in kinds.vals()) RowStore.put<PR.Kind>(c.pos.kinds, PR.kind, kid, { k with lastBlock = c.block });|' src/PosFold.mo

# THE Z REPORT'S CASH LINE as the takings rather than what the count says was added to the drawer
try pos-z-cash-is-the-takings Pos \
  sed -i 's|      List\.add(out, { accountId = shop\.cashAccountId; partnerId = 0; name = "cash taken"; debit = s\.countedCash - s\.openingFloat; credit = 0; amountCurrency = 0; taxId = 0 });|      List.add(out, { accountId = shop.cashAccountId; partnerId = 0; name = "cash taken"; debit = s.cashTakings; credit = 0; amountCurrency = 0; taxId = 0 });|' src/PosFold.mo

# the shortfall credited instead of debited
try pos-z-shortfall-credited Pos \
  sed -i 's|      List\.add(out, { accountId = shop\.differenceAccountId; partnerId = 0; name = "cash short"; debit = s\.shortBy; credit = 0; amountCurrency = 0; taxId = 0 });|      List.add(out, { accountId = shop.differenceAccountId; partnerId = 0; name = "cash short"; debit = 0; credit = s.shortBy; amountCurrency = 0; taxId = 0 });|' src/PosFold.mo

# THE Z MOVE PROPOSED IN THE POSTER'S OWN NAME
try pos-z-proposed-by-the-poster Pos \
  sed -i 's|      zMoveId := switch (c\.postGenerated(s\.cashier, facts)) { case (#err e) return #err(#ledger e); case (#ok ids) ids\[0\] };|      zMoveId := switch (c.postGenerated(c.caller, facts)) { case (#err e) return #err(#ledger e); case (#ok ids) ids[0] };|' src/PosFold.mo

# ── the restaurant ───────────────────────────────────────────────────────────

# Not injected, and why: a bill with nothing on it settled (the till's own pricing refuses a sale of no
# lines inside the dry run, so the tab's check changes no verdict); the waiter settling (the till fold
# refuses the sale to anybody but the cashier, which is its own injection above).

# a second table on the same code: a new row instead of the one changed
try rst-table-code-not-unique Restaurant \
  sed -i 's|    switch (tableByCode(c\.rst, f\.companyId, code)) {|    switch (null : ?(Nat, RR.Table)) {|' src/RstFold.mo

# a table of no seats
try rst-table-of-no-seats Restaurant \
  sed -i 's|    if (f\.seats == 0 or f\.seats > MAX_SEATS) return #err(#seatsBound { seats = f\.seats; max = MAX_SEATS });|    if (false) return #err(#seatsBound { seats = f.seats; max = MAX_SEATS });|' src/RstFold.mo

# a table with a tab open retired
try rst-table-with-tab-retired Restaurant \
  sed -i 's|    switch (openTabOf(c\.rst, tableId)) { case (?(tabId, _)) return #err(#tableTaken { tableId; tabId }); case null {} };|    ignore tableId;|' src/RstFold.mo

# A SECOND TAB AT A TABLE WITH ONE OPEN
try rst-second-tab-at-a-table Restaurant \
  sed -i 's|    switch (openTabOf(c\.rst, f\.tableId)) { case (?(tabId, _)) return #err(#tableTaken { tableId = f\.tableId; tabId }); case null {} };|    ignore f.tableId;|' src/RstFold.mo

# a tab in a session already counted
try rst-tab-in-a-counted-session Restaurant \
  sed -i 's|    if (s\.state != #open) return #err(#sessionNotOpen { sessionId = f\.sessionId; state = PFold\.stateText(s\.state) });|    if (false) return #err(#sessionNotOpen { sessionId = f.sessionId; state = PFold.stateText(s.state) });|' src/RstFold.mo

# A TABLE OF ANOTHER SHOP in this shop's session
try rst-table-of-another-shop Restaurant \
  sed -i 's|    if (t\.shopId != s\.shopId) return #err(#tableNotOfShop { tableId = f\.tableId; shopId = s\.shopId });|    if (false) return #err(#tableNotOfShop { tableId = f.tableId; shopId = s.shopId });|' src/RstFold.mo

# more covers than the table seats
try rst-covers-beyond-seats Restaurant \
  sed -i 's|    if (f\.covers == 0 or f\.covers > t\.seats) return #err(#coversBound { covers = f\.covers; seats = t\.seats });|    if (false) return #err(#coversBound { covers = f.covers; seats = t.seats });|' src/RstFold.mo

# a stranger opening a tab or ordering (one line in two functions, both removed)
# Not injected, and why: rst-stranger-opens-or-orders - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# a stranger voiding, sending or cancelling (one line in three functions, all removed)
# Not injected, and why: rst-stranger-voids-sends-cancels - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# course nought, or a thirteenth
try rst-course-bound Restaurant \
  sed -i 's|    if (f\.course == 0 or f\.course > MAX_COURSES) return #err(#courseBound { course = f\.course; max = MAX_COURSES });|    if (false) return #err(#courseBound { course = f.course; max = MAX_COURSES });|' src/RstFold.mo

# A CATEGORY OFF THE LIST ordered
try rst-off-the-menu Restaurant \
  sed -i 's|        case null return #err(#notOnTheMenu { categoryId = l\.categoryId });|        case null {};|' src/RstFold.mo

# A SENT COURSE TAKING MORE
try rst-sent-course-takes-more Restaurant \
  sed -i 's|    switch (existing) { case (?(_, k)) { if (k\.state == #sent) return #err(#courseSent { course = f\.course }) }; case null {} };|    switch (existing) { case (?(_, _)) {}; case null {} };|' src/RstFold.mo

# THE WAITER VOIDING THEIR OWN LINE once the kitchen has it
try rst-own-cooked-line-voided Restaurant \
  sed -i 's|    if (k\.state == #sent and c\.caller == l\.orderedBy) return #err(#ownLineOnSentCourse { orderedBy = l\.orderedBy });|    if (false) return #err(#ownLineOnSentCourse { orderedBy = l.orderedBy });|' src/RstFold.mo

# a line voided twice
try rst-void-twice Restaurant \
  sed -i 's|    if (l\.isVoided) return #err(#lineVoided { lineId });|    if (false) return #err(#lineVoided { lineId });|' src/RstFold.mo

# a course sent twice
try rst-send-twice Restaurant \
  sed -i 's|    if (k\.state == #sent) return #err(#courseSent { course });|    if (false) return #err(#courseSent { course });|' src/RstFold.mo

# an empty course sent
try rst-empty-course-sent Restaurant \
  sed -i 's|    if (k\.lines == 0) return #err(#courseEmpty { course });|    if (false) return #err(#courseEmpty { course });|' src/RstFold.mo

# A TAB WITH COOKED LINES STANDING cancelled
try rst-cooked-tab-cancelled Restaurant \
  sed -i 's|    for ((_, k) in coursesOf(c\.rst, tabId)\.vals()) { if (k\.state == #sent and k\.lines > 0) return #err(#courseSent { course = k\.ordinal }) };|    ignore tabId;|' src/RstFold.mo

# A BILL SETTLED WITH A COURSE UNSENT
try rst-unsent-course-settled Restaurant \
  sed -i 's|    for ((_, k) in coursesOf(c\.rst, f\.tabId)\.vals()) { if (k\.state != #sent and k\.lines > 0) return #err(#courseNotSent { course = k\.ordinal }) };|    ignore f.tabId;|' src/RstFold.mo

# fifty-one shares
try rst-shares-unbounded Restaurant \
  sed -i 's|    if (n == 0 or n > MAX_SHARES) return #err(#sharesBound { shares = n; max = MAX_SHARES });|    if (false) return #err(#sharesBound { shares = n; max = MAX_SHARES });|' src/RstFold.mo

# weights that do not match the shares
try rst-weights-disagree Restaurant \
  sed -i 's|        if (f\.weights\.size() != n) return #err(#weightsDisagree { weights = f\.weights\.size(); shares = n });|        if (false) return #err(#weightsDisagree { weights = f.weights.size(); shares = n });|' src/RstFold.mo

# a share of no weight
try rst-weight-of-nothing Restaurant \
  sed -i 's|        for (w in f\.weights\.vals()) { if (w == 0 or w > MAX_WEIGHT) return #err(#weightBound { ordinal = i + 1; weight = w; max = MAX_WEIGHT }); i += 1 };|        for (w in f.weights.vals()) { ignore w; i += 1 };|' src/RstFold.mo

# A SHARE'S TENDER SHORT of it
try rst-share-tender-short Restaurant \
  sed -i 's|      if (t\.cash + t\.card < shares\[i\]) return #err(#shareTenderShort { ordinal = i + 1; share = shares\[i\]; tendered = t\.cash + t\.card });|      if (false) return #err(#shareTenderShort { ordinal = i + 1; share = shares[i]; tendered = t.cash + t.card });|' src/RstFold.mo

# A SHARE'S CARD OVER IT
try rst-card-over-share Restaurant \
  sed -i 's|      if (t\.card > shares\[i\]) return #err(#cardOverShare { ordinal = i + 1; share = shares\[i\]; card = t\.card });|      if (false) return #err(#cardOverShare { ordinal = i + 1; share = shares[i]; card = t.card });|' src/RstFold.mo

# THE SPLIT'S WHOLE PARTS ONLY: the minor units left over given to nobody
try rst-split-whole-parts-only Restaurant \
  sed -i 's|    var leftover : Nat = total - given;|    var leftover : Nat = 0;|' src/RstFold.mo

# the minor unit left over to the LATER share where remainders tie
try rst-split-leftover-to-the-later-share Restaurant \
  sed -i 's|        if (extra\[i\] == 0 and (not found or rem\[i\] > rem\[pick\])) { pick := i; found := true };|        if (extra[i] == 0 and (not found or rem[i] >= rem[pick])) { pick := i; found := true };|' src/RstFold.mo

# VOIDED LINES BILLED
try rst-voided-lines-billed Restaurant \
  sed -i 's|      if (not l\.isVoided) {|      if (true) {|' src/RstFold.mo

# the bill's lines of one kind not added up
try rst-bill-not-aggregated Restaurant \
  sed -i 's|          if (x\.categoryId == l\.categoryId) { List\.put(out, i, { categoryId = x\.categoryId; quantity = x\.quantity + l\.quantity }); seen := true };|          if (x.categoryId == l.categoryId) { seen := true };|' src/RstFold.mo

# a settled tab left open
try rst-settled-tab-left-open Restaurant \
  sed -i 's|    RowStore\.put<RR\.Tab>(c\.rst\.tabs, RR\.tab, f\.tabId, { x with state = #paid; saleId = rung\[0\]; orderId = rung\[1\]; rule = f\.rule; ways = n; amountTotal = total; lastBlock = c\.block });|    RowStore.put<RR.Tab>(c.rst.tabs, RR.tab, f.tabId, { x with saleId = rung[0]; orderId = rung[1]; rule = f.rule; ways = n; amountTotal = total; lastBlock = c.block });|' src/RstFold.mo

# the lines standing not counted
try rst-live-lines-not-counted Restaurant \
  sed -i 's|    RowStore\.put<RR\.Tab>(c\.rst\.tabs, RR\.tab, f\.tabId, { x with courses; liveLines = x\.liveLines + f\.lines\.size(); lastBlock = c\.block });|    RowStore.put<RR.Tab>(c.rst.tabs, RR.tab, f.tabId, { x with courses; liveLines = x.liveLines; lastBlock = c.block });|' src/RstFold.mo

# Not injected either: a tab or a shop under the wrong company - the caller is then no member of that
# company, and the till's pricing refuses the other company's categories, so the fold's own check changes
# no verdict. The retired table stands in for it.
# A RETIRED TABLE taking a tab
try rst-retired-table-takes-a-tab Restaurant \
  sed -i 's|    if (not t\.isActive) return #err(#tableRetired { tableId });|    if (false) return #err(#tableRetired { tableId });|' src/RstFold.mo

# ── the web shop ─────────────────────────────────────────────────────────────

# Not injected, and why: the stock fold reading what web orders hold is the stock fold's own line
# (`reservedElsewhere`), and the till's reading is the state's wiring; both are caught here only through
# the web fold's own `reservedAt`, which `availability-ignores-holds` removes from the checkout.

# a storefront over a retired shop
try web-storefront-over-a-retired-shop Webshop \
  sed -i 's|    if (not shop\.isActive) return #err(#shopRetired { shopId = f\.shopId });|    if (false) return #err(#shopRetired { shopId = f.shopId });|' src/WebFold.mo

# a storefront opened or a listing made by somebody who is not a member (one line in two functions, both removed)
# Not injected, and why: web-stranger-opens-or-lists - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# A SECOND STOREFRONT OVER ONE SHOP (one line in both branches, both removed)
try web-second-storefront-over-a-shop Webshop \
  sed -i 's|switch (storefrontOfShop(c\.web, f\.shopId)) { case (?(other, _)) return #err(#shopHasStorefront { shopId = f\.shopId; storefrontId = other }); case null {} };|ignore f.shopId;|' src/WebFold.mo

# a closed storefront still filling carts, and closed again (one line in two functions, both removed)
try web-closed-storefront-sells Webshop \
  sed -i 's|    if (not sf\.isOpen) return #err(#storefrontClosed { storefrontId });|    if (false) return #err(#storefrontClosed { storefrontId });|' src/WebFold.mo

# A CATEGORY THE LIST DOES NOT PRICE listed
try web-unpriced-listed Webshop \
  sed -i 's|      case null return #err(#notOnTheList { categoryId = f\.categoryId });|      case null {};|' src/WebFold.mo

# a delisted category still for sale
try web-delisted-sold Webshop \
  sed -i 's|      case (?(_, l)) { if (not l\.isActive) return #err(#notListed { categoryId = f\.categoryId }) };|      case (?(_, _)) {};|' src/WebFold.mo

# A PRICED CATEGORY NOT ON THE CATALOGUE sold
try web-unlisted-sold Webshop \
  sed -i 's|      case null return #err(#notListed { categoryId = f\.categoryId });|      case null {};|' src/WebFold.mo

# Not injected either: a line of nothing or beyond the bound - the till's pricing refuses both inside the
# dry run, so the cart's own check changes no verdict. One open cart per shopper stands in for them.
# A SECOND OPEN CART for one shopper at one storefront
try web-second-cart-per-shopper Webshop \
  sed -i 's|    switch (openCartOf(c\.web, f\.storefrontId, c\.caller)) {|    switch (null : ?(Nat, WR.Cart)) {|' src/WebFold.mo

# the same kind not merged: a second line instead
try web-kind-not-merged Webshop \
  sed -i 's|          if (l\.categoryId == f\.categoryId) { List\.add(lines, { categoryId = l\.categoryId; quantity = l\.quantity + f\.quantity }); merged := true }|          if (false) { List.add(lines, { categoryId = l.categoryId; quantity = l.quantity + f.quantity }); merged := true }|' src/WebFold.mo

# SOMEBODY ELSE touching a shopper's cart
try web-anyone-touches-a-cart Webshop \
  sed -i 's|    if (c\.caller != x\.shopper) return #err(#notTheShopper { shopper = x\.shopper });|    if (false) return #err(#notTheShopper { shopper = x.shopper });|' src/WebFold.mo

# a checked-out or abandoned cart touched again
try web-cart-state-not-checked Webshop \
  sed -i 's|    if (x\.state != #open) return #err(#cartNotOpen { cartId; state = cartStateText(x\.state) });|    if (false) return #err(#cartNotOpen { cartId; state = cartStateText(x.state) });|' src/WebFold.mo

# a kind not in the cart taken out as if it were
try web-not-in-cart Webshop \
  sed -i 's|    if (not found) return #err(#notInCart { categoryId });|    if (false) return #err(#notInCart { categoryId });|' src/WebFold.mo

# the last kind out leaving the cart open on a cancelled draft
try web-empty-cart-stays-open Webshop \
  sed -i 's|      RowStore\.put<WR\.Cart>(c\.web\.carts, WR\.cart, cartId, { x with state = #abandoned; lines = 0; lastBlock = c\.block });|      RowStore.put<WR.Cart>(c.web.carts, WR.cart, cartId, { x with lines = 0; lastBlock = c.block });|' src/WebFold.mo

# THE PAYMENT NOT HELD TO TODAY'S TOTAL
try web-payment-not-the-total Webshop \
  sed -i 's|    if (f\.cardTendered != total) return #err(#amountDisagrees { total; tendered = f\.cardTendered });|    if (false) return #err(#amountDisagrees { total; tendered = f.cardTendered });|' src/WebFold.mo

# a payment without a reference
try web-payment-without-reference Webshop \
  sed -i 's|    if (Text\.size(f\.paymentReference) == 0) return #err(#nameRequired { what = "payment reference" });|    if (false) return #err(#nameRequired { what = "payment reference" });|' src/WebFold.mo

# THE EIGHTH OF SEVEN SOLD: availability not read
try web-availability-not-read Webshop \
  sed -i 's|      if (available < quantity) return #err(#notAvailable { categoryId; available; wanted = quantity });|      if (false) return #err(#notAvailable { categoryId; available; wanted = quantity });|' src/WebFold.mo

# availability read without what other orders hold
try web-availability-ignores-holds Webshop \
  sed -i 's|      let available = c\.onHand(f\.companyId, shop\.stockLocationId, categoryId) - reservedAt(c\.web, f\.companyId, shop\.stockLocationId, categoryId);|      let available = c.onHand(f.companyId, shop.stockLocationId, categoryId);|' src/WebFold.mo

# the cart's changes and the checkout's re-pricing not written to the draft (one line in three functions, all removed)
try web-draft-not-amended Webshop \
  sed -i 's|    switch (c\.amendOrder(x\.orderId, facts)) { case (#err e) return #err(#order e); case (#ok _) {} };|    ignore facts;|' src/WebFold.mo

# THE GOODS NOT HELD at the checkout
try web-goods-not-held Webshop \
  sed -i 's|      RowStore\.put<WR\.Reservation>(c\.web\.reservations, WR\.reservation, id, { companyId = f\.companyId; locationId = shop\.stockLocationId; categoryId; orderId = x\.orderId; quantity; isLive = true; lastBlock = c\.block });|      RowStore.put<WR.Reservation>(c.web.reservations, WR.reservation, id, { companyId = f.companyId; locationId = shop.stockLocationId; categoryId; orderId = x.orderId; quantity; isLive = false; lastBlock = c.block });|' src/WebFold.mo

# Not injected either: the shopper fulfilling their own order - the payment is proposed in the shopper's
# name and the ledger refuses its maker as its checker, so the fold's own rule changes no verdict (every
# web order posts a payment, so no act is free of the ledger). The cart's checked-out state stands in.
# a checked-out cart left open
try web-cart-stays-open-after-checkout Webshop \
  sed -i 's|    RowStore\.put<WR\.Cart>(c\.web\.carts, WR\.cart, f\.cartId, { x with state = #checkedOut; lastBlock = c\.block });|    RowStore.put<WR.Cart>(c.web.carts, WR.cart, f.cartId, { x with lastBlock = c.block });|' src/WebFold.mo

# a stranger fulfilling, delisting or closing (one line in three functions, all removed)
# Not injected, and why: web-stranger-fulfils-or-closes - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# THE SHIPMENT NOT ASKED ABOUT WHOLE: a picking left behind by a quality hold
try web-shipment-not-asked-whole Webshop \
  sed -i 's|      switch (c\.checkPicking(picking, journalId, o\.orderId)) { case (?e) return #err(#stock e); case null {} };|      ignore picking;|' src/WebFold.mo

# THE INVOICE NOT ASKED ABOUT WHOLE: a shipment left behind by a locked period
try web-invoice-not-asked-whole Webshop \
  sed -i 's|    switch (c\.checkIssue(companyId, o\.orderId, journalId)) { case (?e) return #err(#order e); case null {} };|    ignore journalId;|' src/WebFold.mo

# the payment move proposed in the member's own name
try web-payment-proposed-by-the-member Webshop \
  sed -i 's|    let paymentMoveId = switch (c\.postGenerated(o\.shopper, payment)) { case (#err e) return #err(#ledger e); case (#ok ids) ids\[0\] };|    let paymentMoveId = switch (c.postGenerated(c.caller, payment)) { case (#err e) return #err(#ledger e); case (#ok ids) ids[0] };|' src/WebFold.mo

# the payment's card line as nothing
try web-payment-card-line-empty Webshop \
  sed -i 's|        { accountId = shop\.cardAccountId; partnerId = 0; name = "card captured"; debit = o\.amountPaid; credit = 0; amountCurrency = 0; taxId = 0 },|        { accountId = shop.cardAccountId; partnerId = 0; name = "card captured"; debit = 0; credit = 0; amountCurrency = 0; taxId = 0 },|' src/WebFold.mo

# THE HOLD NOT FREED when the goods ship
try web-hold-not-freed-on-shipment Webshop \
  sed -i 's|    for ((rid, r) in held\.vals()) { if (r\.isLive) RowStore\.put<WR\.Reservation>(c\.web\.reservations, WR\.reservation, rid, { r with isLive = false; lastBlock = c\.block }) };|    ignore held;|' src/WebFold.mo

# the hold not freed when the order is cancelled
try web-hold-not-freed-on-cancel Webshop \
  sed -i 's|    for ((rid, r) in reservationsOf(c\.web, o\.orderId)\.vals()) { if (r\.isLive) RowStore\.put<WR\.Reservation>(c\.web\.reservations, WR\.reservation, rid, { r with isLive = false; lastBlock = c\.block }) };|    ignore o.orderId;|' src/WebFold.mo

# a cancelled order not refunded on record
try web-cancel-not-refunded Webshop \
  sed -i 's|    RowStore\.put<WR\.WebOrder>(c\.web\.orders, WR\.webOrder, webOrderId, { o with state = #cancelled; amountRefunded = o\.amountPaid; lastBlock = c\.block });|    RowStore.put<WR.WebOrder>(c.web.orders, WR.webOrder, webOrderId, { o with state = #cancelled; lastBlock = c.block });|' src/WebFold.mo

# a fulfilled or cancelled order fulfilled or cancelled again (one line in two functions, both removed)
try web-order-state-not-checked Webshop \
  sed -i 's|    if (o\.state != #paid) return #err(#webOrderNotInState { webOrderId; state = webOrderStateText(o\.state); wanted = "paid" });|    if (false) return #err(#webOrderNotInState { webOrderId; state = webOrderStateText(o.state); wanted = "paid" });|' src/WebFold.mo

# a stranger cancelling another's order
try web-stranger-cancels Webshop \
  sed -i 's|    if (c\.caller != o\.shopper and not c\.isMember(companyId, c\.caller)) return #err(#notAMember { subject = c\.caller });|    if (false) return #err(#notAMember { subject = c.caller });|' src/WebFold.mo

# ── the website ──────────────────────────────────────────────────────────────

# Not injected, and why: an erased document published or served (`Evidence.isErased`) - the document row
# is `#erased` too, and the state check above refuses first; a republished page left unpublished (the
# same line as the version move, injected once).

# A PAGE PUBLISHED BY SOMEBODY WHO IS NOT A MEMBER
# Not injected, and why: site-stranger-publishes - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# a page unpublished by somebody who is not a member
# Not injected, and why: site-stranger-unpublishes - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# A PATH WITHOUT ITS SLASH
try site-path-without-slash Website \
  sed -i 's|    if (not Text\.startsWith(path, #text "/")) return #err(#pathInvalid { path; why = "a path begins with a slash" });|    if (false) return #err(#pathInvalid { path; why = "a path begins with a slash" });|' src/SiteFold.mo

# A DOT-DOT SEGMENT, an empty one, a dot one
try site-dot-dot-segment Website \
  sed -i 's|        if (segment == "" or segment == "\." or segment == "\.\.") return #err(#pathInvalid { path; why = "a path has no empty, dot or dot-dot segment" });|        if (false) return #err(#pathInvalid { path; why = "a path has no empty, dot or dot-dot segment" });|' src/SiteFold.mo

# a space, or any other character, in the path
try site-path-any-character Website \
  sed -i 's|    for (ch in path\.chars()) { if (not pathChar(ch)) return #err(#pathInvalid { path; why = "a path is letters, digits, slashes, dots, hyphens and underscores" }) };|    ignore path;|' src/SiteFold.mo

# a content type with quotes or line breaks
try site-content-type-any-character Website \
  sed -i 's|      if (n < 33 and ch != '\'' '\'' or n > 126 or ch == '\''\\"'\'') return ?(#contentTypeInvalid { value; why = "a content type is printable ASCII without quotes or line breaks" });|      if (false) return ?(#contentTypeInvalid { value; why = "a content type is printable ASCII without quotes or line breaks" });|' src/SiteFold.mo

# a page without a content type
try site-content-type-required Website \
  sed -i 's|    if (Text\.size(value) == 0) return ?(#contentTypeInvalid { value; why = "a content type is required" });|    if (false) return ?(#contentTypeInvalid { value; why = "a content type is required" });|' src/SiteFold.mo

# ANOTHER COMPANY'S DOCUMENT as a page
try site-document-of-another-company Website \
  sed -i 's|    if (d\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = d\.companyId });|    if (false) return #err(#wrongCompany { expected = companyId; found = d.companyId });|' src/SiteFold.mo

# AN ATTACHMENT OR A PAPER as a page
try site-attachment-as-page Website \
  sed -i 's|    if (d\.kind != #company) return #err(#documentNotCompanyKind { documentId; kind = EF\.documentKindText(d\.kind) });|    if (false) return #err(#documentNotCompanyKind { documentId; kind = EF.documentKindText(d.kind) });|' src/SiteFold.mo

# AN ARCHIVED DOCUMENT published, and served
try site-archived-document-is-a-page Website \
  sed -i 's|    if (d\.state != #active) return #err(#documentNotActive { documentId; state = stateText(d\.state) });|    if (false) return #err(#documentNotActive { documentId; state = stateText(d.state) });|' src/SiteFold.mo

# a page beyond the bound
try site-page-beyond-the-bound Website \
  sed -i 's|          if (total > MAX_PAGE_BYTES) return #err(#pageTooLarge { bytes = total; max = MAX_PAGE_BYTES });|          if (false) return #err(#pageTooLarge { bytes = total; max = MAX_PAGE_BYTES });|' src/SiteFold.mo

# A DOCUMENT THAT IS NOT ITS OWN PLAINTEXT published: the fingerprint not checked
try site-fingerprint-not-checked Website \
  sed -i 's|    if (C\.hex(fingerprint) != ev\.plainHash) return #err(#fingerprintDisagrees { declared = ev\.plainHash; computed = C\.hex(fingerprint) });|    if (false) return #err(#fingerprintDisagrees { declared = ev.plainHash; computed = C.hex(fingerprint) });|' src/SiteFold.mo

# the bytes served without their fingerprint recomputed
try site-served-bytes-not-hashed Website \
  sed -i 's|    if (fingerprintOf(bytes) != v\.fingerprint) return null;|    if (false) return null;|' src/SiteFold.mo

# AN UNPUBLISHED PAGE STILL SERVED
try site-unpublished-still-served Website \
  sed -i 's|    if (not p\.isLive) return null;|    if (false) return null;|' src/SiteFold.mo

# published again, the page not moved to the new version
try site-new-version-not-current Website \
  sed -i 's|        RowStore\.put<SR\.Page>(c\.site\.pages, SR\.page, id, { p with currentVersion = p\.versions + 1; versions = p\.versions + 1; isLive = true; publishedBy = c\.caller; lastBlock = c\.block });|        RowStore.put<SR.Page>(c.site.pages, SR.page, id, { p with currentVersion = p.currentVersion; versions = p.versions + 1; isLive = true; publishedBy = c.caller; lastBlock = c.block });|' src/SiteFold.mo

# THE PUBLICATION BLOCK not the block the command made
try site-version-block-not-the-log Website \
  sed -i 's|      publishedBlock = c\.block; publishedDay = c\.day; publishedBy = c\.caller; lastBlock = c\.block });|      publishedBlock = 0; publishedDay = c.day; publishedBy = c.caller; lastBlock = c.block });|' src/SiteFold.mo

# a page unpublished twice
try site-unpublish-twice Website \
  sed -i 's|    if (not p\.isLive) return #err(#pageNotLive { pageId });|    if (false) return #err(#pageNotLive { pageId });|' src/SiteFold.mo

# the root not served as the index
try site-root-not-the-index Website \
  sed -i 's|        if (path != "/") null else {|        if (true) null else {|' src/SiteFold.mo

# any url routed as a page
try site-route-any-prefix Website \
  sed -i 's|    if (not Text\.startsWith(clean, #text "/sites/")) return null;|    if (false) return null;|' src/SiteFold.mo

# A QUERY STRING READ as part of the path
try site-route-query-read Website \
  sed -i 's|    let clean = switch (Text\.split(url, #char '\''?'\'')\.next()) { case (?u) u; case null url };|    let clean = url;|' src/SiteFold.mo

# a second page at the same path instead of a new version
try site-page-path-not-unique Website \
  sed -i 's|    let (pageId, ordinal) = switch (pageByPath(c\.site, f\.companyId, path)) {|    let (pageId, ordinal) = switch (null : ?(Nat, SR.Page)) {|' src/SiteFold.mo

# a page unpublished under the wrong company
try site-unpublish-wrong-company Website \
  sed -i 's|    if (p\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p\.companyId });|    if (false) return #err(#wrongCompany { expected = companyId; found = p.companyId });|' src/SiteFold.mo

# ── the blog ─────────────────────────────────────────────────────────────────

# Not injected, and why: a document that is not the company's, not a company document, archived or too
# large - the website's own checks (`SiteFold.pageDocument`, `readBytes`), which the blog asks and the
# website slice removes; a slug beyond the field (`F.textField` refuses it, the fold only names why).

# A POST BY SOMEBODY WHO IS NOT A MEMBER
# Not injected, and why: blog-stranger-publishes - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# a stranger withdrawing
# Not injected, and why: blog-stranger-withdraws - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# A SLUG WITH A CAPITAL, a space or a slash
try blog-slug-any-character Blog \
  sed -i 's|    for (ch in slug\.chars()) { if (not slugChar(ch)) return #err(#slugInvalid { slug; why = "a slug is lower-case letters, digits and hyphens" }) };|    ignore slug;|' src/BlogFold.mo

# a slug starting or ending with a hyphen
try blog-slug-hyphen-at-an-end Blog \
  sed -i 's|    if (Text\.startsWith(slug, #text "-") or Text\.endsWith(slug, #text "-")) return #err(#slugInvalid { slug; why = "a slug neither starts nor ends with a hyphen" });|    if (false) return #err(#slugInvalid { slug; why = "a slug neither starts nor ends with a hyphen" });|' src/BlogFold.mo

# a post without a title
try blog-title-required Blog \
  sed -i 's|    if (Text\.size(f\.title) == 0) return #err(#titleRequired);|    if (false) return #err(#titleRequired);|' src/BlogFold.mo

# A SLUG A LIVE POST HOLDS taken again
try blog-slug-not-held Blog \
  sed -i 's|    switch (existing) { case (?(postId, p)) { if (p\.isLive) return #err(#slugTaken { slug = f\.slug; postId }) }; case null {} };|    switch (existing) { case (?(_, _)) {}; case null {} };|' src/BlogFold.mo

# A DOCUMENT THAT IS NOT ITS OWN PLAINTEXT as a post: the fingerprint not checked
try blog-fingerprint-not-checked Blog \
  sed -i 's|    if (SFold\.hexOf(fingerprint) != ev\.plainHash) return #err(#site(#fingerprintDisagrees { declared = ev\.plainHash; computed = SFold\.hexOf(fingerprint) }));|    if (false) return #err(#site(#fingerprintDisagrees { declared = ev.plainHash; computed = SFold.hexOf(fingerprint) }));|' src/BlogFold.mo

# THE DATE NOT THE CALENDAR'S: a post dated day nought
try blog-date-not-the-calendars Blog \
  sed -i 's|          companyId = f\.companyId; slug; title; author = c\.caller; publishedDay = c\.day; publishedBlock = c\.block; revisedDay = c\.day; revision = 1;|          companyId = f.companyId; slug; title; author = c.caller; publishedDay = 0; publishedBlock = c.block; revisedDay = c.day; revision = 1;|' src/BlogFold.mo

# THE AUTHOR NOT THE CALLER
try blog-author-not-the-caller Blog \
  sed -i 's|          companyId = f\.companyId; slug; title; author = c\.caller; publishedDay = c\.day; publishedBlock = c\.block; revisedDay = c\.day; revision = 1;|          companyId = f.companyId; slug; title; author = Principal.fromText(\"aaaaa-aa\"); publishedDay = c.day; publishedBlock = c.block; revisedDay = c.day; revision = 1;|' src/BlogFold.mo

# a revision moving the day of first publication
try blog-revision-moves-the-first-day Blog \
  sed -i 's|    RowStore\.put<BR\.Post>(c\.blog\.posts, BR\.post, f\.postId, { p with revisedDay = c\.day; revision = p\.revision + 1; documentId = f\.documentId; evidenceId; contentType; byteSize; fingerprint; lastBlock = c\.block });|    RowStore.put<BR.Post>(c.blog.posts, BR.post, f.postId, { p with publishedDay = c.day; revisedDay = c.day; revision = p.revision + 1; documentId = f.documentId; evidenceId; contentType; byteSize; fingerprint; lastBlock = c.block });|' src/BlogFold.mo

# a revision not counted
try blog-revision-not-counted Blog \
  sed -i 's|    RowStore\.put<BR\.Post>(c\.blog\.posts, BR\.post, f\.postId, { p with revisedDay = c\.day; revision = p\.revision + 1; documentId = f\.documentId; evidenceId; contentType; byteSize; fingerprint; lastBlock = c\.block });|    RowStore.put<BR.Post>(c.blog.posts, BR.post, f.postId, { p with revisedDay = c.day; revision = p.revision; documentId = f.documentId; evidenceId; contentType; byteSize; fingerprint; lastBlock = c.block });|' src/BlogFold.mo

# a withdrawn post revised
try blog-withdrawn-post-revised Blog \
  sed -i 's|    if (not p\.isLive) return #err(#postWithdrawn { postId = f\.postId });|    if (false) return #err(#postWithdrawn { postId = f.postId });|' src/BlogFold.mo

# a post withdrawn twice
try blog-withdraw-twice Blog \
  sed -i 's|    if (not p\.isLive) return #err(#postWithdrawn { postId });|    if (false) return #err(#postWithdrawn { postId });|' src/BlogFold.mo

# A WITHDRAWN POST STILL SERVED
try blog-withdrawn-still-served Blog \
  sed -i 's|    if (not p\.isLive) return null;|    if (false) return null;|' src/BlogFold.mo

# the bytes served without their fingerprint recomputed
try blog-served-bytes-not-hashed Blog \
  sed -i 's|    if (SFold\.fingerprintOf(bytes) != p\.fingerprint) return null;|    if (false) return null;|' src/BlogFold.mo

# THE INDEX OLDEST FIRST
try blog-index-oldest-first Blog \
  sed -i 's|  Array\.tabulate<(Nat, BR\.Post)>(n, func(i) { asc\[asc\.size() - 1 - i\] })|  Array.tabulate<(Nat, BR.Post)>(n, func(i) { asc[i] })|' src/BlogFold.mo

# A TITLE'S MARKUP NOT ESCAPED in the index
try blog-title-not-escaped Blog \
  sed -i 's|      body #= "<li><a href=\\"/sites/" # escape(companySlug) # "/blog/" # slug # "\\">" # escape(title) # "</a> <time datetime=\\"" # isoDate(p\.publishedDay) # "\\">" # isoDate(p\.publishedDay) # "</time></li>";|      body #= "<li><a href=\\"/sites/" # escape(companySlug) # "/blog/" # slug # "\\">" # title # "</a> <time datetime=\\"" # isoDate(p.publishedDay) # "\\">" # isoDate(p.publishedDay) # "</time></li>";|' src/BlogFold.mo

# the date written by another calendar
try blog-date-off-by-a-day Blog \
  sed -i 's|    let (y, m, d) = CivilDate\.toCivil(day);|    let (y, m, d) = CivilDate.toCivil(day + 1);|' src/BlogFold.mo

# the index route taking a post's path
try blog-route-any-path Blog \
  sed -i 's|    if (not Text\.startsWith(path, #text "/blog/")) return null;|    if (false) return null;|' src/BlogFold.mo

# ── the forum ────────────────────────────────────────────────────────────────

# Not injected, and why: a board or a moderation of a company that does not exist (the membership check
# refuses it too); a slug beyond the field (`F.textField` refuses it, the fold only names why); the
# wrong-company check of a reply moderation and of a topic moderation when the caller is no member of the
# other company (the battery makes the moderator a member of both so each has one cause).

# A BOARD BY SOMEBODY WHO IS NOT A MEMBER
# Not injected, and why: forum-stranger-declares - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# A TOPIC BY SOMEBODY WHO IS NOT A MEMBER
# Not injected, and why: forum-stranger-opens-a-topic - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# A REPLY BY SOMEBODY WHO IS NOT A MEMBER
# Not injected, and why: forum-stranger-replies - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# A MODERATION BY SOMEBODY WHO IS NOT A MEMBER
# Not injected, and why: forum-stranger-moderates - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# THE SLUG RULE IS THE BLOG'S: a capital accepted
try forum-slug-rule-not-the-blogs Forum \
  sed -i 's|^    let slug = switch (slugField(f\.slug)) { case (#err e) return #err(e); case (#ok s) s };$|    let slug = switch (slugField(f.slug)) { case (#err e) { switch (F.textField(f.slug, W.PATH)) { case (?s) s; case null return #err(e) } }; case (#ok s) s };|' src/ForumFold.mo

# a board needs a title
try forum-board-title-required Forum \
  sed -i 's|^    if (Text\.size(f\.title) == 0) return #err(#titleRequired);$|    if (false) return #err(#titleRequired);|' src/ForumFold.mo

# a topic needs a title
try forum-topic-title-required Forum \
  sed -i 's|^    if (Text\.size(f\.title) == 0) return #err(#titleRequired); // a topic has a title$|    if (false) return #err(#titleRequired); // a topic has a title|' src/ForumFold.mo

# DECLARED AGAIN, the title changes
try forum-declared-again-unchanged Forum \
  sed -i 's|^        RowStore\.put<FR\.Board>(c\.forum\.boards, FR\.board, boardId, { b with title; description; lastBlock = c\.block });$|        RowStore.put<FR.Board>(c.forum.boards, FR.board, boardId, { b with lastBlock = c.block });|' src/ForumFold.mo

# a topic on another company's board
try forum-topic-wrong-company Forum \
  sed -i 's|^    if (b\.companyId != f\.companyId) return #err(#wrongCompany { expected = f\.companyId; found = b\.companyId });$|    if (false) return #err(#wrongCompany { expected = f.companyId; found = b.companyId });|' src/ForumFold.mo

# A TOPIC WITHOUT A WORD
try forum-topic-word-required Forum \
  sed -i 's|^    if (Text\.size(f\.body) == 0) return #err(#bodyRequired);$|    if (false) return #err(#bodyRequired);|' src/ForumFold.mo

# A REPLY WITHOUT A WORD
try forum-reply-word-required Forum \
  sed -i 's|^    if (Text\.size(f\.body) == 0) return #err(#bodyRequired); // a reply is a word$|    if (false) return #err(#bodyRequired); // a reply is a word|' src/ForumFold.mo

# THE AUTHOR IS THE CALLER
try forum-author-not-the-caller Forum \
  sed -i 's|^      companyId = f\.companyId; boardId = f\.boardId; title; body; author = c\.caller; openedDay = c\.day; openedBlock = c\.block;$|      companyId = f.companyId; boardId = f.boardId; title; body; author = Principal.fromText("aaaaa-aa"); openedDay = c.day; openedBlock = c.block;|' src/ForumFold.mo

# THE DAY IS THE CALENDAR'S
try forum-day-not-the-calendars Forum \
  sed -i 's|^      companyId = f\.companyId; boardId = f\.boardId; title; body; author = c\.caller; openedDay = c\.day; openedBlock = c\.block;$|      companyId = f.companyId; boardId = f.boardId; title; body; author = c.caller; openedDay = c.day + 1; openedBlock = c.block;|' src/ForumFold.mo

# THE BOARD COUNTS ITS TOPICS
try forum-board-does-not-count Forum \
  sed -i 's|^    RowStore\.put<FR\.Board>(c\.forum\.boards, FR\.board, f\.boardId, { b with topics = b\.topics + 1; lastBlock = c\.block });$|    RowStore.put<FR.Board>(c.forum.boards, FR.board, f.boardId, { b with topics = b.topics; lastBlock = c.block });|' src/ForumFold.mo

# a reply on another company's topic
try forum-reply-wrong-company Forum \
  sed -i 's|^    if (t\.companyId != f\.companyId) return #err(#wrongCompany { expected = f\.companyId; found = t\.companyId });$|    if (false) return #err(#wrongCompany { expected = f.companyId; found = t.companyId });|' src/ForumFold.mo

# A HIDDEN TOPIC TAKES NO REPLY
try forum-hidden-topic-takes-replies Forum \
  sed -i 's|^    if (t\.isHidden) return #err(#topicHidden { topicId = f\.topicId });$|    if (false) return #err(#topicHidden { topicId = f.topicId });|' src/ForumFold.mo

# A LOCKED TOPIC TAKES NO REPLY
try forum-locked-topic-takes-replies Forum \
  sed -i 's|^    if (t\.isLocked) return #err(#topicLocked { topicId = f\.topicId });$|    if (false) return #err(#topicLocked { topicId = f.topicId });|' src/ForumFold.mo

# THE TOPIC COUNTS ITS REPLIES
try forum-reply-not-counted Forum \
  sed -i 's|^    RowStore\.put<FR\.Topic>(c\.forum\.topics, FR\.topic, f\.topicId, { t with replies = t\.replies + 1; lastDay = c\.day; activityBlock = c\.block; lastBlock = c\.block });$|    RowStore.put<FR.Topic>(c.forum.topics, FR.topic, f.topicId, { t with replies = t.replies; lastDay = c.day; activityBlock = c.block; lastBlock = c.block });|' src/ForumFold.mo

# A REPLY MOVES THE TOPIC'S LATEST WORD
try forum-reply-does-not-move-the-latest-word Forum \
  sed -i 's|^    RowStore\.put<FR\.Topic>(c\.forum\.topics, FR\.topic, f\.topicId, { t with replies = t\.replies + 1; lastDay = c\.day; activityBlock = c\.block; lastBlock = c\.block });$|    RowStore.put<FR.Topic>(c.forum.topics, FR.topic, f.topicId, { t with replies = t.replies + 1; lastDay = c.day; activityBlock = t.activityBlock; lastBlock = c.block });|' src/ForumFold.mo

# the reply's author is the caller
try forum-reply-author-not-the-caller Forum \
  sed -i 's|^    RowStore\.put<FR\.Reply>(c\.forum\.replies, FR\.reply, id, { companyId = f\.companyId; topicId = f\.topicId; author = c\.caller; body; day = c\.day; block = c\.block; isHidden = false; lastBlock = c\.block });$|    RowStore.put<FR.Reply>(c.forum.replies, FR.reply, id, { companyId = f.companyId; topicId = f.topicId; author = Principal.fromText("aaaaa-aa"); body; day = c.day; block = c.block; isHidden = false; lastBlock = c.block });|' src/ForumFold.mo

# A MODERATION NAMES ITS REASON
try forum-reason-required Forum \
  sed -i 's|^    if (Text\.size(f\.reason) == 0) return #err(#reasonRequired);$|    if (false) return #err(#reasonRequired);|' src/ForumFold.mo

# a moderation of another company's topic
try forum-moderation-wrong-company Forum \
  sed -i 's|^        if (t\.companyId != f\.companyId) return #err(#wrongCompany { expected = f\.companyId; found = t\.companyId });$|        if (false) return #err(#wrongCompany { expected = f.companyId; found = t.companyId });|' src/ForumFold.mo

# a moderation of another company's reply
try forum-reply-moderation-wrong-company Forum \
  sed -i 's|^        if (r\.companyId != f\.companyId) return #err(#wrongCompany { expected = f\.companyId; found = r\.companyId });$|        if (false) return #err(#wrongCompany { expected = f.companyId; found = r.companyId });|' src/ForumFold.mo

# NOBODY MODERATES THEIR OWN TOPIC
try forum-moderating-own-topic Forum \
  sed -i 's|^        if (c\.caller == t\.author) return #err(#moderatingOwnWord { author = t\.author; target = #topic; targetId = f\.targetId });$|        if (false) return #err(#moderatingOwnWord { author = t.author; target = #topic; targetId = f.targetId });|' src/ForumFold.mo

# NOBODY MODERATES THEIR OWN REPLY
try forum-moderating-own-reply Forum \
  sed -i 's|^        if (c\.caller == r\.author) return #err(#moderatingOwnWord { author = r\.author; target = #reply; targetId = f\.targetId });$|        if (false) return #err(#moderatingOwnWord { author = r.author; target = #reply; targetId = f.targetId });|' src/ForumFold.mo

# AN ACT THAT WOULD CHANGE NOTHING on a topic is refused
try forum-topic-act-that-changes-nothing Forum \
  sed -i 's|^        if (wouldChangeNothing(f\.act, t\.isHidden, t\.isLocked, t\.isPinned)) return #err(#alreadySo { act = f\.act; target = #topic; targetId = f\.targetId });$|        if (false) return #err(#alreadySo { act = f.act; target = #topic; targetId = f.targetId });|' src/ForumFold.mo

# AN ACT THAT WOULD CHANGE NOTHING on a reply is refused
try forum-reply-act-that-changes-nothing Forum \
  sed -i 's|^        if (wouldChangeNothing(f\.act, r\.isHidden, false, false)) return #err(#alreadySo { act = f\.act; target = #reply; targetId = f\.targetId });$|        if (false) return #err(#alreadySo { act = f.act; target = #reply; targetId = f.targetId });|' src/ForumFold.mo

# LOCKING AND PINNING ARE A TOPIC'S
try forum-reply-locked-or-pinned Forum \
  sed -i 's|^        switch (f\.act) { case (#hide or #restore) {}; case (act) return #err(#actNotForTarget { act; target = #reply }) };$|        ignore f.act;|' src/ForumFold.mo

# A MODERATION IS A RECORDED ACT
try forum-moderation-not-recorded Forum \
  sed -i 's|^    RowStore\.put<FR\.Moderation>(c\.forum\.moderations, FR\.moderation, id, { companyId = f\.companyId; target = f\.target; targetId = f\.targetId; act = f\.act; moderator = c\.caller; author; reason; day = c\.day; block = c\.block });$|    ignore reason;|' src/ForumFold.mo

# the moderator on the row is the caller
try forum-moderator-not-the-caller Forum \
  sed -i 's|^    RowStore\.put<FR\.Moderation>(c\.forum\.moderations, FR\.moderation, id, { companyId = f\.companyId; target = f\.target; targetId = f\.targetId; act = f\.act; moderator = c\.caller; author; reason; day = c\.day; block = c\.block });$|    RowStore.put<FR.Moderation>(c.forum.moderations, FR.moderation, id, { companyId = f.companyId; target = f.target; targetId = f.targetId; act = f.act; moderator = author; author; reason; day = c.day; block = c.block });|' src/ForumFold.mo

# A HIDDEN REPLY IS SERVED NO MORE
try forum-hidden-reply-still-served Forum \
  sed -i 's|^      if (not r\.isHidden and shown < THREAD_LIMIT) {$|      if (shown < THREAD_LIMIT) {|' src/ForumFold.mo

# A HIDDEN TOPIC IS SERVED NO MORE
try forum-hidden-topic-still-served Forum \
  sed -i 's|^    if (t\.boardId != boardId or t\.companyId != companyId or t\.isHidden) return null;$|    if (t.boardId != boardId or t.companyId != companyId) return null;|' src/ForumFold.mo

# a thread is served under its own board alone
try forum-thread-of-another-board Forum \
  sed -i 's|^    if (t\.boardId != boardId or t\.companyId != companyId or t\.isHidden) return null;$|    if (t.companyId != companyId or t.isHidden) return null;|' src/ForumFold.mo

# every word served is escaped
try forum-text-not-escaped Forum \
  sed -i 's|^        body #= "<li><p>" # BFold\.escape(textOf(arena, r\.body)) # "</p>" # byline(r\.author, r\.day) # "</li>";$|        body #= "<li><p>" # textOf(arena, r.body) # "</p>" # byline(r.author, r.day) # "</li>";|' src/ForumFold.mo

# THE LATEST WORD FIRST
try forum-latest-word-last Forum \
  sed -i 's|^    Array\.tabulate<(Nat, FR\.Topic)>(n, func(i) { asc\[asc\.size() - 1 - i\] })$|    Array.tabulate<(Nat, FR.Topic)>(n, func(i) { asc[i] })|' src/ForumFold.mo

# a path not under /forum is not the forum's
try forum-route-any-path Forum \
  sed -i 's|^    if (not Text\.startsWith(path, #text "/forum/")) return null;$|    if (false) return null;|' src/ForumFold.mo

# A HIDDEN TOPIC IS LISTED NO MORE
try forum-hidden-topic-still-listed Forum \
  sed -i 's|^        keyOf = func(id : Nat, x : Topic) : ?Blob { if (x\.isHidden) null else ?listKey(x\.boardId, x\.isPinned, x\.activityBlock, id) } },$|        keyOf = func(id : Nat, x : Topic) : ?Blob { ?listKey(x.boardId, x.isPinned, x.activityBlock, id) } },|' src/ForumRows.mo

# PINNED FIRST
try forum-pinned-not-first Forum \
  sed -i 's|^        keyOf = func(id : Nat, x : Topic) : ?Blob { if (x\.isHidden) null else ?listKey(x\.boardId, x\.isPinned, x\.activityBlock, id) } },$|        keyOf = func(id : Nat, x : Topic) : ?Blob { if (x.isHidden) null else ?listKey(x.boardId, false, x.activityBlock, id) } },|' src/ForumRows.mo

# ── ideas ────────────────────────────────────────────────────────────────────
#
# Not injected, and why: the employee, the stranger and the director marking or deciding, and the stranger voting
# (the gate's holders refuse each before the fold - a vote's are the company's members - and the isolation battery
# holds the holders table; the fold's own member check is reached by no route the contract takes); a note beyond
# the field (the arena's bound, the fold only names it).

# A VOTE ON A TOPIC THAT IS NO IDEA
try idea-any-topic-is-an-idea Forum \
  sed -i 's|^    if (not isIdeaBoard(c\.forum, t\.boardId)) return #err(#notAnIdea { topicId });$|    if (false) return #err(#notAnIdea { topicId });|' src/ForumFold.mo

# A HIDDEN IDEA TAKES NO VOTE
try idea-hidden-takes-a-vote Forum \
  sed -i 's|^    if (t\.isHidden) return #err(#topicHidden { topicId });$|    if (false) return #err(#topicHidden { topicId });|' src/ForumFold.mo

# MARKING WHAT IS MARKED
try idea-mark-that-changes-nothing Forum \
  sed -i 's|^    if (isIdeaBoard(c\.forum, f\.boardId) == f\.isIdeas) return #err(#boardAlreadySo { boardId = f\.boardId; isIdeas = f\.isIdeas });$|    if (false) return #err(#boardAlreadySo { boardId = f.boardId; isIdeas = f.isIdeas });|' src/ForumFold.mo

# ANOTHER COMPANY'S BOARD MARKED
try idea-board-of-another-company Forum \
  sed -i 's|^    if (b\.companyId != f\.companyId) return #err(#wrongCompany { expected = f\.companyId; found = b\.companyId }); // the board marked is the company'\''s$|    if (false) return #err(#wrongCompany { expected = f.companyId; found = b.companyId }); // the board marked is the company'\''s|' src/ForumFold.mo

# AN IDEA OF ANOTHER COMPANY
try idea-of-another-company Forum \
  sed -i 's|^    if (t\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = t\.companyId }); // the idea is the company'\''s$|    if (false) return #err(#wrongCompany { expected = companyId; found = t.companyId }); // the idea is the company'\''s|' src/ForumFold.mo

# NOBODY DECIDES THEIR OWN IDEA
try idea-author-decides Forum \
  sed -i 's|^    if (c\.caller == t\.author) return #err(#decidingOwnIdea { author = t\.author; topicId = f\.topicId });$|    if (false) return #err(#decidingOwnIdea { author = t.author; topicId = f.topicId });|' src/ForumFold.mo

# AN IDEA MOVES FORWARD ONLY
try idea-status-moves-any-way Forum \
  sed -i 's|^    if (not moves(from, f\.status)) return #err(#statusMove { topicId = f\.topicId; from; to = f\.status });$|    if (false) return #err(#statusMove { topicId = f.topicId; from; to = f.status });|' src/ForumFold.mo

# an approved idea taken to rejected
try idea-approved-then-rejected Forum \
  sed -i 's|^      case (#approved, #implemented) true;$|      case (#approved, #implemented or #rejected) true;|' src/ForumFold.mo

# A REJECTION AND AN IMPLEMENTATION SAY WHY
try idea-decided-without-a-word Forum \
  sed -i 's|^    if ((f\.status == #rejected or f\.status == #implemented) and Text\.size(f\.note) == 0) return #err(#noteRequired { status = f\.status });$|    if (false) return #err(#noteRequired { status = f.status });|' src/ForumFold.mo

# NOBODY VOTES FOR THEIR OWN IDEA
try idea-author-votes Forum \
  sed -i 's|^    if (c\.caller == t\.author) return #err(#votingOwnIdea { author = t\.author; topicId = f\.topicId });$|    if (false) return #err(#votingOwnIdea { author = t.author; topicId = f.topicId });|' src/ForumFold.mo

# ONE VOTE PER MEMBER AND IDEA: the same vote twice
try idea-vote-twice Forum \
  sed -i 's|^        if (v\.isUp == f\.isUp) return #err(#alreadyVoted { topicId = f\.topicId; isUp = f\.isUp });$|        if (false) return #err(#alreadyVoted { topicId = f.topicId; isUp = f.isUp });|' src/ForumFold.mo

# a changed vote written as a row of its own
try idea-changed-vote-a-new-row Forum \
  sed -i 's|^        RowStore\.put<FR\.TopicVote>(c\.forum\.votes, FR\.topicVote, id, { v with isUp = f\.isUp; lastBlock = c\.block });$|        RowStore.put<FR.TopicVote>(c.forum.votes, FR.topicVote, c.forum.nextVoteId, { v with isUp = f.isUp; lastBlock = c.block }); c.forum.nextVoteId += 1;|' src/ForumFold.mo

# A VOTE TAKEN BACK THAT WAS NEVER CAST
try idea-vote-taken-back-never-cast Forum \
  sed -i 's|^        if (not f\.isUp) return #err(#alreadyVoted { topicId = f\.topicId; isUp = false });$|        if (false) return #err(#alreadyVoted { topicId = f.topicId; isUp = false });|' src/ForumFold.mo

# ── live chat ────────────────────────────────────────────────────────────────

# Not injected, and why: an enrolment, a withdrawal or a take at a company that does not exist (the
# membership or operator check refuses it too); a transfer or a rating under the wrong company (the
# receiver is no operator of the other company, and the rating's visitor check, refuse them too).

# AN ENROLMENT BY SOMEBODY WHO IS NOT A MEMBER
# Not injected, and why: chat-stranger-enrols - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# A STRANGER ENROLLED
try chat-stranger-enrolled Chat \
  sed -i 's|^    if (not c\.isMember(companyId, subject)) return #err(#notAMember { subject });$|    if (false) return #err(#notAMember { subject });|' src/ChatFold.mo

# NOBODY ENROLS THEMSELVES
try chat-enrolling-oneself Chat \
  sed -i 's|^    if (c\.caller == subject) return #err(#enrollingOneself { subject });$|    if (false) return #err(#enrollingOneself { subject });|' src/ChatFold.mo

# enrolled twice
try chat-enrolled-twice Chat \
  sed -i 's|^        if (o\.isEnrolled) return #err(#alreadyEnrolled { subject });$|        if (false) return #err(#alreadyEnrolled { subject });|' src/ChatFold.mo

# a withdrawal by a stranger
# Not injected, and why: chat-stranger-withdraws - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# withdrawn twice
try chat-withdrawn-twice Chat \
  sed -i 's|^    if (not o\.isEnrolled) return #err(#notEnrolled { subject });$|    if (false) return #err(#notEnrolled { subject });|' src/ChatFold.mo

# withdrawn, taking no more
try chat-withdrawal-withdraws-nobody Chat \
  sed -i 's|^    RowStore\.put<CR\.Operator>(c\.chat\.operators, CR\.operator, id, { o with isEnrolled = false; lastBlock = c\.block });$|    RowStore.put<CR.Operator>(c.chat.operators, CR.operator, id, { o with isEnrolled = true; lastBlock = c.block });|' src/ChatFold.mo

# a conversation with a company that does not exist
try chat-conversation-with-no-company Chat \
  sed -i 's|^    if (not c\.companyExists(f\.companyId)) return #err(#wrongCompany { expected = f\.companyId; found = 0 });$|    if (false) return #err(#wrongCompany { expected = f.companyId; found = 0 });|' src/ChatFold.mo

# A CONVERSATION WITHOUT A FIRST WORD
try chat-first-word-required Chat \
  sed -i 's|^    switch (wordFits(f\.body)) { case (?e) return #err(e); case null {} };$|    ignore wordFits(f.body);|' src/ChatFold.mo

# ONE LIVE CONVERSATION PER VISITOR
try chat-second-live-conversation Chat \
  sed -i 's|^    switch (liveConversationOf(c\.chat, f\.companyId, c\.caller)) { case (?(conversationId, _)) return #err(#conversationLive { conversationId }); case null {} };$|    ignore liveConversationOf(c.chat, f.companyId, c.caller);|' src/ChatFold.mo

# THE VISITOR IS THE CALLER
try chat-visitor-not-the-caller Chat \
  sed -i 's|^      companyId = f\.companyId; visitor = c\.caller; operator = c\.caller; state = #waiting; openedDay = c\.day; openedBlock = c\.block;$|      companyId = f.companyId; visitor = Principal.fromText("aaaaa-aa"); operator = c.caller; state = #waiting; openedDay = c.day; openedBlock = c.block;|' src/ChatFold.mo

# THE DAY IS THE CALENDAR'S
try chat-day-not-the-calendars Chat \
  sed -i 's|^      companyId = f\.companyId; visitor = c\.caller; operator = c\.caller; state = #waiting; openedDay = c\.day; openedBlock = c\.block;$|      companyId = f.companyId; visitor = c.caller; operator = c.caller; state = #waiting; openedDay = c.day + 1; openedBlock = c.block;|' src/ChatFold.mo

# the opening word is the first of the history
try chat-opening-word-not-counted Chat \
  sed -i 's|^      takenBlock = 0; closedDay = 0; closedBlock = 0; messages = 1; rating = #unrated; lastBlock = c\.block });$|      takenBlock = 0; closedDay = 0; closedBlock = 0; messages = 0; rating = #unrated; lastBlock = c.block });|' src/ChatFold.mo

# ONLY AN ENROLLED OPERATOR TAKES
try chat-anybody-takes Chat \
  sed -i 's|^    if (not isOperator(c\.chat, companyId, c\.caller)) return #err(#notAnOperator { subject = c\.caller });$|    if (false) return #err(#notAnOperator { subject = c.caller });|' src/ChatFold.mo

# nothing waiting, nothing taken
try chat-nothing-waiting-taken Chat \
  sed -i 's|^    if (queue\.size() == 0) return #err(#nobodyWaiting);$|    if (queue.size() == 0) return #ok([]);|' src/ChatFold.mo

# GIVEN THE LONGEST WAITING CONVERSATION
try chat-not-the-longest-waiting Chat \
  sed -i 's|^    let (id, v) = queue\[0\];$|    let (id, v) = queue[queue.size() - 1];|' src/ChatFold.mo

# a take counted to the taker
try chat-take-not-counted Chat \
  sed -i 's|^    countTaken(c, companyId, c\.caller);$|    ignore 0;|' src/ChatFold.mo

# a waiting conversation is nobody's to hand over
try chat-transfer-of-a-waiting-conversation Chat \
  sed -i 's|^    if (v\.state != #open) return #err(#notOpen { conversationId = f\.conversationId; state = v\.state });$|    if (false) return #err(#notOpen { conversationId = f.conversationId; state = v.state });|' src/ChatFold.mo

# a transfer is the holder's
try chat-transfer-by-a-non-holder Chat \
  sed -i 's|^    if (c\.caller != v\.operator) return #err(#notTheOperator { conversationId = f\.conversationId; operator = v\.operator });$|    if (false) return #err(#notTheOperator { conversationId = f.conversationId; operator = v.operator });|' src/ChatFold.mo

# HANDED TO ONESELF
try chat-transfer-to-oneself Chat \
  sed -i 's|^    if (f\.to == c\.caller) return #err(#transferToSelf);$|    if (false) return #err(#transferToSelf);|' src/ChatFold.mo

# HANDED TO A MEMBER WHO IS NOT AN OPERATOR
try chat-transfer-to-a-non-operator Chat \
  sed -i 's|^    if (not isOperator(c\.chat, f\.companyId, f\.to)) return #err(#notAnOperator { subject = f\.to });$|    if (false) return #err(#notAnOperator { subject = f.to });|' src/ChatFold.mo

# a transfer counted to the receiver
try chat-transfer-not-counted Chat \
  sed -i 's|^    countTaken(c, f\.companyId, f\.to);$|    ignore 0;|' src/ChatFold.mo

# A CLOSED CONVERSATION TAKES NO WORD
try chat-closed-conversation-takes-words Chat \
  sed -i 's|^    if (v\.state == #closed) return #err(#conversationClosed { conversationId = f\.conversationId });$|    if (false) return #err(#conversationClosed { conversationId = f.conversationId });|' src/ChatFold.mo

# a word under the wrong company
try chat-word-under-the-wrong-company Chat \
  sed -i 's|^    if (v\.companyId != f\.companyId) return #err(#wrongCompany { expected = f\.companyId; found = v\.companyId }); // a word is on the one company'\''s conversation$|    if (false) return #err(#wrongCompany { expected = f.companyId; found = v.companyId }); // a word is on the one company'\''s conversation|' src/ChatFold.mo

# A WORD IS THE VISITOR'S OR THE HOLDING OPERATOR'S
try chat-anybody-speaks Chat \
  sed -i 's|^    let speaker : E\.ChatSpeaker = if (c\.caller == v\.visitor) #visitor else if (v\.state == #open and c\.caller == v\.operator) #operator else return #err(#notAParty { conversationId = f\.conversationId });$|    let speaker : E.ChatSpeaker = if (c.caller == v.visitor) #visitor else #operator;|' src/ChatFold.mo

# A WORD OF NOTHING
try chat-word-required Chat \
  sed -i 's|^    switch (wordFits(f\.body)) { case (?e) return #err(e); case null {} }; // a word on a conversation$|    ignore wordFits(f.body); // a word on a conversation|' src/ChatFold.mo

# THE HISTORY IS BOUNDED
try chat-history-unbounded Chat \
  sed -i 's|^    if (v\.messages >= HISTORY) return #err(#historyFull { conversationId = f\.conversationId; limit = HISTORY });$|    if (false) return #err(#historyFull { conversationId = f.conversationId; limit = HISTORY });|' src/ChatFold.mo

# every word counted
try chat-word-not-counted Chat \
  sed -i 's|^    RowStore\.put<CR\.Conversation>(c\.chat\.conversations, CR\.conversation, f\.conversationId, { v with messages = v\.messages + 1; lastBlock = c\.block });$|    RowStore.put<CR.Conversation>(c.chat.conversations, CR.conversation, f.conversationId, { v with messages = v.messages; lastBlock = c.block });|' src/ChatFold.mo

# the word's author is the caller
try chat-speaker-not-the-caller Chat \
  sed -i 's|^    RowStore\.put<CR\.Message>(c\.chat\.messages, CR\.message, id, { companyId; conversationId; speaker; sender = c\.caller; body; day = c\.day; block = c\.block });$|    RowStore.put<CR.Message>(c.chat.messages, CR.message, id, { companyId; conversationId; speaker; sender = Principal.fromText("aaaaa-aa"); body; day = c.day; block = c.block });|' src/ChatFold.mo

# closed twice
try chat-closed-twice Chat \
  sed -i 's|^    if (v\.state == #closed) return #err(#conversationClosed { conversationId });$|    if (false) return #err(#conversationClosed { conversationId });|' src/ChatFold.mo

# CLOSED BY THE VISITOR OR THE HOLDING OPERATOR ALONE
try chat-anybody-closes Chat \
  sed -i 's|^    if (not (c\.caller == v\.visitor or (v\.state == #open and c\.caller == v\.operator))) return #err(#notAParty { conversationId });$|    if (false) return #err(#notAParty { conversationId });|' src/ChatFold.mo

# a close under the wrong company
try chat-close-under-the-wrong-company Chat \
  sed -i 's|^    if (v\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = v\.companyId });$|    if (false) return #err(#wrongCompany { expected = companyId; found = v.companyId });|' src/ChatFold.mo

# THE RATING IS THE VISITOR'S ALONE
try chat-rating-not-the-visitors Chat \
  sed -i 's|^    if (c\.caller != v\.visitor) return #err(#notTheVisitor { conversationId = f\.conversationId; visitor = v\.visitor });$|    if (false) return #err(#notTheVisitor { conversationId = f.conversationId; visitor = v.visitor });|' src/ChatFold.mo

# a rating waits for the close
try chat-rating-an-open-conversation Chat \
  sed -i 's|^    if (v\.state != #closed) return #err(#conversationNotClosed { conversationId = f\.conversationId });$|    if (false) return #err(#conversationNotClosed { conversationId = f.conversationId });|' src/ChatFold.mo

# RATED ONCE
try chat-rated-twice Chat \
  sed -i 's|^    if (v\.rating != #unrated) return #err(#alreadyRated { conversationId = f\.conversationId });$|    if (false) return #err(#alreadyRated { conversationId = f.conversationId });|' src/ChatFold.mo

# a rating of nothing
try chat-rating-of-nothing Chat \
  sed -i 's|^    if (f\.rating == #unrated) return #err(#ratingRequired);$|    if (false) return #err(#ratingRequired);|' src/ChatFold.mo

# A WITHDRAWN OPERATOR TAKES NO MORE
try chat-withdrawn-operator-takes Chat \
  sed -i 's|^    switch (operatorOf(st, companyId, p)) { case (?(_, o)) o\.isEnrolled; case null false }$|    switch (operatorOf(st, companyId, p)) { case (?(_, o)) true; case null false }|' src/ChatFold.mo

# THE QUEUE IS THE WAITING ALONE
try chat-queue-holds-the-taken Chat \
  sed -i 's|^        keyOf = func(id : Nat, x : Conversation) : ?Blob { if (x\.state == #waiting) ?PR\.pairKey(x\.companyId, id) else null } },$|        keyOf = func(id : Nat, x : Conversation) : ?Blob { ?PR.pairKey(x.companyId, id) } },|' src/ChatRows.mo

# an open conversation is live too
try chat-open-conversation-not-live Chat \
  sed -i 's|^        keyOf = func(_id : Nat, x : Conversation) : ?Blob { if (x\.state != #closed) ?subjectKey(x\.companyId, x\.visitor) else null } },$|        keyOf = func(_id : Nat, x : Conversation) : ?Blob { if (x.state == #waiting) ?subjectKey(x.companyId, x.visitor) else null } },|' src/ChatRows.mo

# ── marketing automation ─────────────────────────────────────────────────────

# Not injected, and why: a workflow over another company's segment (the state hands the fold only the
# company's own segments, so the check cannot be reached); a send without a template (the usable-template
# check refuses it too); the check-only twin of a tag act and the wave's one-address-one-copy (the battery
# has no failing tag act and no duplicate address in a wave - stated, not claimed).

# A WORKFLOW BY SOMEBODY WHO IS NOT A MEMBER
# Not injected, and why: auto-stranger-declares - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# a workflow needs a name
try auto-name-required Automation \
  sed -i 's|^    if (Text\.size(f\.name) == 0) return #err(#nameRequired { what = "a workflow'\''s name" });$|    if (false) return #err(#nameRequired { what = "a workflow'\''s name" });|' src/AutoFold.mo

# a step by a stranger
# Not injected, and why: auto-stranger-adds-a-step - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# a run opened by a stranger
# Not injected, and why: auto-stranger-runs - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# A STEP ADDED AFTER ACTIVATION
try auto-step-on-a-live-workflow Automation \
  sed -i 's|^    if (w\.state != #draft) return #err(#workflowNotDraft { workflowId; state = w\.state });$|    if (false) return #err(#workflowNotDraft { workflowId; state = w.state });|' src/AutoFold.mo

# THE SEVENTEENTH STEP
try auto-too-many-steps Automation \
  sed -i 's|^    if (w\.steps >= MAX_STEPS) return #err(#tooManySteps { max = MAX_STEPS });$|    if (false) return #err(#tooManySteps { max = MAX_STEPS });|' src/AutoFold.mo

# A DELAY BEYOND A YEAR
try auto-delay-unbounded Automation \
  sed -i 's|^    if (f\.delayDays > MAX_DELAY) return #err(#delayTooLong { days = f\.delayDays; max = MAX_DELAY });$|    if (false) return #err(#delayTooLong { days = f.delayDays; max = MAX_DELAY });|' src/AutoFold.mo

# a send names a template and no tag
try auto-send-names-a-tag Automation \
  sed -i 's|^        if (f\.mailingId == 0 or Text\.size(f\.tag) > 0) return #err(#stepNeedsMailing);$|        if (false) return #err(#stepNeedsMailing);|' src/AutoFold.mo

# a send of a template that is not usable
try auto-template-not-checked Automation \
  sed -i 's|^        if (not c\.templateUsable(f\.companyId, f\.mailingId)) return #err(#templateNotUsable { mailingId = f\.mailingId });$|        if (false) return #err(#templateNotUsable { mailingId = f.mailingId });|' src/AutoFold.mo

# A TAG STEP WITHOUT A TAG
try auto-tag-step-without-a-tag Automation \
  sed -i 's|^        if (f\.mailingId != 0 or Text\.size(f\.tag) == 0) return #err(#stepNeedsTag);$|        if (false) return #err(#stepNeedsTag);|' src/AutoFold.mo

# a tag beyond the field
try auto-tag-beyond-the-field Automation \
  sed -i 's|^        let ?field = CR\.tagField(f\.tag) else return #err(#tagDoesNotFit { tag = f\.tag });$|        let field = switch (CR.tagField(f.tag)) { case (?x) x; case null noTag() };|' src/AutoFold.mo

# A CONDITION ON A SEND THAT IS NOT THERE
try auto-condition-without-a-send Automation \
  sed -i 's|^      if (not previousIsASend) return #err(#conditionNeedsASend { ordinal });$|      if (false) return #err(#conditionNeedsASend { ordinal });|' src/AutoFold.mo

# ACTIVATING A WORKFLOW WITH NO STEP
try auto-activate-with-no-step Automation \
  sed -i 's|^    if (w\.steps == 0) return #err(#noSteps { workflowId });$|    if (false) return #err(#noSteps { workflowId });|' src/AutoFold.mo

# ACTIVATION IS A SECOND PERSON'S
try auto-declarer-activates Automation \
  sed -i 's|^    if (c\.caller == w\.declaredBy) return #err(#sameDeclarer { subject = c\.caller });$|    if (false) return #err(#sameDeclarer { subject = c.caller });|' src/AutoFold.mo

# A WORKFLOW WHOSE TEMPLATE IS NO LONGER A DRAFT IS NOT ACTIVATED
try auto-activation-ignores-the-template Automation \
  sed -i 's|^      if (s\.kind == #sendMailing and not c\.templateUsable(companyId, s\.mailingId)) return #err(#templateNotUsable { mailingId = s\.mailingId });$|      if (false) return #err(#templateNotUsable { mailingId = s.mailingId });|' src/AutoFold.mo

# THE SEGMENT'S RULE FIXED AT ACTIVATION
try auto-rule-not-fixed Automation \
  sed -i 's|^    RowStore\.put<AR\.Workflow>(c\.auto\.workflows, AR\.workflow, workflowId, { w with state = #active; ruleHash = seg\.ruleHash; activatedBy = c\.caller; lastBlock = c\.block });$|    RowStore.put<AR.Workflow>(c.auto.workflows, AR.workflow, workflowId, { w with state = #active; ruleHash = w.ruleHash; activatedBy = c.caller; lastBlock = c.block });|' src/AutoFold.mo

# A CLOSED WORKFLOW RUNS NO MORE
try auto-run-on-a-closed-workflow Automation \
  sed -i 's|^    if (w\.state != #active) return #err(#workflowNotActive { workflowId; state = w\.state });$|    if (false) return #err(#workflowNotActive { workflowId; state = w.state });|' src/AutoFold.mo

# a run through a day that has not come
try auto-horizon-not-reached Automation \
  sed -i 's|^    if (throughDay > c\.day) return #err(#horizonNotReached { throughDay; day = c\.day });$|    if (false) return #err(#horizonNotReached { throughDay; day = c.day });|' src/AutoFold.mo

# one running run per kind
try auto-two-runs Automation \
  sed -i 's|^    switch (runningRun(c\.auto, workflowId, kind)) { case (?(runId, _)) return #err(#runAlreadyRunning { workflowId; runId }); case null {} };$|    ignore runningRun(c.auto, workflowId, kind);|' src/AutoFold.mo

# A STEP SLICE OF AN ENROLMENT RUN
try auto-slice-of-the-wrong-kind Automation \
  sed -i 's|^    if (run\.kind != kind) return #err(#noSuchRun { runId });$|    if (false) return #err(#noSuchRun { runId });|' src/AutoFold.mo

# a slice of a run that is done
try auto-slice-of-a-done-run Automation \
  sed -i 's|^    if (not run\.isRunning) return #err(#runNotRunning { runId });$|    if (false) return #err(#runNotRunning { runId });|' src/AutoFold.mo

# AN AUDIENCE THAT MOVED
try auto-audience-moved-unnoticed Automation \
  sed -i 's|^    if (seg\.ruleHash != w\.ruleHash) return #err(#audienceMoved { workflowId = run\.workflowId });$|    if (false) return #err(#audienceMoved { workflowId = run.workflowId });|' src/AutoFold.mo

# THE SEGMENT ADMITS
try auto-admits-anybody Automation \
  sed -i 's|^      if (c\.admits(seg, leadId, l) and participantOf(c\.auto, run\.workflowId, leadId) == null) List\.add(admitted, leadId);$|      if (participantOf(c.auto, run.workflowId, leadId) == null) List.add(admitted, leadId);|' src/AutoFold.mo

# ENROLLED ONCE
try auto-enrolled-twice Automation \
  sed -i 's|^      if (c\.admits(seg, leadId, l) and participantOf(c\.auto, run\.workflowId, leadId) == null) List\.add(admitted, leadId);$|      if (c.admits(seg, leadId, l)) List.add(admitted, leadId);|' src/AutoFold.mo

# due for the first step so many days from today
try auto-due-not-the-delay Automation \
  sed -i 's|^        companyId; workflowId = run\.workflowId; leadId; nextStep = 1; dueDay = c\.day + first\.delayDays; state = #active;$|        companyId; workflowId = run.workflowId; leadId; nextStep = 1; dueDay = c.day + first.delayDays + 1; state = #active;|' src/AutoFold.mo

# the enrolment run ends with the last page
try auto-enrolment-runs-forever Automation \
  sed -i 's|^      run with cursor = last; scanned = run\.scanned + page\.size(); acted = run\.acted + added; isRunning = page\.size() == limit; lastBlock = c\.block });$|      run with cursor = last; scanned = run.scanned + page.size(); acted = run.acted + added; isRunning = true; lastBlock = c.block });|' src/AutoFold.mo

# THE CONDITION ON THE OPEN
try auto-condition-ignored Automation \
  sed -i 's|^      case (#ifOpened) c\.leadEngaged(companyId, p\.lastMailingId, p\.leadId, #open);$|      case (#ifOpened) true;|' src/AutoFold.mo

# A LEAD ARCHIVED LEAVES
try auto-gone-lead-fires Automation \
  sed -i 's|^      let alive = switch (c\.leadOf(p\.leadId)) { case (?l) l\.companyId == companyId and not l\.isArchived; case null false };$|      let alive = true;|' src/AutoFold.mo

# NOT MET, THE PARTICIPANT LEAVES
try auto-not-met-does-not-leave Automation \
  sed -i 's|^        RowStore\.put<AR\.Participant>(c\.auto\.participants, AR\.participant, pl\.pid, { pl\.p with state = #exited; lastBlock = c\.block });$|        RowStore.put<AR.Participant>(c.auto.participants, AR.participant, pl.pid, { pl.p with lastBlock = c.block });|' src/AutoFold.mo

# every step counts what it fired for
try auto-step-not-counted Automation \
  sed -i 's|^      if (n > 0) RowStore\.put<AR\.Step>(c\.auto\.steps, AR\.step, sid, { s with fired = s\.fired + n; lastBlock = c\.block });$|      if (n > 0) RowStore.put<AR.Step>(c.auto.steps, AR.step, sid, { s with fired = s.fired; lastBlock = c.block });|' src/AutoFold.mo

# AFTER THE LAST STEP THE PARTICIPANT IS DONE
try auto-last-step-not-done Automation \
  sed -i 's|^        if (pl\.s\.ordinal >= w\.steps) {$|        if (false) {|' src/AutoFold.mo

# the next step due so many days on
try auto-next-due-not-the-delay Automation \
  sed -i 's|^          RowStore\.put<AR\.Participant>(c\.auto\.participants, AR\.participant, pl\.pid, { pl\.p with nextStep = pl\.s\.ordinal + 1; dueDay = c\.day + next\.delayDays; lastMailingId; lastBlock = c\.block });$|          RowStore.put<AR.Participant>(c.auto.participants, AR.participant, pl.pid, { pl.p with nextStep = pl.s.ordinal + 1; dueDay = c.day; lastMailingId; lastBlock = c.block });|' src/AutoFold.mo

# the participant's copy is in the wave the step raised
try auto-wave-not-remembered Automation \
  sed -i 's|^          RowStore\.put<AR\.Participant>(c\.auto\.participants, AR\.participant, pl\.pid, { pl\.p with nextStep = pl\.s\.ordinal + 1; dueDay = c\.day + next\.delayDays; lastMailingId; lastBlock = c\.block });$|          RowStore.put<AR.Participant>(c.auto.participants, AR.participant, pl.pid, { pl.p with nextStep = pl.s.ordinal + 1; dueDay = c.day + next.delayDays; lastMailingId = pl.p.lastMailingId; lastBlock = c.block });|' src/AutoFold.mo

# THE RUN ENDS WHEN NOTHING IS DUE
try auto-run-ends-early Automation \
  sed -i 's|^    let stillDue = due(c\.auto, run\.workflowId, run\.throughDay, 1)\.size() > 0;$|    let stillDue = false;|' src/AutoFold.mo

# AN ACTIVATED WORKFLOW OWNS ITS TEMPLATES
try auto-template-not-owned Automation \
  sed -i 's|^        case (?w) { if (w\.companyId == companyId and w\.state != #draft) return true };$|        case (?w) { if (false) return true };|' src/AutoFold.mo

# what a step run walks is the active alone
try auto-exited-still-due Automation \
  sed -i 's|^        keyOf = func(id : Nat, x : Participant) : ?Blob { if (x\.state == #active) ?dueKey(x\.workflowId, x\.dueDay, id) else null } },$|        keyOf = func(id : Nat, x : Participant) : ?Blob { ?dueKey(x.workflowId, x.dueDay, id) } },|' src/AutoRows.mo

# A TEMPLATE LAUNCHED, PLANNED, AMENDED AND CANCELLED BY NOBODY
try auto-template-launched-by-hand Automation \
  sed -i 's|^    if (c\.isTemplate(companyId, mailingId)) return ?(#ownedByWorkflow { mailingId });$|    if (false) return ?(#ownedByWorkflow { mailingId });|' src/CrmFold.mo

# THE WAVE READS THE SUPPRESSION LIST
try auto-wave-ignores-suppression Automation \
  sed -i 's|^                let suppressedHere = switch (activeSuppression(c, companyId, key)) { case (?_) true; case null false };$|                let suppressedHere = false;|' src/CrmFold.mo

# THE WAVE'S CONTENT IS THE TEMPLATE'S
try auto-wave-content-not-the-templates Automation \
  sed -i 's|^      contentHash = contentHash(emailFrom, replyTo, subject, bodyHtml); rollingHash = rolling;$|      contentHash = zero32(); rollingHash = rolling;|' src/CrmFold.mo

# THE WAVE IS A MAILING READY AT ONCE
try auto-wave-not-ready Automation \
  sed -i 's|^      state = if (n == suppressed) #done else #ready;$|      state = #draft;|' src/CrmFold.mo

# ── SMS marketing ────────────────────────────────────────────────────────────

# Not injected, and why: a text mailing at a company that does not exist (the membership check refuses it
# too); a segment that is not there (the state hands the fold only live segments of the company, so the
# segment check and the company check are one); the wrong-company checks of amend, launch, plan, claim,
# results and replies (one shared `mailingOf`, whose membership check refuses a non-member of the other
# company too); a claim of nothing (the kernel's page would still be asked for one).

# A TEXT MAILING BY SOMEBODY WHO IS NOT A MEMBER
# Not injected, and why: sms-stranger-creates - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# a text mailing needs a body
try sms-body-required Sms \
  sed -i 's|^    if (Text\.size(f\.body) == 0) return ?#bodyRequired;$|    if (false) return ?#bodyRequired;|' src/SmsFold.mo

# ONE SEGMENT OF TEXT
try sms-body-unbounded Sms \
  sed -i 's|^    if (Text\.size(f\.body) > BODY_MAX) return ?#bodyTooLong { size = Text\.size(f\.body); max = BODY_MAX };$|    if (false) return ?#bodyTooLong { size = Text.size(f.body); max = BODY_MAX };|' src/SmsFold.mo

# the attempt bound between 1 and 255
try sms-attempt-bound-unchecked Sms \
  sed -i 's|^    if (f\.attemptBound == 0 or f\.attemptBound > 255) return ?#attemptBoundOutOfRange { bound = f\.attemptBound };$|    if (false) return ?#attemptBoundOutOfRange { bound = f.attemptBound };|' src/SmsFold.mo

# a day that fits
try sms-day-unchecked Sms \
  sed -i 's|^    if (not dayFits(f\.scheduledDay)) return ?#dayTooLarge { day = f\.scheduledDay };$|    if (false) return ?#dayTooLarge { day = f.scheduledDay };|' src/SmsFold.mo

# THE BODY APPROVED IS THE BODY THAT GOES OUT
try sms-content-locked Sms \
  sed -i 's|^    if (m\.state != #draft) return #err(#contentLocked { mailingId });$|    if (false) return #err(#contentLocked { mailingId });|' src/SmsFold.mo

# a launch of a draft alone
try sms-launch-twice Sms \
  sed -i 's|^    if (m\.state != #draft) return #err(#mailingNotInState { mailingId; state = m\.state; wanted = "a draft" });$|    if (false) return #err(#mailingNotInState { mailingId; state = m.state; wanted = "a draft" });|' src/SmsFold.mo

# A LAUNCH DECLARES THE LIST'S SIZE
try sms-launch-declares-nothing Sms \
  sed -i 's|^    if (expectedRecipients == 0) return #err(#expectedRecipientsZero);$|    if (false) return #err(#expectedRecipientsZero);|' src/SmsFold.mo

# THE BODY FIXED BY ITS HASH AT LAUNCH
try sms-body-not-fixed Sms \
  sed -i 's|^      m with state = #planning; contentHash = contentHash(body); ruleHash; rollingHash = zero32(); expected = expectedRecipients;$|      m with state = #planning; contentHash = zero32(); ruleHash; rollingHash = zero32(); expected = expectedRecipients;|' src/SmsFold.mo

# a plan of a mailing that is planning
try sms-plan-of-a-draft Sms \
  sed -i 's|^    if (m\.state != #planning) return #err(#mailingNotInState { mailingId; state = m\.state; wanted = "planning" });$|    if (false) return #err(#mailingNotInState { mailingId; state = m.state; wanted = "planning" });|' src/SmsFold.mo

# AN AUDIENCE THAT MOVED SINCE THE LAUNCH
try sms-audience-moved-unnoticed Sms \
  sed -i 's|^      if (s\.ruleHash != m\.ruleHash) return #err(#audienceMoved { mailingId });$|      if (false) return #err(#audienceMoved { mailingId });|' src/SmsFold.mo

# the segment admits
try sms-segment-ignored Sms \
  sed -i 's|^      let admitted = switch (seg) { case null not l\.isArchived; case (?s) c\.admits(s, leadId, l) };$|      let admitted = not l.isArchived;|' src/SmsFold.mo

# a number that is not one is left out
try sms-bad-number-placed Sms \
  sed -i 's|^        switch (SR\.normaliseNumber(raw)) {$|        switch (if (Text.size(raw) == 0) null else ?raw) {|' src/SmsFold.mo

# ONE NUMBER ONE COPY
try sms-two-spellings-two-copies Sms \
  sed -i 's|^            if (not already and not seenInSlice) List\.add(chosen, { leadId; number; key; suppressedHere = isSuppressed(c\.sms, companyId, key) });$|            if (not already) List.add(chosen, { leadId; number; key; suppressedHere = isSuppressed(c.sms, companyId, key) });|' src/SmsFold.mo

# A SUPPRESSED NUMBER PLACED SUPPRESSED
try sms-suppression-not-read-at-plan Sms \
  sed -i 's|^            if (not already and not seenInSlice) List\.add(chosen, { leadId; number; key; suppressedHere = isSuppressed(c\.sms, companyId, key) });$|            if (not already and not seenInSlice) List.add(chosen, { leadId; number; key; suppressedHere = false });|' src/SmsFold.mo

# THE LIST HELD TO THE COUNT THE LAUNCHER DECLARED
try sms-count-not-held Sms \
  sed -i 's|^    if (total > m\.expected or (lastPage and total != m\.expected)) return #err(#planCountMismatch { mailingId; expected = m\.expected; found = total });$|    if (false) return #err(#planCountMismatch { mailingId; expected = m.expected; found = total });|' src/SmsFold.mo

# the list's hash chained in lead order
try sms-list-not-chained Sms \
  sed -i 's|^      rolling := chain(rolling, x\.key);$|      rolling := rolling;|' src/SmsFold.mo

# the list ready at the last page
try sms-list-never-ready Sms \
  sed -i 's|^      m with cursor = if (lastPage) 0 else last; planned = total; suppressed; rollingHash = rolling; state = if (lastPage) #ready else #planning; lastBlock = c\.block });$|      m with cursor = if (lastPage) 0 else last; planned = total; suppressed; rollingHash = rolling; state = #planning; lastBlock = c.block });|' src/SmsFold.mo

# a claim within the batch bound
try sms-claim-beyond-the-batch Sms \
  sed -i 's|^    if (limit > MAX_SEND_BATCH) return #err(#sliceTooLarge { asked = limit; max = MAX_SEND_BATCH });$|    if (false) return #err(#sliceTooLarge { asked = limit; max = MAX_SEND_BATCH });|' src/SmsFold.mo

# A CLAIM BOUND TO THE LIST BY ITS HASH
try sms-claim-not-bound-to-the-list Sms \
  sed -i 's|^    if (m\.rollingHash != planHash) return #err(#planHashMismatch { mailingId });$|    if (false) return #err(#planHashMismatch { mailingId });|' src/SmsFold.mo

# THE SCHEDULE IS THE CALENDAR'S
try sms-claim-before-the-day Sms \
  sed -i 's|^    if (c\.day < m\.scheduledDay) return #err(#notYetScheduled { mailingId; scheduledDay = m\.scheduledDay; day = c\.day });$|    if (false) return #err(#notYetScheduled { mailingId; scheduledDay = m.scheduledDay; day = c.day });|' src/SmsFold.mo

# THE SUPPRESSION LIST READ AGAIN AT THE CLAIM
try sms-claim-ignores-the-late-stop Sms \
  sed -i 's|^    for ((id, r) in pending\.vals()) { if (isSuppressed(c\.sms, companyId, r\.numberKey)) List\.add(silenced, (id, r)) else List\.add(claimable, (id, r)) };$|    for ((id, r) in pending.vals()) { List.add(claimable, (id, r)) };|' src/SmsFold.mo

# done when every copy is terminal
try sms-done-with-copies-in-flight Sms \
  sed -i 's|^      if (not noneIn(c\.sms, companyId, mailingId, #sending)) return #err(#mailingNotInState { mailingId; state = m\.state; wanted = "terminal: copies are still in flight" });$|      if (false) return #err(#mailingNotInState { mailingId; state = m.state; wanted = "terminal: copies are still in flight" });|' src/SmsFold.mo

# results of one shape
try sms-results-of-another-shape Sms \
  sed -i 's|^    if (f\.ok\.size() != f\.recipientIds\.size() or f\.reasons\.size() != f\.recipientIds\.size()) return #err(#resultShapeMismatch { recipients = f\.recipientIds\.size(); given = f\.ok\.size() });$|    if (false) return #err(#resultShapeMismatch { recipients = f.recipientIds.size(); given = f.ok.size() });|' src/SmsFold.mo

# A RESULT FOR A COPY IN FLIGHT ALONE
try sms-result-for-a-copy-not-in-flight Sms \
  sed -i 's|^      if (r\.state != #sending) return #err(#recipientNotSending { recipientId = rid; state = r\.state });$|      if (false) return #err(#recipientNotSending { recipientId = rid; state = r.state });|' src/SmsFold.mo

# FAILED FOR GOOD AT THE BOUND
try sms-failure-costs-nothing Sms \
  sed -i 's|^        let terminal = attempts >= m\.attemptBound;$|        let terminal = false;|' src/SmsFold.mo

# a reply of nothing
try sms-reply-of-nothing Sms \
  sed -i 's|^      if (reply == #none) return #err(#replyOfNothing { recipientId = rid });$|      if (false) return #err(#replyOfNothing { recipientId = rid });|' src/SmsFold.mo

# A REPLY FOR A COPY SENT ALONE
try sms-reply-for-a-copy-never-sent Sms \
  sed -i 's|^      if (r\.state != #sent) return #err(#recipientNotSent { recipientId = rid; state = r\.state });$|      if (false) return #err(#recipientNotSent { recipientId = rid; state = r.state });|' src/SmsFold.mo

# ONE REPLY PER COPY
try sms-reply-twice Sms \
  sed -i 's|^      if (r\.reply != #none) return #err(#replyRecorded { recipientId = rid; reply = r\.reply });$|      if (false) return #err(#replyRecorded { recipientId = rid; reply = r.reply });|' src/SmsFold.mo

# STOP SUPPRESSES THE NUMBER
try sms-stop-not-a-suppression Sms \
  sed -i 's|^        case (#optOut) { optedOut += 1; suppressByWord(c, f\.companyId, r, #unsubscribed) };$|        case (#optOut) { optedOut += 1 };|' src/SmsFold.mo

# AN UNREACHABLE NUMBER IS SUPPRESSED
try sms-unreachable-not-a-suppression Sms \
  sed -i 's|^        case (#undeliverable) { suppressByWord(c, f\.companyId, r, #bounced) };$|        case (#undeliverable) {};|' src/SmsFold.mo

# a live mailing alone is cancelled
try sms-cancel-a-done-mailing Sms \
  sed -i 's|^    if (m\.state == #done or m\.state == #cancelled) return #err(#mailingNotInState { mailingId; state = m\.state; wanted = "live" });$|    if (false) return #err(#mailingNotInState { mailingId; state = m.state; wanted = "live" });|' src/SmsFold.mo

# a suppression of a number in one form alone
try sms-suppress-a-non-number Sms \
  sed -i 's|^    let ?normalised = SR\.normaliseNumber(number) else return #err(#numberInvalid { number });$|    let normalised = switch (SR.normaliseNumber(number)) { case (?n) n; case null number };|' src/SmsFold.mo

# suppressed once
try sms-suppressed-twice Sms \
  sed -i 's|^        if (s\.isActive) return #err(#alreadySuppressed { number = normalised });$|        if (false) return #err(#alreadySuppressed { number = normalised });|' src/SmsFold.mo

# released once
try sms-released-twice Sms \
  sed -i 's|^    if (not s\.isActive) return #err(#notSuppressed { number = normalised });$|    if (false) return #err(#notSuppressed { number = normalised });|' src/SmsFold.mo

# `+` or `00` the country-code mark
try sms-plus-not-the-mark Sms \
  sed -i 's|^      if (not Text\.startsWith(digits, #text "00")) return null;$|      if (false) return null;|' src/SmsRows.mo

# eight to fifteen digits
try sms-digits-unbounded Sms \
  sed -i 's|^    if (n < 8 or n > 15) return null;$|    if (false) return null;|' src/SmsRows.mo

# ── social marketing ─────────────────────────────────────────────────────────

# Not injected, and why: an account at a company that does not exist (the membership check refuses it too);
# the wrong-company checks behind the shared `liveAccount`/`scheduledPost` helpers and the result's (the
# membership of the other company refuses them too); the image document's own checks (`SiteFold.pageDocument`,
# `readBytes`), which the website slice removes.

# AN ACCOUNT BY SOMEBODY WHO IS NOT A MEMBER
# Not injected, and why: social-stranger-connects - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# the relay's word is a member's
# Not injected, and why: social-stranger-speaks-for-the-relay - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# an account needs a handle
try social-handle-required Social \
  sed -i 's|^    if (Text\.size(f\.handle) == 0) return #err(#handleRequired);$|    if (false) return #err(#handleRequired);|' src/SocialFold.mo

# ONE ACCOUNT PER CHANNEL
try social-two-accounts-one-channel Social \
  sed -i 's|^    switch (accountOf(c\.social, f\.companyId, f\.channel)) {$|    switch (null : ?(Nat, SOR.SocialAccount)) {|' src/SocialFold.mo

# a disconnection, a post or a claim is a member's
# Not injected, and why: social-stranger-on-an-account - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# an amendment or a cancel is a member's
# Not injected, and why: social-stranger-amends - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# A DISCONNECTED ACCOUNT POSTS NO MORE
try social-disconnected-account-posts Social \
  sed -i 's|^    if (not a\.isActive) return #err(#accountInactive { accountId });$|    if (false) return #err(#accountInactive { accountId });|' src/SocialFold.mo

# a post needs a text
try social-body-required Social \
  sed -i 's|^    if (Text\.size(f\.body) == 0) return #err(#bodyRequired);$|    if (false) return #err(#bodyRequired);|' src/SocialFold.mo

# THE CHANNEL'S OWN BOUND
try social-channel-bound-ignored Social \
  sed -i 's|^    if (Text\.size(f\.body) > max) return #err(#bodyTooLong { channel = a\.channel; size = Text\.size(f\.body); max });$|    if (false) return #err(#bodyTooLong { channel = a.channel; size = Text.size(f.body); max });|' src/SocialFold.mo

# a day that fits
try social-day-unchecked Social \
  sed -i 's|^    if (not dayFits(f\.scheduledDay)) return #err(#dayTooLarge { day = f\.scheduledDay });$|    if (false) return #err(#dayTooLarge { day = f.scheduledDay });|' src/SocialFold.mo

# A DAY THAT HAS PASSED
try social-day-passed Social \
  sed -i 's|^    if (f\.scheduledDay < c\.day) return #err(#dayPassed { scheduledDay = f\.scheduledDay; day = c\.day });$|    if (false) return #err(#dayPassed { scheduledDay = f.scheduledDay; day = c.day });|' src/SocialFold.mo

# AN IMAGE THAT IS NOT ITS OWN PLAINTEXT
try social-image-fingerprint-not-checked Social \
  sed -i 's|^    if (SFold\.hexOf(fingerprint) != ev\.plainHash) return #err(#site(#fingerprintDisagrees { declared = ev\.plainHash; computed = SFold\.hexOf(fingerprint) }));$|    if (false) return #err(#site(#fingerprintDisagrees { declared = ev.plainHash; computed = SFold.hexOf(fingerprint) }));|' src/SocialFold.mo

# THE AUTHOR IS THE CALLER
try social-author-not-the-caller Social \
  sed -i 's|^      attempts = 0; remoteId = TA\.EMPTY; reason = TA\.EMPTY; author = c\.caller; postedDay = 0; claimedBlock = 0; lastBlock = c\.block });$|      attempts = 0; remoteId = TA.EMPTY; reason = TA.EMPTY; author = Principal.fromText("aaaaa-aa"); postedDay = 0; claimedBlock = 0; lastBlock = c.block });|' src/SocialFold.mo

# the account counts its posts
try social-account-does-not-count Social \
  sed -i 's|^    RowStore\.put<SOR\.SocialAccount>(c\.social\.accounts, SOR\.socialAccount, f\.accountId, { a with posts = a\.posts + 1; lastBlock = c\.block });$|    RowStore.put<SOR.SocialAccount>(c.social.accounts, SOR.socialAccount, f.accountId, { a with posts = a.posts; lastBlock = c.block });|' src/SocialFold.mo

# AMENDED AND CANCELLED WHILE SCHEDULED ALONE
try social-amend-a-claimed-post Social \
  sed -i 's|^    if (p\.state != #scheduled) return #err(#postNotScheduled { postId; state = p\.state });$|    if (false) return #err(#postNotScheduled { postId; state = p.state });|' src/SocialFold.mo

# amended on its own account
try social-amend-onto-another-account Social \
  sed -i 's|^    if (f\.accountId != p\.accountId) return #err(#noSuchPost { postId });$|    if (false) return #err(#noSuchPost { postId });|' src/SocialFold.mo

# NOTHING BEFORE ITS DAY
try social-nothing-due-given Social \
  sed -i 's|^    let ?(postId, p) = nextDue(c\.social, accountId, c\.day) else return #err(#nothingDue { accountId });$|    let ?(postId, p) = (switch (nextDue(c.social, accountId, c.day)) { case (?x) ?x; case null nextDue(c.social, accountId, F.pow256(W.DAY) - 1) }) else return #err(#nothingDue { accountId });|' src/SocialFold.mo

# the attempt counted
try social-attempt-not-counted Social \
  sed -i 's|^    RowStore\.put<SOR\.SocialPost>(c\.social\.posts, SOR\.socialPost, postId, { p with state = #claimed; attempts = p\.attempts + 1; claimedBlock = c\.block; lastBlock = c\.block });$|    RowStore.put<SOR.SocialPost>(c.social.posts, SOR.socialPost, postId, { p with state = #claimed; attempts = p.attempts; claimedBlock = c.block; lastBlock = c.block });|' src/SocialFold.mo

# A WORD ON A CLAIMED POST ALONE
try social-word-on-a-post-not-claimed Social \
  sed -i 's|^    if (p\.state != #claimed) return #err(#postNotClaimed { postId = f\.postId; state = p\.state });$|    if (false) return #err(#postNotClaimed { postId = f.postId; state = p.state });|' src/SocialFold.mo

# POSTED UNDER THE CHANNEL'S ID
try social-posted-without-an-id Social \
  sed -i 's|^    if (f\.posted and Text\.size(f\.remoteId) == 0) return #err(#remoteIdRequired);$|    if (false) return #err(#remoteIdRequired);|' src/SocialFold.mo

# posted on the calendar's day
try social-posted-day-not-the-calendars Social \
  sed -i 's|^      RowStore\.put<SOR\.SocialPost>(c\.social\.posts, SOR\.socialPost, f\.postId, { p with state = #posted; remoteId; reason = TA\.EMPTY; postedDay = c\.day; lastBlock = c\.block });$|      RowStore.put<SOR.SocialPost>(c.social.posts, SOR.socialPost, f.postId, { p with state = #posted; remoteId; reason = TA.EMPTY; postedDay = c.day + 1; lastBlock = c.block });|' src/SocialFold.mo

# FAILED FOR GOOD AT THE THIRD ATTEMPT
try social-fails-for-ever Social \
  sed -i 's|^      let terminal = p\.attempts >= ATTEMPT_BOUND;$|      let terminal = false;|' src/SocialFold.mo

# BACK TO THE QUEUE until the bound
try social-failed-at-once Social \
  sed -i 's|^      RowStore\.put<SOR\.SocialPost>(c\.social\.posts, SOR\.socialPost, f\.postId, { p with state = if (terminal) #failed else #scheduled; reason; lastBlock = c\.block });$|      RowStore.put<SOR.SocialPost>(c.social.posts, SOR.socialPost, f.postId, { p with state = #failed; reason; lastBlock = c.block });|' src/SocialFold.mo

# THE QUEUE IS THE SCHEDULED ALONE
try social-queue-holds-the-posted Social \
  sed -i 's|^        keyOf = func(id : Nat, x : SocialPost) : ?Blob { if (x\.state == #scheduled) ?dueKey(x\.accountId, x\.scheduledDay, id) else null } },$|        keyOf = func(id : Nat, x : SocialPost) : ?Blob { if (x.state != #cancelled) ?dueKey(x.accountId, x.scheduledDay, id) else null } },|' src/SocialRows.mo

# THE OLDEST DUE BY ITS DAY
try social-queue-not-by-day Social \
  sed -i 's|^        keyOf = func(id : Nat, x : SocialPost) : ?Blob { if (x\.state == #scheduled) ?dueKey(x\.accountId, x\.scheduledDay, id) else null } },$|        keyOf = func(id : Nat, x : SocialPost) : ?Blob { if (x.state == #scheduled) ?dueKey(x.accountId, 0, id) else null } },|' src/SocialRows.mo

# X's bound is 280
try social-x-unbounded Social \
  sed -i 's|^  public func socialChannelBound(c : SocialChannel) : Nat { switch (c) { case (#x) 280; case (#facebook) 2_000; case (#linkedin) 3_000; case (#instagram) 2_200 } };$|  public func socialChannelBound(c : SocialChannel) : Nat { switch (c) { case (#x) 2_000; case (#facebook) 2_000; case (#linkedin) 3_000; case (#instagram) 2_200 } };|' src/Enums.mo

# connected again, standing again
try social-reconnection-stays-down Social \
  sed -i 's|^        RowStore\.put<SOR\.SocialAccount>(c\.social\.accounts, SOR\.socialAccount, id, { a with handle; isActive = true; connectedBy = c\.caller; lastBlock = c\.block });$|        RowStore.put<SOR.SocialAccount>(c.social.accounts, SOR.socialAccount, id, { a with handle; connectedBy = c.caller; lastBlock = c.block });|' src/SocialFold.mo

# disconnected, posting no more
try social-disconnect-disconnects-nobody Social \
  sed -i 's|^    RowStore\.put<SOR\.SocialAccount>(c\.social\.accounts, SOR\.socialAccount, accountId, { a with isActive = false; lastBlock = c\.block });$|    RowStore.put<SOR.SocialAccount>(c.social.accounts, SOR.socialAccount, accountId, { a with lastBlock = c.block });|' src/SocialFold.mo

# ── events ───────────────────────────────────────────────────────────────────

# Not injected, and why: an event at a company that does not exist (the membership check refuses it too); the
# wrong-company checks behind the shared `announced` helper (the membership of the other company refuses them
# too); a seat of nothing at the door (the seats check and the over-seats check would each refuse it); a ticket
# for no seat, to another company's partner or to a supplier - the order fold refuses each of those sales
# itself (an empty line, a partner of another company, a partner with no receivable), so the fold's own check
# is a second defence and cannot be removed alone.

# AN EVENT BY SOMEBODY WHO IS NOT A MEMBER
# Not injected, and why: events-stranger-announces - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# an amendment, a sale, a close, a cancel is a member's
# Not injected, and why: events-stranger-acts - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# an event needs a name
try events-name-required Events \
  sed -i 's|^    if (Text\.size(f\.name) == 0) return #err(#nameRequired { what = "an event'\''s name" });$|    if (false) return #err(#nameRequired { what = "an event'\''s name" });|' src/EventFold.mo

# an event needs a venue
try events-venue-required Events \
  sed -i 's|^    if (Text\.size(f\.venue) == 0) return #err(#nameRequired { what = "a venue" });$|    if (false) return #err(#nameRequired { what = "a venue" });|' src/EventFold.mo

# a day that fits
try events-day-unchecked Events \
  sed -i 's|^    if (not dayFits(f\.day)) return #err(#dayTooLarge { day = f\.day });$|    if (false) return #err(#dayTooLarge { day = f.day });|' src/EventFold.mo

# AN EVENT FOR A DAY THAT HAS PASSED
try events-day-passed Events \
  sed -i 's|^    if (f\.day < c\.day) return #err(#dayPassed { day = f\.day; today = c\.day });$|    if (false) return #err(#dayPassed { day = f.day; today = c.day });|' src/EventFold.mo

# an event has seats
try events-no-seats Events \
  sed -i 's|^    if (f\.capacity == 0) return #err(#capacityZero);$|    if (false) return #err(#capacityZero);|' src/EventFold.mo

# ANOTHER COMPANY'S CATEGORY
try events-category-of-another-company Events \
  sed -i 's|^    if (cat\.companyId != f\.companyId) return #err(#wrongCompany { expected = f\.companyId; found = cat\.companyId });$|    if (false) return #err(#wrongCompany { expected = f.companyId; found = cat.companyId });|' src/EventFold.mo

# A FREE EVENT CARRIES NOTHING OF A SALE: its category, its journal, its rate, its currency (a
# price of nothing is a members' event, so a priced ticket's category at no price is refused here)
try events-free-with-a-category Events \
  sed -i 's|^      if (f\.categoryId != 0) return #err(#freeEventHasNoSale { field = "category" });$|      if (false) return #err(#freeEventHasNoSale { field = "category" });|' src/EventFold.mo
try events-free-with-a-journal Events \
  sed -i 's|^      if (f\.journalId != 0) return #err(#freeEventHasNoSale { field = "journal" });$|      if (false) return #err(#freeEventHasNoSale { field = "journal" });|' src/EventFold.mo
try events-free-with-a-rate Events \
  sed -i 's|^      if (f\.taxRate != 0) return #err(#freeEventHasNoSale { field = "tax rate" });$|      if (false) return #err(#freeEventHasNoSale { field = "tax rate" });|' src/EventFold.mo
try events-free-with-a-currency Events \
  sed -i 's|^      if (Text\.size(f\.currency) != 0) return #err(#freeEventHasNoSale { field = "currency" });$|      if (false) return #err(#freeEventHasNoSale { field = "currency" });|' src/EventFold.mo

# the tax rate bounded
try events-rate-unbounded Events \
  sed -i 's|^    if (f\.taxRate > MAX_TAX_RATE) return #err(#rateBound { value = f\.taxRate; max = MAX_TAX_RATE });$|    if (false) return #err(#rateBound { value = f.taxRate; max = MAX_TAX_RATE });|' src/EventFold.mo

# a ticket has a currency
try events-currency-required Events \
  sed -i 's|^    if (Text\.size(f\.currency) == 0) return #err(#codeDoesNotFit { code = f\.currency; max = W\.CURRENCY_CODE });$|    if (false) return #err(#codeDoesNotFit { code = f.currency; max = W.CURRENCY_CODE });|' src/EventFold.mo

# an open journal of the company
try events-journal-unchecked Events \
  sed -i 's|^    if (not c\.journalOpen(f\.companyId, f\.journalId)) return #err(#noSuchJournal { journalId = f\.journalId });$|    if (false) return #err(#noSuchJournal { journalId = f.journalId });|' src/EventFold.mo

# AMENDED, SOLD, CLOSED AND CANCELLED WHILE ANNOUNCED ALONE
try events-amend-a-closed-event Events \
  sed -i 's|^    if (e\.state != #announced) return #err(#eventNotAnnounced { eventId; state = e\.state });$|    if (false) return #err(#eventNotAnnounced { eventId; state = e.state });|' src/EventFold.mo

# THE CAPACITY NEVER BELOW THE SEATS SOLD
try events-capacity-below-sold Events \
  sed -i 's|^    if (f\.capacity < e\.seatsSold) return #err(#capacityBelowSold { capacity = f\.capacity; sold = e\.seatsSold });$|    if (false) return #err(#capacityBelowSold { capacity = f.capacity; sold = e.seatsSold });|' src/EventFold.mo

# THE CATEGORY FIXED ONCE SOLD AT
try events-category-not-fixed Events \
  sed -i 's|^    if (e\.seatsSold > 0 and f\.categoryId != e\.categoryId) return #err(#categoryFixed { eventId });$|    if (false) return #err(#categoryFixed { eventId });|' src/EventFold.mo

# CANCELLED BEFORE A SEAT IS SOLD
try events-cancel-with-seats-sold Events \
  sed -i 's|^    if (e\.priceUnit > 0 and e\.seatsSold > 0) return #err(#ticketsSold { eventId; sold = e\.seatsSold });$|    if (false) return #err(#ticketsSold { eventId; sold = e.seatsSold });|' src/EventFold.mo

# closed once its day has come
try events-close-before-the-day Events \
  sed -i 's|^    if (c\.day < e\.day) return #err(#eventNotYet { eventId; day = e\.day; today = c\.day });$|    if (false) return #err(#eventNotYet { eventId; day = e.day; today = c.day });|' src/EventFold.mo

# THE ONE WHO SET THE PRICE DOES NOT SELL AT IT
try events-organiser-sells Events \
  sed -i 's|^    if (c\.caller == e\.organiser) return #err(#organiserSells { subject = c\.caller });$|    if (false) return #err(#organiserSells { subject = c.caller });|' src/EventFold.mo

# NOTHING SOLD AFTER THE DAY
try events-sold-after-the-day Events \
  sed -i 's|^    if (c\.day > e\.day) return #err(#eventPassed { eventId = f\.eventId; day = e\.day; today = c\.day });$|    if (false) return #err(#eventPassed { eventId = f.eventId; day = e.day; today = c.day });|' src/EventFold.mo

# THE SEAT PAST THE CAPACITY REFUSES THE WHOLE ACT
try events-sold-past-the-capacity Events \
  sed -i 's|^    if (f\.seats > left) return #err(#soldOut { eventId = f\.eventId; left; asked = f\.seats });$|    if (false) return #err(#soldOut { eventId = f.eventId; left; asked = f.seats });|' src/EventFold.mo

# THE SALE ASKED ABOUT WHOLE: a customer past their limit refused with nothing written
try events-sale-not-asked-about-whole Events \
  sed -i 's|^    switch (c\.checkSale(order, e\.journalId)) { case (?r) return #err(#order r); case null {} };$|    ignore c.checkSale(order, e.journalId);|' src/EventFold.mo

# the seats counted on the event
try events-seats-not-counted Events \
  sed -i 's|^    RowStore\.put<ER\.Event>(c\.events\.events, ER\.event, f\.eventId, { e with seatsSold = e\.seatsSold + f\.seats; lastBlock = c\.block });$|    RowStore.put<ER.Event>(c.events.events, ER.event, f.eventId, { e with seatsSold = e.seatsSold; lastBlock = c.block });|' src/EventFold.mo

# the seller the caller
try events-seller-not-the-caller Events \
  sed -i 's|^      companyId = f\.companyId; eventId = f\.eventId; partnerId = f\.partnerId; seats = f\.seats; attended = 0; orderId; moveId; amount; soldBy = c\.caller; day = c\.day; lastBlock = c\.block });$|      companyId = f.companyId; eventId = f.eventId; partnerId = f.partnerId; seats = f.seats; attended = 0; orderId; moveId; amount; soldBy = Principal.fromText("aaaaa-aa"); day = c.day; lastBlock = c.block });|' src/EventFold.mo

# ATTENDANCE ON THE DAY OR AFTER, NEVER BEFORE
try events-attendance-before-the-day Events \
  sed -i 's|^    if (c\.day < e\.day) return #err(#eventNotYet { eventId = t\.eventId; day = e\.day; today = c\.day });$|    if (false) return #err(#eventNotYet { eventId = t.eventId; day = e.day; today = c.day });|' src/EventFold.mo

# NEVER BEYOND THE SEATS THE TICKET HOLDS
try events-attendance-over-the-seats Events \
  sed -i 's|^    if (t\.attended + seats > t\.seats) return #err(#attendanceOverSeats { ticketId; seats = t\.seats; attended = t\.attended; asked = seats });$|    if (false) return #err(#attendanceOverSeats { ticketId; seats = t.seats; attended = t.attended; asked = seats });|' src/EventFold.mo

# attendance counted on the event
try events-attendance-not-counted Events \
  sed -i 's|^    RowStore\.put<ER\.Event>(c\.events\.events, ER\.event, t\.eventId, { e with attended = e\.attended + seats; lastBlock = c\.block });$|    RowStore.put<ER.Event>(c.events.events, ER.event, t.eventId, { e with attended = e.attended; lastBlock = c.block });|' src/EventFold.mo

# ── members' events ──────────────────────────────────────────────────────────
#
# Not injected, and why: a stranger's answer (the gate's holders refuse a non-member before the fold, and
# `announced` asks membership of every events act).

# A MEMBERS' EVENT SELLS NO TICKET
try events-members-event-sold Events \
  sed -i 's|^    if (e\.priceUnit == 0) return #err(#membersEventSellsNothing { eventId = f\.eventId });$|    if (false) return #err(#membersEventSellsNothing { eventId = f.eventId });|' src/EventFold.mo

# A PRICED EVENT TAKES NO RESPONSE
try events-priced-event-answered Events \
  sed -i 's|^    if (e\.priceUnit > 0) return #err(#notAMembersEvent { eventId = f\.eventId });$|    if (false) return #err(#notAMembersEvent { eventId = f.eventId });|' src/EventFold.mo

# FREE OR PRICED IS FIXED AT THE ANNOUNCEMENT
try events-price-kind-amended Events \
  sed -i 's|^    if ((f\.priceUnit == 0) != (e\.priceUnit == 0)) return #err(#priceKindFixed { eventId });$|    if (false) return #err(#priceKindFixed { eventId });|' src/EventFold.mo

# AN ANSWER AFTER THE DAY
try events-answer-after-the-day Events \
  sed -i 's|^    if (c\.day > e\.day) return #err(#eventPassed { eventId = f\.eventId; day = e\.day; today = c\.day }); // answered until its day$|    if (false) return #err(#eventPassed { eventId = f.eventId; day = e.day; today = c.day }); // answered until its day|' src/EventFold.mo

# THE SAME ANSWER TWICE
try events-same-answer-twice Events \
  sed -i 's|^      case (?(_, r)) { if (r\.response == f\.response) return #err(#alreadyResponded { eventId = f\.eventId; response = f\.response }) };$|      case (?(_, r)) {};|' src/EventFold.mo

# A PLACE PAST THE CAPACITY
try events-place-past-capacity Events \
  sed -i 's|^    if (attending and not wasAttending and e\.seatsSold >= e\.capacity) return #err(#soldOut { eventId = f\.eventId; left = 0; asked = 1 });$|    if (false) return #err(#soldOut { eventId = f.eventId; left = 0; asked = 1 });|' src/EventFold.mo

# A CHANGED ANSWER MOVES THE PLACE: a place given back kept taken
try events-place-not-given-back Events \
  sed -i 's|^    let seats = if (attending and not wasAttending) e\.seatsSold + 1 else if (wasAttending and not attending) e\.seatsSold - 1 else e\.seatsSold;$|    let seats = if (attending and not wasAttending) e.seatsSold + 1 else e.seatsSold;|' src/EventFold.mo

# ONE ROW PER MEMBER AND EVENT: a changed answer written as a row of its own
try events-changed-answer-a-new-row Events \
  sed -i 's|^      case (?(id, r)) { RowStore\.put<ER\.Response>(c\.events\.responses, ER\.response, id, { r with response = f\.response; day = c\.day; lastBlock = c\.block }); id };$|      case (?(_, r)) { let id = c.events.nextResponseId; RowStore.put<ER.Response>(c.events.responses, ER.response, id, { r with response = f.response; day = c.day; lastBlock = c.block }); c.events.nextResponseId += 1; id };|' src/EventFold.mo

# A MEMBERS' EVENT IS CANCELLED WHOEVER ANSWERED IT
try events-members-event-not-cancelled Events \
  sed -i 's|^    if (e\.priceUnit > 0 and e\.seatsSold > 0) return #err(#ticketsSold { eventId; sold = e\.seatsSold });$|    if (e.seatsSold > 0) return #err(#ticketsSold { eventId; sold = e.seatsSold });|' src/EventFold.mo

# a survey is a member's to open
# Not injected, and why: survey-stranger-opens - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# a question, a response and a close are a member's
# Not injected, and why: survey-stranger-acts - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# a survey is its company's
try survey-wrong-company Survey \
  sed -i 's|^    if (s\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = s\.companyId });$|    if (false) return #err(#wrongCompany { expected = companyId; found = s.companyId });|' src/SurveyFold.mo

# a survey needs a title
try survey-title-required Survey \
  sed -i 's|^    if (Text\.size(f\.title) == 0) return #err(#titleRequired);$|    if (false) return #err(#titleRequired);|' src/SurveyFold.mo

# a last day that fits
try survey-day-unchecked Survey \
  sed -i 's|^    if (not dayFits(f\.dueDay)) return #err(#dayTooLarge { day = f\.dueDay });$|    if (false) return #err(#dayTooLarge { day = f.dueDay });|' src/SurveyFold.mo

# A LAST DAY THAT HAS PASSED
try survey-day-passed Survey \
  sed -i 's|^    if (f\.dueDay != 0 and f\.dueDay < c\.day) return #err(#dayPassed { day = f\.dueDay; today = c\.day });$|    if (false) return #err(#dayPassed { day = f.dueDay; today = c.day });|' src/SurveyFold.mo

# A CLOSED SURVEY TAKES NO QUESTION, NO RESPONSE AND NO SECOND CLOSE
try survey-closed-takes-acts Survey \
  sed -i 's|^    if (s\.state != #open) return #err(#surveyClosed { surveyId });$|    if (false) return #err(#surveyClosed { surveyId });|' src/SurveyFold.mo

# QUESTIONS ADDED WHILE NOBODY HAS ANSWERED
try survey-question-after-an-answer Survey \
  sed -i 's|^    if (s\.responses > 0) return #err(#alreadyAnswered { surveyId = f\.surveyId; responses = s\.responses });$|    if (false) return #err(#alreadyAnswered { surveyId = f.surveyId; responses = s.responses });|' src/SurveyFold.mo

# AT MOST THIRTY-TWO QUESTIONS
try survey-questions-unbounded Survey \
  sed -i 's|^    if (s\.questions >= MAX_QUESTIONS) return #err(#tooManyQuestions { max = MAX_QUESTIONS });$|    if (false) return #err(#tooManyQuestions { max = MAX_QUESTIONS });|' src/SurveyFold.mo

# a question needs a text
try survey-question-text-required Survey \
  sed -i 's|^    if (Text\.size(f\.text) == 0) return #err(#textRequired);$|    if (false) return #err(#textRequired);|' src/SurveyFold.mo

# A CHOICE OF AT LEAST TWO OPTIONS
try survey-one-option Survey \
  sed -i 's|^        if (f\.options\.size() < MIN_OPTIONS) return #err(#optionsRequired { min = MIN_OPTIONS });$|        if (false) return #err(#optionsRequired { min = MIN_OPTIONS });|' src/SurveyFold.mo

# a choice of at most ten options
try survey-eleven-options Survey \
  sed -i 's|^        if (f\.options\.size() > MAX_OPTIONS) return #err(#tooManyOptions { max = MAX_OPTIONS });$|        if (false) return #err(#tooManyOptions { max = MAX_OPTIONS });|' src/SurveyFold.mo

# every option a text
try survey-empty-option Survey \
  sed -i 's|^        for (o in f\.options\.vals()) { if (Text\.size(o) == 0 or Text\.contains(o, #text SEPARATOR)) return #err(#optionEmpty) };$|        for (o in f.options.vals()) { if (false) return #err(#optionEmpty) };|' src/SurveyFold.mo

# OPTIONS ON A CHOICE ALONE
try survey-options-on-a-yes-no Survey \
  sed -i 's|^      case (kind) { if (f\.options\.size() > 0) return #err(#optionsNotForKind { kind }) };$|      case (kind) { if (false) return #err(#optionsNotForKind { kind }) };|' src/SurveyFold.mo

# the questions in order
try survey-ordinal-not-kept Survey \
  sed -i 's|^      companyId = f\.companyId; surveyId = f\.surveyId; ordinal = s\.questions + 1; kind = f\.kind; text; options; optionCount = f\.options\.size(); required = f\.required; answers = 0; lastBlock = c\.block });$|      companyId = f.companyId; surveyId = f.surveyId; ordinal = 1; kind = f.kind; text; options; optionCount = f.options.size(); required = f.required; answers = 0; lastBlock = c.block });|' src/SurveyFold.mo

# A RATING OF ONE TO FIVE
try survey-rating-takes-ten Survey \
  sed -i 's|^    switch (q\.kind) { case (#yesNo) 2; case (#rating) RATING_MAX; case (#multiChoice) q\.optionCount; case (#openText) 0 }$|    switch (q.kind) { case (#yesNo) 2; case (#rating) 10; case (#multiChoice) q.optionCount; case (#openText) 0 }|' src/SurveyFold.mo

# THE TALLY COUNTED FROM THE ANSWER ROWS, choice by choice
try survey-tally-miscounted Survey \
  sed -i 's|^      if (n == 0) counts\[0\] += 1 else if (a\.choice >= 1 and a\.choice <= n) counts\[a\.choice - 1\] += 1;$|      counts[0] += 1;|' src/SurveyFold.mo

# RESULTS A PAGE FROM THE ORDINAL ASKED
try survey-results-from-the-first Survey \
  sed -i 's|^    let page = switch (Lookup\.upTo<SRw\.Question>(st\.questions, SRw\.question, "by_survey_ordinal_one", PR\.pairKey(surveyId, fromOrdinal), PR\.pairKey(surveyId, MAX_QUESTIONS), n)) {$|    let page = switch (Lookup.upTo<SRw.Question>(st.questions, SRw.question, "by_survey_ordinal_one", PR.pairKey(surveyId, 1), PR.pairKey(surveyId, MAX_QUESTIONS), n)) {|' src/SurveyFold.mo

# the close dated by the calendar
try survey-close-not-dated Survey \
  sed -i 's|^    RowStore\.put<SRw\.Survey>(c\.surveys\.surveys, SRw\.survey, surveyId, { s with state = #closed; closedDay = c\.day; lastBlock = c\.block });$|    RowStore.put<SRw.Survey>(c.surveys.surveys, SRw.survey, surveyId, { s with state = #closed; closedDay = 0; lastBlock = c.block });|' src/SurveyFold.mo

# A RESPONSE TO A SURVEY THAT ASKS NOTHING
try survey-answers-nothing-asked Survey \
  sed -i 's|^    if (s\.questions == 0) return #err(#noQuestions { surveyId = f\.surveyId });$|    if (false) return #err(#noQuestions { surveyId = f.surveyId });|' src/SurveyFold.mo

# NOTHING ANSWERED AFTER THE LAST DAY
try survey-answered-after-the-last-day Survey \
  sed -i 's|^    if (s\.dueDay != 0 and c\.day > s\.dueDay) return #err(#surveyOverdue { surveyId = f\.surveyId; dueDay = s\.dueDay; today = c\.day });$|    if (false) return #err(#surveyOverdue { surveyId = f.surveyId; dueDay = s.dueDay; today = c.day });|' src/SurveyFold.mo

# ONE RESPONSE PER RESPONDENT
try survey-responded-twice Survey \
  sed -i 's|^    switch (responseOf(c\.surveys, f\.surveyId, c\.caller)) { case (?_) return #err(#respondedAlready { surveyId = f\.surveyId }); case null {} };$|    switch (responseOf(c.surveys, f.surveyId, c.caller)) { case (?_) {}; case null {} };|' src/SurveyFold.mo

# an answer to this survey's question alone
try survey-other-surveys-question Survey \
  sed -i 's|^      if (q\.surveyId != f\.surveyId) return #err(#questionNotOfSurvey { questionId = a\.questionId; surveyId = f\.surveyId });$|      if (false) return #err(#questionNotOfSurvey { questionId = a.questionId; surveyId = f.surveyId });|' src/SurveyFold.mo

# AT MOST ONE ANSWER PER QUESTION
try survey-question-answered-twice Survey \
  sed -i 's|^      for ((prior, _, _) in List\.values(checked)) { if (prior == a\.questionId) return #err(#answeredTwice { questionId = a\.questionId }) };$|      for ((prior, _, _) in List.values(checked)) { if (false) return #err(#answeredTwice { questionId = a.questionId }) };|' src/SurveyFold.mo

# EVERY REQUIRED QUESTION ANSWERED
try survey-required-unanswered Survey \
  sed -i 's|^        if (not answered) return #err(#requiredUnanswered { questionId = qid });$|        if (false) return #err(#requiredUnanswered { questionId = qid });|' src/SurveyFold.mo

# an open question takes no choice
try survey-choice-on-an-open-question Survey \
  sed -i 's|^        if (a\.choice != 0) return ?#choiceInvalid { questionId; choice = a\.choice };$|        if (false) return ?#choiceInvalid { questionId; choice = a.choice };|' src/SurveyFold.mo

# an open answer is a text
try survey-open-answer-empty Survey \
  sed -i 's|^        if (Text\.size(a\.text) == 0) return ?#textRequired;$|        if (false) return ?#textRequired;|' src/SurveyFold.mo

# AN OPEN ANSWER WITHIN ITS BOUND
try survey-open-answer-unbounded Survey \
  sed -i 's|^        if (Text\.size(a\.text) > MAX_TEXT) return ?#textTooLong { max = MAX_TEXT };$|        if (false) return ?#textTooLong { max = MAX_TEXT };|' src/SurveyFold.mo

# A CHOICE WITHIN THE CHOICES THE QUESTION TAKES
try survey-choice-outside-the-choices Survey \
  sed -i 's|^        if (a\.choice < 1 or a\.choice > n) return ?#choiceInvalid { questionId; choice = a\.choice };$|        if (false) return ?#choiceInvalid { questionId; choice = a.choice };|' src/SurveyFold.mo

# TEXT ON AN OPEN QUESTION ALONE
try survey-text-on-a-choice Survey \
  sed -i 's|^        if (Text\.size(a\.text) > 0) return ?#textNotForKind { questionId };$|        if (false) return ?#textNotForKind { questionId };|' src/SurveyFold.mo

# NOBODY NAMED WHERE THE SURVEY IS ANONYMOUS
try survey-anonymous-names-the-respondent Survey \
  sed -i 's|^      respondent = if (s\.isAnonymous) nobody() else c\.caller; day = c\.day; answers = List\.size(checked); lastBlock = c\.block });$|      respondent = c.caller; day = c.day; answers = List.size(checked); lastBlock = c.block });|' src/SurveyFold.mo

# THE KEY THE SURVEY AND THE RESPONDENT HASHED
try survey-key-not-the-respondents Survey \
  sed -i 's|^      companyId = f\.companyId; surveyId = f\.surveyId; respondentKey = respondentKeyOf(f\.surveyId, c\.caller);$|      companyId = f.companyId; surveyId = f.surveyId; respondentKey = respondentKeyOf(f.surveyId, nobody());|' src/SurveyFold.mo

# the answers counted on the question
try survey-answers-not-counted Survey \
  sed -i 's|^      RowStore\.put<SRw\.Question>(c\.surveys\.questions, SRw\.question, qid, { q with answers = q\.answers + 1; lastBlock = c\.block });$|      RowStore.put<SRw.Question>(c.surveys.questions, SRw.question, qid, { q with answers = q.answers; lastBlock = c.block });|' src/SurveyFold.mo

# the responses counted on the survey
try survey-responses-not-counted Survey \
  sed -i 's|^    RowStore\.put<SRw\.Survey>(c\.surveys\.surveys, SRw\.survey, f\.surveyId, { s with responses = s\.responses + 1; lastBlock = c\.block });$|    RowStore.put<SRw.Survey>(c.surveys.surveys, SRw.survey, f.surveyId, { s with responses = s.responses; lastBlock = c.block });|' src/SurveyFold.mo

# every act a member's
# Not injected, and why: appraisal-stranger-acts - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# a cycle needs a name
try appraisal-cycle-name-required Appraisals \
  sed -i 's|^    if (Text\.size(f\.name) == 0) return #err(#nameRequired { what = "a review cycle" });$|    if (false) return #err(#nameRequired { what = "a review cycle" });|' src/AprFold.mo

# a period whose days fit
try appraisal-cycle-day-unchecked Appraisals \
  sed -i 's|^    if (not dayFits(f\.endDay)) return #err(#dayTooLarge { day = f\.endDay });$|    if (false) return #err(#dayTooLarge { day = f.endDay });|' src/AprFold.mo

# A PERIOD THAT ENDS BEFORE IT STARTS
try appraisal-period-reversed Appraisals \
  sed -i 's|^    if (f\.endDay < f\.startDay) return #err(#daysReversed { startDay = f\.startDay; endDay = f\.endDay });$|    if (false) return #err(#daysReversed { startDay = f.startDay; endDay = f.endDay });|' src/AprFold.mo

# ONE LIVE CYCLE PER COMPANY
try appraisal-two-live-cycles Appraisals \
  sed -i 's|^    switch (liveCycle(c\.apr, f\.companyId)) { case (?(id, _)) return #err(#cycleLive { cycleId = id }); case null {} };$|    switch (liveCycle(c.apr, f.companyId)) { case (?(id, _)) {}; case null {} };|' src/AprFold.mo

# A SLICE WHILE ENROLLING ALONE
try appraisal-slice-when-not-enrolling Appraisals \
  sed -i 's|^    if (cy\.state != #enrolling) return #err(#cycleNotEnrolling { cycleId });$|    if (false) return #err(#cycleNotEnrolling { cycleId });|' src/AprFold.mo

# A SLICE WITHIN THE BOUND
try appraisal-slice-unbounded Appraisals \
  sed -i 's|^    if (limit < 1 or limit > MAX_SLICE) return #err(#sliceBound { limit; max = MAX_SLICE });$|    if (false) return #err(#sliceBound { limit; max = MAX_SLICE });|' src/AprFold.mo

# AN INACTIVE EMPLOYEE GETS NO REVIEW
try appraisal-inactive-enrolled Appraisals \
  sed -i 's|^      if (e\.isActive) {$|      if (true) {|' src/AprFold.mo

# THE REVIEWER IS THE MANAGER AT ENROLMENT
try appraisal-reviewer-not-the-manager Appraisals \
  sed -i 's|^          companyId; cycleId; employeeId; subject = e\.subject; reviewerId = e\.managerId;$|          companyId; cycleId; employeeId; subject = e.subject; reviewerId = 0;|' src/AprFold.mo

# OPEN ONCE A SLICE COMES BACK SHORT, not before
try appraisal-open-before-the-run-ends Appraisals \
  sed -i 's|^      cy with cursor = last; enrolled = cy\.enrolled + added; state = if (page\.size() < limit) #open else #enrolling; lastBlock = c\.block });$|      cy with cursor = last; enrolled = cy.enrolled + added; state = #open; lastBlock = c.block });|' src/AprFold.mo

# the enrolled counted on the cycle
try appraisal-enrolled-not-counted Appraisals \
  sed -i 's|^      cy with cursor = last; enrolled = cy\.enrolled + added; state = if (page\.size() < limit) #open else #enrolling; lastBlock = c\.block });$|      cy with cursor = last; enrolled = cy.enrolled; state = if (page.size() < limit) #open else #enrolling; lastBlock = c.block });|' src/AprFold.mo

# A SELF REVIEW AND A CALIBRATION START ON AN OPEN CYCLE ALONE
try appraisal-acts-on-a-cycle-not-open Appraisals \
  sed -i 's|^    if (cy\.state != #open) return #err(#cycleNotOpen { cycleId });$|    if (false) return #err(#cycleNotOpen { cycleId });|' src/AprFold.mo

# THE SELF REVIEW ONCE
try appraisal-self-review-twice Appraisals \
  sed -i 's|^    if (r\.selfRating != 0) return #err(#selfReviewDone { reviewId });$|    if (false) return #err(#selfReviewDone { reviewId });|' src/AprFold.mo

# A RATING OF ONE TO FIVE
try appraisal-rating-unbounded Appraisals \
  sed -i 's|^  func ratingOk(rating : Nat) : ?Refusal { if (rating < 1 or rating > RATING_MAX) ?#ratingBound { rating; max = RATING_MAX } else null };$|  func ratingOk(rating : Nat) : ?Refusal { if (false) ?#ratingBound { rating; max = RATING_MAX } else null };|' src/AprFold.mo

# THE MANAGER'S REVIEW ON AN OPEN CYCLE ALONE
try appraisal-manager-review-when-not-open Appraisals \
  sed -i 's|^    if (cy\.state != #open) return #err(#cycleNotOpen { cycleId = r\.cycleId });$|    if (false) return #err(#cycleNotOpen { cycleId = r.cycleId });|' src/AprFold.mo

# THE MANAGER'S REVIEW IS THE REVIEWER'S
try appraisal-not-the-reviewer Appraisals \
  sed -i 's|^    if (r\.reviewerId == 0 or callerId != r\.reviewerId) return #err(#notTheReviewer { reviewId = f\.reviewId; subject = c\.caller });$|    if (false) return #err(#notTheReviewer { reviewId = f.reviewId; subject = c.caller });|' src/AprFold.mo

# THE MANAGER'S REVIEW ONCE
try appraisal-manager-review-twice Appraisals \
  sed -i 's|^    if (r\.managerRating != 0) return #err(#managerReviewDone { reviewId = f\.reviewId });$|    if (false) return #err(#managerReviewDone { reviewId = f.reviewId });|' src/AprFold.mo

# the reviewed counted on the cycle
try appraisal-reviewed-not-counted Appraisals \
  sed -i 's|^    RowStore\.put<AR\.ReviewCycle>(c\.apr\.cycles, AR\.reviewCycle, r\.cycleId, { cy with reviewed = cy\.reviewed + 1; lastBlock = c\.block });$|    RowStore.put<AR.ReviewCycle>(c.apr.cycles, AR.reviewCycle, r.cycleId, { cy with reviewed = cy.reviewed; lastBlock = c.block });|' src/AprFold.mo

# CALIBRATION WHILE CALIBRATING ALONE
try appraisal-calibration-when-not-calibrating Appraisals \
  sed -i 's|^    if (cy\.state != #calibrating) return #err(#cycleNotCalibrating { cycleId = r\.cycleId });$|    if (false) return #err(#cycleNotCalibrating { cycleId = r.cycleId });|' src/AprFold.mo

# NOBODY CALIBRATES THEIR OWN RECORD
try appraisal-calibrates-own-record Appraisals \
  sed -i 's|^    if (c\.caller == r\.subject) return #err(#ownRecord { subject = c\.caller });   // the calibration$|    if (false) return #err(#ownRecord { subject = c.caller });   // the calibration|' src/AprFold.mo

# CALIBRATION A SECOND PERSON'S: the reviewer does not calibrate what they rated
try appraisal-reviewer-calibrates Appraisals \
  sed -i 's|^      case (?(callerId, _)) { if (r\.reviewerId != 0 and callerId == r\.reviewerId) return #err(#reviewerCalibrates { reviewId = f\.reviewId; subject = c\.caller }) };$|      case (?(callerId, _)) { if (false) return #err(#reviewerCalibrates { reviewId = f.reviewId; subject = c.caller }) };|' src/AprFold.mo

# CALIBRATED ONCE
try appraisal-calibrated-twice Appraisals \
  sed -i 's|^    if (r\.state == #calibrated) return #err(#alreadyCalibrated { reviewId = f\.reviewId });$|    if (false) return #err(#alreadyCalibrated { reviewId = f.reviewId });|' src/AprFold.mo

# A CALIBRATION NEEDS A REASON
try appraisal-calibration-without-reason Appraisals \
  sed -i 's|^    if (Text\.size(f\.reason) == 0) return #err(#reasonRequired);$|    if (false) return #err(#reasonRequired);|' src/AprFold.mo

# THE FINAL RATING THE CALIBRATED ONE WHERE THERE IS ONE
try appraisal-final-rating-misread Appraisals \
  sed -i 's|^    switch (r\.state) { case (#calibrated) r\.finalRating; case (#open) r\.managerRating }$|    switch (r.state) { case (#calibrated) r.managerRating; case (#open) r.managerRating }|' src/AprFold.mo

# the calibrated counted on the cycle
try appraisal-calibrated-not-counted Appraisals \
  sed -i 's|^    RowStore\.put<AR\.ReviewCycle>(c\.apr\.cycles, AR\.reviewCycle, r\.cycleId, { cy with calibrated = cy\.calibrated + 1; lastBlock = c\.block });$|    RowStore.put<AR.ReviewCycle>(c.apr.cycles, AR.reviewCycle, r.cycleId, { cy with calibrated = cy.calibrated; lastBlock = c.block });|' src/AprFold.mo

# CLOSED FROM CALIBRATING ALONE
try appraisal-close-when-not-calibrating Appraisals \
  sed -i 's|^    if (cy\.state != #calibrating) return #err(#cycleNotCalibrating { cycleId });$|    if (false) return #err(#cycleNotCalibrating { cycleId });|' src/AprFold.mo

# a goal for an active employee
try appraisal-goal-for-inactive Appraisals \
  sed -i 's|^    if (not owner\.isActive) return #err(#inactiveEmployee { employeeId = ownerId });$|    if (false) return #err(#inactiveEmployee { employeeId = ownerId });|' src/AprFold.mo

# A GOAL SET BY THE OWNER OR THEIR MANAGER
try appraisal-goal-set-by-anybody Appraisals \
  sed -i 's|^    if (not ownerOrManager(c, f\.companyId, ownerId, owner)) return #err(#notOwnerOrManager { goalId = 0; subject = c\.caller });$|    if (false) return #err(#notOwnerOrManager { goalId = 0; subject = c.caller });|' src/AprFold.mo

# A GOAL DUE TODAY OR LATER
try appraisal-goal-due-passed Appraisals \
  sed -i 's|^    if (f\.dueDay < c\.day) return #err(#dayPassed { day = f\.dueDay; today = c\.day });$|    if (false) return #err(#dayPassed { day = f.dueDay; today = c.day });|' src/AprFold.mo

# a goal in a cycle not closed
try appraisal-goal-in-closed-cycle Appraisals \
  sed -i 's|^      if (cy\.state == #closed) return #err(#cycleClosed { cycleId = f\.cycleId });$|      if (false) return #err(#cycleClosed { cycleId = f.cycleId });|' src/AprFold.mo

# A KEY RESULT BY THE OWNER OR THEIR MANAGER
try appraisal-key-result-by-anybody Appraisals \
  sed -i 's|^    if (not ownerOrManagerOf(c, f\.companyId, g\.ownerId)) return #err(#notOwnerOrManager { goalId = f\.goalId; subject = c\.caller });$|    if (false) return #err(#notOwnerOrManager { goalId = f.goalId; subject = c.caller });|' src/AprFold.mo

# AT MOST TEN KEY RESULTS
try appraisal-key-results-unbounded Appraisals \
  sed -i 's|^    if (g\.keyResults >= MAX_KEY_RESULTS) return #err(#tooManyKeyResults { max = MAX_KEY_RESULTS });$|    if (false) return #err(#tooManyKeyResults { max = MAX_KEY_RESULTS });|' src/AprFold.mo

# a key result needs a target
try appraisal-target-required Appraisals \
  sed -i 's|^    if (f\.target == 0 or f\.target >= F\.pow256(W\.QTY)) return #err(#targetRequired);$|    if (false) return #err(#targetRequired);|' src/AprFold.mo

# a yes-no has a target of one
try appraisal-yes-no-target Appraisals \
  sed -i 's|^    if (f\.kind == #yesNo and f\.target != 1) return #err(#yesNoTarget { target = f\.target });$|    if (false) return #err(#yesNoTarget { target = f.target });|' src/AprFold.mo

# A CLOSED GOAL TAKES NOTHING
try appraisal-closed-goal-moves Appraisals \
  sed -i 's|^    if (g\.state != #active) return #err(#goalNotActive { goalId });$|    if (false) return #err(#goalNotActive { goalId });|' src/AprFold.mo

# ONLY THE OWNER MOVES A KEY RESULT
try appraisal-key-result-moved-by-manager Appraisals \
  sed -i 's|^    if (c\.caller != g\.subject) return #err(#notTheOwner { goalId = kr\.goalId; subject = c\.caller });$|    if (false) return #err(#notTheOwner { goalId = kr.goalId; subject = c.caller });|' src/AprFold.mo

# NEVER PAST THE TARGET
try appraisal-key-result-past-target Appraisals \
  sed -i 's|^    if (current > kr\.target) return #err(#overTarget { current; target = kr\.target });$|    if (false) return #err(#overTarget { current; target = kr.target });|' src/AprFold.mo

# achieved with key results to achieve
try appraisal-achieved-with-no-key-result Appraisals \
  sed -i 's|^      if (krs\.size() == 0) return #err(#noKeyResults { goalId });$|      if (false) return #err(#noKeyResults { goalId });|' src/AprFold.mo

# ACHIEVED ONLY WHEN EVERY KEY RESULT IS AT ITS TARGET
try appraisal-achieved-short Appraisals \
  sed -i 's|^      if (short > 0) return #err(#keyResultsShort { goalId; short });$|      if (false) return #err(#keyResultsShort { goalId; short });|' src/AprFold.mo

# PROGRESS A READ, per mille over the key results
try appraisal-progress-miscomputed Appraisals \
  sed -i 's|^    for ((_, kr) in krs\.vals()) { sum += Nat\.min(kr\.current, kr\.target) \* 1_000 / kr\.target };$|    for ((_, kr) in krs.vals()) { sum += 1_000 };|' src/AprFold.mo

# A GOAL CLOSED BY THE OWNER OR THEIR MANAGER
try appraisal-goal-closed-by-anybody Appraisals \
  sed -i 's|^    if (not ownerOrManagerOf(c, companyId, g\.ownerId)) return #err(#notOwnerOrManager { goalId; subject = c\.caller });$|    if (false) return #err(#notOwnerOrManager { goalId; subject = c.caller });|' src/AprFold.mo

# a recognition of a member
try appraisal-recognises-a-stranger Appraisals \
  sed -i 's|^    if (not c\.isMember(f\.companyId, f\.to)) return #err(#recipientNotAMember { subject = f\.to });$|    if (false) return #err(#recipientNotAMember { subject = f.to });|' src/AprFold.mo

# NOBODY RECOGNISES THEMSELVES
try appraisal-recognises-oneself Appraisals \
  sed -i 's|^    if (c\.caller == f\.to) return #err(#selfRecognition { subject = c\.caller });$|    if (false) return #err(#selfRecognition { subject = c.caller });|' src/AprFold.mo

# a recognition needs a message
try appraisal-message-required Appraisals \
  sed -i 's|^    if (Text\.size(f\.message) == 0) return #err(#messageRequired);$|    if (false) return #err(#messageRequired);|' src/AprFold.mo

# A MESSAGE WITHIN ITS BOUND
try appraisal-message-unbounded Appraisals \
  sed -i 's|^    if (Text\.size(f\.message) > MAX_MESSAGE) return #err(#textTooLong { max = MAX_MESSAGE });$|    if (false) return #err(#textTooLong { max = MAX_MESSAGE });|' src/AprFold.mo

# every act a member's
# Not injected, and why: learning-stranger-acts - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# a course needs a title
try learning-course-title-required Learning \
  sed -i 's|^    if (Text\.size(f\.title) == 0) return #err(#nameRequired { what = "a course" });$|    if (false) return #err(#nameRequired { what = "a course" });|' src/LrnFold.mo

# A COURSE HAS A DURATION
try learning-course-duration-required Learning \
  sed -i 's|^    if (f\.durationMins == 0 or f\.durationMins >= F\.pow256(W\.QTY)) return #err(#durationRequired);$|    if (false) return #err(#durationRequired);|' src/LrnFold.mo

# a course retired once
try learning-course-retired-twice Learning \
  sed -i 's|^    if (not co\.isActive) return #err(#courseRetired { courseId });$|    if (false) return #err(#courseRetired { courseId });|' src/LrnFold.mo

# a path needs a title
try learning-path-title-required Learning \
  sed -i 's|^    if (Text\.size(f\.title) == 0) return #err(#nameRequired { what = "a learning path" });$|    if (false) return #err(#nameRequired { what = "a learning path" });|' src/LrnFold.mo

# A PATH HAS A COURSE
try learning-path-empty Learning \
  sed -i 's|^    if (f\.courseIds\.size() == 0) return #err(#pathEmpty);$|    if (false) return #err(#pathEmpty);|' src/LrnFold.mo

# A PATH OF AT MOST TWENTY
try learning-path-unbounded Learning \
  sed -i 's|^    if (f\.courseIds\.size() > MAX_PATH_COURSES) return #err(#tooManyCourses { max = MAX_PATH_COURSES });$|    if (false) return #err(#tooManyCourses { max = MAX_PATH_COURSES });|' src/LrnFold.mo

# A PATH THROUGH ACTIVE COURSES ALONE
try learning-path-through-retired Learning \
  sed -i 's|^      if (not co\.isActive) return #err(#courseRetired { courseId = f\.courseIds\[i\] });$|      if (false) return #err(#courseRetired { courseId = f.courseIds[i] });|' src/LrnFold.mo

# NO COURSE TWICE ON A PATH
try learning-path-course-twice Learning \
  sed -i 's|^      while (j < i) { if (f\.courseIds\[j\] == f\.courseIds\[i\]) return #err(#courseTwice { courseId = f\.courseIds\[i\] }); j += 1 };$|      while (j < i) { if (false) return #err(#courseTwice { courseId = f.courseIds[i] }); j += 1 };|' src/LrnFold.mo

# a path retired once
try learning-path-retired-twice Learning \
  sed -i 's|^    if (not p\.isActive) return #err(#pathRetired { pathId });$|    if (false) return #err(#pathRetired { pathId });|' src/LrnFold.mo

# AN ENROLMENT IN AN ACTIVE COURSE ALONE
try learning-enrol-in-retired Learning \
  sed -i 's|^    if (not co\.isActive) return #err(#courseRetired { courseId = f\.courseId });$|    if (false) return #err(#courseRetired { courseId = f.courseId });|' src/LrnFold.mo

# an enrolment of an active employee
try learning-enrol-inactive Learning \
  sed -i 's|^    if (not e\.isActive) return #err(#inactiveEmployee { employeeId });   // the learner$|    if (false) return #err(#inactiveEmployee { employeeId });   // the learner|' src/LrnFold.mo

# AN ENROLMENT BY THE LEARNER OR THEIR MANAGER
try learning-enrol-by-anybody Learning \
  sed -i 's|^    if (not selfOrManager(c, f\.companyId, e)) return #err(#notLearnerOrManager { subject = c\.caller });$|    if (false) return #err(#notLearnerOrManager { subject = c.caller });|' src/LrnFold.mo

# NOT ENROLLED AGAIN IN A COURSE COMPLETED
try learning-enrol-after-completion Learning \
  sed -i 's|^          case (#completed) return #err(#alreadyCompleted { courseId = f\.courseId; employeeId });$|          case (#completed) {};|' src/LrnFold.mo

# ONE LIVE ENROLMENT PER LEARNER PER COURSE
try learning-enrol-twice Learning \
  sed -i 's|^          case (_) return #err(#alreadyEnrolled { courseId = f\.courseId; employeeId });$|          case (_) {};|' src/LrnFold.mo

# the enrolments counted on the course
try learning-enrolments-not-counted Learning \
  sed -i 's|^        RowStore\.put<LR\.Course>(c\.lrn\.courses, LR\.course, f\.courseId, { co with enrolments = co\.enrolments + 1; lastBlock = c\.block });   // enrolled first$|        RowStore.put<LR.Course>(c.lrn.courses, LR.course, f.courseId, { co with enrolments = co.enrolments; lastBlock = c.block });   // enrolled first|' src/LrnFold.mo

# A COMPLETED OR DROPPED ENROLMENT TAKES NOTHING
try learning-acts-on-a-dead-enrolment Learning \
  sed -i 's|^    if (en\.state == #completed or en\.state == #dropped) return #err(#enrolmentNotLive { enrolmentId });$|    if (false) return #err(#enrolmentNotLive { enrolmentId });|' src/LrnFold.mo

# ONLY THE LEARNER MOVES THEIR PROGRESS
try learning-progress-by-manager Learning \
  sed -i 's|^    if (c\.caller != en\.subject) return #err(#notTheLearner { enrolmentId; subject = c\.caller });$|    if (false) return #err(#notTheLearner { enrolmentId; subject = c.caller });|' src/LrnFold.mo

# PROGRESS WITHIN A HUNDRED
try learning-progress-unbounded Learning \
  sed -i 's|^    if (progressPct < 1 or progressPct > 100) return #err(#progressBound { progressPct });$|    if (false) return #err(#progressBound { progressPct });|' src/LrnFold.mo

# NEVER BACKWARDS
try learning-progress-backwards Learning \
  sed -i 's|^    if (progressPct <= en\.progressPct) return #err(#progressNotForward { from = en\.progressPct; to = progressPct });$|    if (false) return #err(#progressNotForward { from = en.progressPct; to = progressPct });|' src/LrnFold.mo

# A HUNDRED COMPLETES
try learning-hundred-does-not-complete Learning \
  sed -i 's|^    let done = progressPct == 100;$|    let done = false;|' src/LrnFold.mo

# A DROP BY THE LEARNER OR THEIR MANAGER
try learning-drop-by-anybody Learning \
  sed -i 's|^    if (not selfOrManager(c, companyId, e)) return #err(#notLearnerOrManager { subject = c\.caller });$|    if (false) return #err(#notLearnerOrManager { subject = c.caller });|' src/LrnFold.mo

# a certification needs a name
try learning-cert-name-required Learning \
  sed -i 's|^    if (Text\.size(f\.name) == 0) return #err(#nameRequired { what = "a certification" });$|    if (false) return #err(#nameRequired { what = "a certification" });|' src/LrnFold.mo

# a certification needs an issuer
try learning-cert-issuer-required Learning \
  sed -i 's|^    if (Text\.size(f\.issuer) == 0) return #err(#nameRequired { what = "an issuer" });$|    if (false) return #err(#nameRequired { what = "an issuer" });|' src/LrnFold.mo

# ISSUED NOT AFTER TODAY
try learning-cert-issued-tomorrow Learning \
  sed -i 's|^    if (issuedDay > c\.day) return ?#dayInFuture { day = issuedDay; today = c\.day };$|    if (false) return ?#dayInFuture { day = issuedDay; today = c.day };|' src/LrnFold.mo

# AN EXPIRY AFTER THE ISSUE
try learning-cert-expiry-before-issue Learning \
  sed -i 's|^    if (expiryDay != 0 and expiryDay <= issuedDay) return ?#expiryBeforeIssue { issuedDay; expiryDay };$|    if (false) return ?#expiryBeforeIssue { issuedDay; expiryDay };|' src/LrnFold.mo

# evidenced by a company document or none
try learning-cert-document-unchecked Learning \
  sed -i 's|^    if (f\.documentId != 0 and not c\.documentIsCompanys(f\.companyId, f\.documentId)) return #err(#noSuchDocument { documentId = f\.documentId });$|    if (false) return #err(#noSuchDocument { documentId = f.documentId });|' src/LrnFold.mo

# VALID ON A DAY IS A READ AGAINST THE CALENDAR
try learning-validity-ignores-the-calendar Learning \
  sed -i 's|^    cert\.state == #valid and (cert\.expiryDay == 0 or day <= cert\.expiryDay)$|    cert.state == #valid|' src/LrnFold.mo

# A REVOKED CERTIFICATION IS NEITHER RENEWED NOR REVOKED AGAIN
try learning-revoked-cert-acts Learning \
  sed -i 's|^    if (cert\.state == #revoked) return #err(#certificationRevoked { certificationId });$|    if (false) return #err(#certificationRevoked { certificationId });|' src/LrnFold.mo

# A RENEWAL NOT BEFORE THE ISSUE
try learning-renewal-backdated Learning \
  sed -i 's|^    if (f\.issuedDay < cert\.issuedDay) return #err(#renewalBackdated { issuedDay = f\.issuedDay; previous = cert\.issuedDay });$|    if (false) return #err(#renewalBackdated { issuedDay = f.issuedDay; previous = cert.issuedDay });|' src/LrnFold.mo

# A RENEWAL FORWARD
try learning-renewal-not-forward Learning \
  sed -i 's|^    if (cert\.expiryDay != 0 and f\.expiryDay != 0 and f\.expiryDay <= cert\.expiryDay) return #err(#renewalNotForward { expiryDay = f\.expiryDay; previous = cert\.expiryDay });$|    if (false) return #err(#renewalNotForward { expiryDay = f.expiryDay; previous = cert.expiryDay });|' src/LrnFold.mo

# NOBODY REVOKES THEIR OWN
try learning-revokes-own-cert Learning \
  sed -i 's|^    if (c\.caller == cert\.subject) return #err(#ownRecord { subject = c\.caller });$|    if (false) return #err(#ownRecord { subject = c.caller });|' src/LrnFold.mo

# A REVOCATION NEEDS A REASON
try learning-revocation-without-reason Learning \
  sed -i 's|^    if (Text\.size(reason) == 0) return #err(#reasonRequired);$|    if (false) return #err(#reasonRequired);|' src/LrnFold.mo

# a skill needs a name
try learning-skill-name-required Learning \
  sed -i 's|^    if (Text\.size(f\.name) == 0) return #err(#nameRequired { what = "a skill" });$|    if (false) return #err(#nameRequired { what = "a skill" });|' src/LrnFold.mo

# A LEVEL OF ONE TO FIVE
try learning-level-unbounded Learning \
  sed -i 's|^  func levelOk(level : Nat) : ?Refusal { if (level < 1 or level > LEVEL_MAX) ?#levelBound { level; max = LEVEL_MAX } else null };$|  func levelOk(level : Nat) : ?Refusal { if (false) ?#levelBound { level; max = LEVEL_MAX } else null };|' src/LrnFold.mo

# AT MOST FIFTY SKILLS
try learning-skills-unbounded Learning \
  sed -i 's|^        if (skillsOf(c\.lrn, employeeId)\.size() >= MAX_SKILLS) return #err(#tooManySkills { max = MAX_SKILLS });$|        if (false) return #err(#tooManySkills { max = MAX_SKILLS });|' src/LrnFold.mo

# A REMOVED SKILL TAKES NOTHING
try learning-removed-skill-acts Learning \
  sed -i 's|^    if (not s\.isActive) return #err(#skillRemoved { skillId });$|    if (false) return #err(#skillRemoved { skillId });|' src/LrnFold.mo

# A SKILL REMOVED BY ITS HOLDER
try learning-skill-removed-by-anybody Learning \
  sed -i 's|^    if (c\.caller != s\.subject) return #err(#notTheHolder { skillId; subject = c\.caller });$|    if (false) return #err(#notTheHolder { skillId; subject = c.caller });|' src/LrnFold.mo

# NOBODY ENDORSES THEIR OWN
try learning-endorses-own-skill Learning \
  sed -i 's|^    if (c\.caller == s\.subject) return #err(#ownRecord { subject = c\.caller });$|    if (false) return #err(#ownRecord { subject = c.caller });|' src/LrnFold.mo

# ONE ENDORSEMENT PER ENDORSER
try learning-endorses-twice Learning \
  sed -i 's|^    for ((_, en) in given\.vals()) { if (en\.endorser == c\.caller) return #err(#alreadyEndorsed { skillId = f\.skillId; subject = c\.caller }) };$|    for ((_, en) in given.vals()) { if (false) return #err(#alreadyEndorsed { skillId = f.skillId; subject = c.caller }) };|' src/LrnFold.mo

# the endorsements counted on the skill
try learning-endorsements-not-counted Learning \
  sed -i 's|^    RowStore\.put<LR\.Skill>(c\.lrn\.skills, LR\.skill, f\.skillId, { s with endorsements = s\.endorsements + 1; lastBlock = c\.block });$|    RowStore.put<LR.Skill>(c.lrn.skills, LR.skill, f.skillId, { s with endorsements = s.endorsements; lastBlock = c.block });|' src/LrnFold.mo

# THE MANAGER'S RATING THE MANAGER'S ALONE
try learning-rated-by-anybody Learning \
  sed -i 's|^    if (not isManager) return #err(#notTheManager { skillId; subject = c\.caller });$|    if (false) return #err(#notTheManager { skillId; subject = c.caller });|' src/LrnFold.mo

# ROOM FOR ONE TO TWENTY
try learning-mentees-unbounded Learning \
  sed -i 's|^    if (f\.maxMentees < 1 or f\.maxMentees > MAX_MENTEES) return #err(#menteesBound { maxMentees = f\.maxMentees; max = MAX_MENTEES });$|    if (false) return #err(#menteesBound { maxMentees = f.maxMentees; max = MAX_MENTEES });|' src/LrnFold.mo

# a request by an active employee
try learning-inactive-mentee Learning \
  sed -i 's|^    if (not mentee\.isActive) return #err(#inactiveEmployee { employeeId = menteeId });$|    if (false) return #err(#inactiveEmployee { employeeId = menteeId });|' src/LrnFold.mo

# NOBODY MENTORS THEMSELVES
try learning-mentors-oneself Learning \
  sed -i 's|^    if (mentorId == menteeId) return #err(#selfMentoring { subject = c\.caller });$|    if (false) return #err(#selfMentoring { subject = c.caller });|' src/LrnFold.mo

# A REQUEST OF A MENTOR WHO IS OFFERING
try learning-mentor-not-offering Learning \
  sed -i 's|^    if (not profile\.isActive) return #err(#notAMentor { subject = f\.mentor });$|    if (false) return #err(#notAMentor { subject = f.mentor });|' src/LrnFold.mo

# a mentorship needs a focus
try learning-focus-required Learning \
  sed -i 's|^    if (Text\.size(f\.focus) == 0) return #err(#nameRequired { what = "a mentorship'\''s focus" });$|    if (false) return #err(#nameRequired { what = "a mentorship'\''s focus" });|' src/LrnFold.mo

# ONE MENTORSHIP STANDING PER PAIR
try learning-asks-twice Learning \
  sed -i 's|^        if (m\.menteeId == menteeId) return #err(#alreadyMentored { mentorId; menteeId });$|        if (false) return #err(#alreadyMentored { mentorId; menteeId });|' src/LrnFold.mo

# A MENTOR WITH ROOM
try learning-mentor-full Learning \
  sed -i 's|^    if (count >= profile\.maxMentees) return #err(#mentorFull { mentorId; maxMentees = profile\.maxMentees });$|    if (false) return #err(#mentorFull { mentorId; maxMentees = profile.maxMentees });|' src/LrnFold.mo

# THE ROOM COUNTED FROM WHAT STANDS
try learning-room-counts-the-declined Learning \
  sed -i 's|^      if (standing(m\.state)) {$|      if (true) {|' src/LrnFold.mo

# THE MENTOR ANSWERS
try learning-answered-by-mentee Learning \
  sed -i 's|^    if (c\.caller != m\.mentorSubject) return #err(#notTheMentor { mentorshipId; subject = c\.caller });$|    if (false) return #err(#notTheMentor { mentorshipId; subject = c.caller });|' src/LrnFold.mo

# ANSWERED ONCE
try learning-answered-twice Learning \
  sed -i 's|^    if (m\.state != #requested) return #err(#mentorshipNotRequested { mentorshipId });$|    if (false) return #err(#mentorshipNotRequested { mentorshipId });|' src/LrnFold.mo

# A SESSION BY A PARTY
try learning-session-by-a-stranger-to-it Learning \
  sed -i 's|^    if (c\.caller != m\.mentorSubject and c\.caller != m\.menteeSubject) return #err(#notAParty { mentorshipId; subject = c\.caller });$|    if (false) return #err(#notAParty { mentorshipId; subject = c.caller });|' src/LrnFold.mo

# A SESSION ON AN ACTIVE MENTORSHIP ALONE
try learning-session-when-not-active Learning \
  sed -i 's|^    if (m\.state != #active) return #err(#mentorshipNotActive { mentorshipId });$|    if (false) return #err(#mentorshipNotActive { mentorshipId });|' src/LrnFold.mo

# A SESSION WITHIN TEN HOURS
try learning-minutes-unbounded Learning \
  sed -i 's|^    if (f\.minutes < 1 or f\.minutes > MAX_SESSION_MINUTES) return #err(#minutesBound { minutes = f\.minutes; max = MAX_SESSION_MINUTES });$|    if (false) return #err(#minutesBound { minutes = f.minutes; max = MAX_SESSION_MINUTES });|' src/LrnFold.mo

# the minutes added on the mentorship
try learning-minutes-not-added Learning \
  sed -i 's|^    RowStore\.put<LR\.Mentorship>(c\.lrn\.mentorships, LR\.mentorship, f\.mentorshipId, { m with sessions = m\.sessions + 1; minutes = m\.minutes + f\.minutes; lastBlock = c\.block });$|    RowStore.put<LR.Mentorship>(c.lrn.mentorships, LR.mentorship, f.mentorshipId, { m with sessions = m.sessions + 1; minutes = m.minutes; lastBlock = c.block });|' src/LrnFold.mo


# ── compensation and benefits ───────────────────────────────────────────────────
# Every rule the Compensation battery states, removed one at a time from `src/CnbFold.mo`.
# Not injected, each defended twice: a plan with no metric (its weights sum to nothing, not ten thousand); the
# creator approving a payment, the approver disbursing a loan and the borrower recording their own repayment (the
# ledger's `checkGenerated` refuses a proposer who is the caller); a repayment of nothing (the ledger refuses a line
# with neither side).

# every act a member's
# Not injected, and why: cnb-stranger-acts - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# THE SALARY EXPENSE IS AN EXPENSE
try cnb-policy-expense-kind Compensation \
  sed -i 's|^    if (expense\.accountType != #expense) return #err(#accountKind { what = "the salary expense"; found = accountTypeName(expense\.accountType) });$|    if (false) return #err(#accountKind { what = "the salary expense"; found = accountTypeName(expense\.accountType) });|' src/CnbFold.mo

# DEDUCTIONS HELD IN A LIABILITY
try cnb-policy-deductions-kind Compensation \
  sed -i 's|^    if (deductions\.accountType != #liability and deductions\.accountType != #payable) return #err(#accountKind { what = "the deductions account"; found = accountTypeName(deductions\.accountType) });$|    if (false) return #err(#accountKind { what = "the deductions account"; found = accountTypeName(deductions\.accountType) });|' src/CnbFold.mo

# THE EMPLOYEE PAYABLE A PAYABLE
try cnb-policy-payable-kind Compensation \
  sed -i 's|^    if (payable\.accountType != #payable and payable\.accountType != #liability) return #err(#accountKind { what = "the employee payable"; found = accountTypeName(payable\.accountType) });$|    if (false) return #err(#accountKind { what = "the employee payable"; found = accountTypeName(payable\.accountType) });|' src/CnbFold.mo

# THE LOAN RECEIVABLE A RECEIVABLE
try cnb-policy-receivable-kind Compensation \
  sed -i 's|^    if (receivable\.accountType != #receivable and receivable\.accountType != #asset) return #err(#accountKind { what = "the loan receivable"; found = accountTypeName(receivable\.accountType) });$|    if (false) return #err(#accountKind { what = "the loan receivable"; found = accountTypeName(receivable\.accountType) });|' src/CnbFold.mo

# a band needs a name
try cnb-band-name-required Compensation \
  sed -i 's|^    if (Text\.size(f\.name) == 0) return #err(#nameRequired { what = "a pay band" });$|    if (false) return #err(#nameRequired { what = "a pay band" });|' src/CnbFold.mo

# A GRADE OF ONE TO TEN
try cnb-grade-unbounded Compensation \
  sed -i 's|^    if (f\.grade < 1 or f\.grade > GRADE_MAX) return #err(#gradeBound { grade = f\.grade; max = GRADE_MAX });$|    if (false) return #err(#gradeBound { grade = f\.grade; max = GRADE_MAX });|' src/CnbFold.mo

# MINIMUM, MIDPOINT, MAXIMUM IN ORDER (declared and amended)
try cnb-band-out-of-order Compensation \
  sed -i 's|^    if (minAmount == 0 or minAmount > midAmount or midAmount > maxAmount or not moneyFits(maxAmount)) return ?#bandOrder { minAmount; midAmount; maxAmount };$|    if (false) return ?#bandOrder { minAmount; midAmount; maxAmount };|' src/CnbFold.mo

# ONE BAND PER GRADE
try cnb-grade-twice Compensation \
  sed -i 's|^    switch (taken) { case (?(id, b)) { if (b\.isActive) return #err(#gradeTaken { grade = f\.grade; bandId = id }) }; case null {} };$|    switch (taken) { case (?(id, b)) { if (false) return #err(#gradeTaken { grade = f\.grade; bandId = id }) }; case null {} };|' src/CnbFold.mo

# a retired band takes nothing
try cnb-band-retired-used Compensation \
  sed -i 's|^    if (not b\.isActive) return #err(#bandRetired { bandId });$|    if (false) return #err(#bandRetired { bandId });|' src/CnbFold.mo

# a band is its company's
try cnb-band-wrong-company Compensation \
  sed -i 's|^    if (b\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = b\.companyId });$|    if (false) return #err(#wrongCompany { expected = companyId; found = b\.companyId });|' src/CnbFold.mo

# a review of an active employee
try cnb-review-inactive-subject Compensation \
  sed -i 's|^    if (not e\.isActive) return #err(#inactiveEmployee { employeeId });   // the subject of a review$|    if (false) return #err(#inactiveEmployee { employeeId });   // the subject of a review|' src/CnbFold.mo

# THE MANAGER'S PROPOSAL
try cnb-review-not-the-manager Compensation \
  sed -i 's|^    if (not isManager) return #err(#notTheManager { subject = c\.caller });$|    if (false) return #err(#notTheManager { subject = c\.caller });|' src/CnbFold.mo

# WITHIN THE BAND
try cnb-review-outside-band Compensation \
  sed -i 's|^    if (f\.proposedBase < band\.minAmount or f\.proposedBase > band\.maxAmount) return #err(#outsideBand { proposed = f\.proposedBase; minAmount = band\.minAmount; maxAmount = band\.maxAmount });$|    if (false) return #err(#outsideBand { proposed = f\.proposedBase; minAmount = band\.minAmount; maxAmount = band\.maxAmount });|' src/CnbFold.mo

# a review moves the base
try cnb-review-no-change Compensation \
  sed -i 's|^    if (f\.proposedBase == currentBase) return #err(#noChange { base = currentBase });$|    if (false) return #err(#noChange { base = currentBase });|' src/CnbFold.mo

# a day that fits
try cnb-review-day-too-large Compensation \
  sed -i 's|^    if (not dayFits(f\.effectiveDay)) return #err(#dayTooLarge { day = f\.effectiveDay });$|    if (false) return #err(#dayTooLarge { day = f\.effectiveDay });|' src/CnbFold.mo

# EFFECTIVE ON A DAY NOT PAST
try cnb-review-day-past Compensation \
  sed -i 's|^    if (f\.effectiveDay < c\.day) return #err(#dayPast { day = f\.effectiveDay; today = c\.day });$|    if (false) return #err(#dayPast { day = f\.effectiveDay; today = c\.day });|' src/CnbFold.mo

# a review needs a justification
try cnb-review-justification-required Compensation \
  sed -i 's|^    if (Text\.size(f\.justification) == 0) return #err(#reasonRequired { what = "a salary review" });$|    if (false) return #err(#reasonRequired { what = "a salary review" });|' src/CnbFold.mo

# ONE REVIEW IN FLIGHT PER EMPLOYEE
try cnb-review-one-in-flight Compensation \
  sed -i 's|^    switch (openReviewOf(c\.cnb, employeeId)) { case (?reviewId) return #err(#reviewOpen { employeeId; reviewId }); case null {} };$|    ignore openReviewOf(c\.cnb, employeeId);|' src/CnbFold.mo

# a review decided while proposed
try cnb-review-decided-twice Compensation \
  sed -i 's|^    if (r\.state != #proposed) return #err(#reviewNotInState { reviewId; state = reviewStateName(r\.state); wanted = "proposed" });$|    if (false) return #err(#reviewNotInState { reviewId; state = reviewStateName(r\.state); wanted = "proposed" });|' src/CnbFold.mo

# NOBODY DECIDES THEIR OWN REVIEW
try cnb-review-decided-by-subject Compensation \
  sed -i 's|^    if (c\.caller == r\.subject) return #err(#ownRecord { subject = c\.caller });   // deciding one'\''s own review$|    if (false) return #err(#ownRecord { subject = c\.caller });   // deciding one'\''s own review|' src/CnbFold.mo

# A SECOND PERSON DECIDES
try cnb-review-decided-by-proposer Compensation \
  sed -i 's|^    if (c\.caller == r\.proposedBy) return #err(#sameHands { what = "proposed"; subject = c\.caller });$|    if (false) return #err(#sameHands { what = "proposed"; subject = c\.caller });|' src/CnbFold.mo

# a rejection carries a note
try cnb-review-rejection-note Compensation \
  sed -i 's|^    if (not approve and Text\.size(note) == 0) return #err(#reasonRequired { what = "a rejection" });$|    if (false) return #err(#reasonRequired { what = "a rejection" });|' src/CnbFold.mo

# an approved review is implemented
try cnb-review-implemented-unapproved Compensation \
  sed -i 's|^    if (r\.state != #approved) return #err(#reviewNotInState { reviewId; state = reviewStateName(r\.state); wanted = "approved" });$|    if (false) return #err(#reviewNotInState { reviewId; state = reviewStateName(r\.state); wanted = "approved" });|' src/CnbFold.mo

# NOBODY IMPLEMENTS THEIR OWN REVIEW
try cnb-review-implemented-by-subject Compensation \
  sed -i 's|^    if (c\.caller == r\.subject) return #err(#ownRecord { subject = c\.caller });   // implementing one'\''s own review$|    if (false) return #err(#ownRecord { subject = c\.caller });   // implementing one'\''s own review|' src/CnbFold.mo

# IMPLEMENTED ONCE ITS DAY HAS COME
try cnb-review-implemented-early Compensation \
  sed -i 's|^    if (c\.day < r\.effectiveDay) return #err(#notYetEffective { day = r\.effectiveDay; today = c\.day });$|    if (false) return #err(#notYetEffective { day = r\.effectiveDay; today = c\.day });|' src/CnbFold.mo

# THE NEW BASE WRITTEN THROUGH THE PAYROLL FOLD
try cnb-review-base-not-written Compensation \
  sed -i 's|^    switch (c\.applyBasePay(companyId, r\.subject, r\.proposedBase, r\.effectiveDay)) { case (?reason) return #err(#pay { reason }); case null {} };$|    ignore r\.proposedBase;|' src/CnbFold.mo

# withdrawn while proposed
try cnb-review-withdrawn-late Compensation \
  sed -i 's|^    if (r\.state != #proposed) return #err(#reviewNotInState { reviewId; state = reviewStateName(r\.state); wanted = "proposed" });   // withdrawn while proposed$|    if (false) return #err(#reviewNotInState { reviewId; state = reviewStateName(r\.state); wanted = "proposed" });   // withdrawn while proposed|' src/CnbFold.mo

# withdrawn by its proposer
try cnb-review-withdrawn-by-other Compensation \
  sed -i 's|^    if (c\.caller != r\.proposedBy) return #err(#notTheProposer { subject = c\.caller });$|    if (false) return #err(#notTheProposer { subject = c\.caller });|' src/CnbFold.mo

# a grant to an active employee
try cnb-grant-inactive Compensation \
  sed -i 's|^    if (not e\.isActive) return #err(#inactiveEmployee { employeeId });   // the grantee$|    if (false) return #err(#inactiveEmployee { employeeId });   // the grantee|' src/CnbFold.mo

# A GRANT BY SOMEBODY ELSE
try cnb-grant-to-oneself Compensation \
  sed -i 's|^    if (c\.caller == f\.subject) return #err(#ownRecord { subject = c\.caller });   // granting to oneself$|    if (false) return #err(#ownRecord { subject = c\.caller });   // granting to oneself|' src/CnbFold.mo

# a grant of at least one share
try cnb-grant-no-shares Compensation \
  sed -i 's|^    if (f\.totalShares == 0 or f\.totalShares >= F\.pow256(W\.QTY)) return #err(#sharesRequired);$|    if (false) return #err(#sharesRequired);|' src/CnbFold.mo

# VESTING OVER ONE TO A HUNDRED AND TWENTY MONTHS
try cnb-grant-months-unbounded Compensation \
  sed -i 's|^    if (f\.vestingMonths < 1 or f\.vestingMonths > MAX_VESTING_MONTHS) return #err(#monthsBound { months = f\.vestingMonths; max = MAX_VESTING_MONTHS });$|    if (false) return #err(#monthsBound { months = f\.vestingMonths; max = MAX_VESTING_MONTHS });|' src/CnbFold.mo

# A CLIFF WITHIN THE VESTING
try cnb-grant-cliff-beyond Compensation \
  sed -i 's|^    if (f\.cliffMonths > f\.vestingMonths) return #err(#cliffBeyondVesting { cliffMonths = f\.cliffMonths; vestingMonths = f\.vestingMonths });$|    if (false) return #err(#cliffBeyondVesting { cliffMonths = f\.cliffMonths; vestingMonths = f\.vestingMonths });|' src/CnbFold.mo

# A CLIFF SCHEDULE VESTS AT ITS CLIFF
try cnb-grant-cliff-not-vesting Compensation \
  sed -i 's|^      case (#cliff) { if (f\.cliffMonths != f\.vestingMonths) return #err(#cliffNotTheVesting { cliffMonths = f\.cliffMonths; vestingMonths = f\.vestingMonths }) };$|      case (#cliff) { if (false) return #err(#cliffNotTheVesting { cliffMonths = f\.cliffMonths; vestingMonths = f\.vestingMonths }) };|' src/CnbFold.mo

# THE PERIOD DIVIDES THE VESTING
try cnb-grant-not-whole Compensation \
  sed -i 's|^      case (_) { let p = periodMonths(f\.schedule); if (f\.vestingMonths % p != 0) return #err(#vestingNotWhole { vestingMonths = f\.vestingMonths; period = p }) };$|      case (_) { let p = periodMonths(f\.schedule); if (false) return #err(#vestingNotWhole { vestingMonths = f\.vestingMonths; period = p }) };|' src/CnbFold.mo

# NOTHING MORE VESTS: refused
try cnb-vest-nothing Compensation \
  sed -i 's|^    if (vested <= g\.vestedShares) return #err(#nothingVests { grantId; vested = g\.vestedShares });$|    if (false) return #err(#nothingVests { grantId; vested = g\.vestedShares });|' src/CnbFold.mo

# THE FIGURE THE SCHEDULE'S
try cnb-vest-not-the-schedule Compensation \
  sed -i 's|^    let vested = vestedOn(g, c\.day);$|    let vested = vestedOn(g, c\.day) + 1;|' src/CnbFold.mo

# NOTHING BEFORE THE CLIFF
try cnb-schedule-no-cliff Compensation \
  sed -i 's|^    if (elapsed < g\.cliffMonths) return 0;$|    if (false) return 0;|' src/CnbFold.mo

# A WHOLE CIVIL MONTH IS WHOLE
try cnb-schedule-partial-month Compensation \
  sed -i 's|^    if (d2 < d1) { if (whole == 0) 0 else whole - 1 } else whole$|    whole|' src/CnbFold.mo

# THE TRANCHES DUE, NO MORE
try cnb-schedule-tranches Compensation \
  sed -i 's|^        if (due == tranches) g\.totalShares else g\.totalShares \* due / tranches$|        if (due == tranches) g\.totalShares else g\.totalShares \* (due + 1) / tranches|' src/CnbFold.mo

# THE HOLDER ALONE EXERCISES
try cnb-exercise-not-holder Compensation \
  sed -i 's|^    if (c\.caller != g\.subject) return #err(#notTheHolder { subject = c\.caller });$|    if (false) return #err(#notTheHolder { subject = c\.caller });|' src/CnbFold.mo

# an exercise of at least one share
try cnb-exercise-no-shares Compensation \
  sed -i 's|^    if (shares == 0) return #err(#sharesRequired);   // exercised$|    if (false) return #err(#sharesRequired);   // exercised|' src/CnbFold.mo

# ONLY WHAT IS VESTED AND UNEXERCISED
try cnb-exercise-unvested Compensation \
  sed -i 's|^    if (shares > available) return #err(#notVested { asked = shares; available });$|    if (false) return #err(#notVested { asked = shares; available });|' src/CnbFold.mo

# exercised whole, the grant is exercised
try cnb-exercise-never-whole Compensation \
  sed -i 's|^    RowStore\.put<CR\.EquityGrant>(c\.cnb\.grants, CR\.equityGrant, grantId, { g with exercisedShares = exercised; state = if (exercised == g\.totalShares) #exercised else #active; lastBlock = c\.block });$|    RowStore\.put<CR\.EquityGrant>(c\.cnb\.grants, CR\.equityGrant, grantId, { g with exercisedShares = exercised; state = #active; lastBlock = c\.block });|' src/CnbFold.mo

# a grant cancelled by somebody else
try cnb-cancel-own Compensation \
  sed -i 's|^    if (c\.caller == g\.subject) return #err(#ownRecord { subject = c\.caller });   // cancelling one'\''s own grant$|    if (false) return #err(#ownRecord { subject = c\.caller });   // cancelling one'\''s own grant|' src/CnbFold.mo

# a cancellation needs a reason
try cnb-cancel-reason Compensation \
  sed -i 's|^    if (Text\.size(reason) == 0) return #err(#reasonRequired { what = "a cancellation" });$|    if (false) return #err(#reasonRequired { what = "a cancellation" });|' src/CnbFold.mo

# an active grant alone vests, exercises, cancels
try cnb-grant-not-active Compensation \
  sed -i 's|^    if (g\.state != #active) return #err(#grantNotActive { grantId });$|    if (false) return #err(#grantNotActive { grantId });|' src/CnbFold.mo

# a plan needs a name
try cnb-plan-name Compensation \
  sed -i 's|^    if (Text\.size(f\.name) == 0) return #err(#nameRequired { what = "an incentive plan" });$|    if (false) return #err(#nameRequired { what = "an incentive plan" });|' src/CnbFold.mo

# A MAXIMUM WITHIN BOUNDS
try cnb-plan-max-unbounded Compensation \
  sed -i 's|^    if (f\.maxBps < 1 or f\.maxBps > MAX_INCENTIVE_BPS) return #err(#maxBpsBound { bps = f\.maxBps; max = MAX_INCENTIVE_BPS });$|    if (false) return #err(#maxBpsBound { bps = f\.maxBps; max = MAX_INCENTIVE_BPS });|' src/CnbFold.mo

# AT MOST EIGHT METRICS
try cnb-plan-too-many Compensation \
  sed -i 's|^    if (f\.metrics\.size() > MAX_METRICS) return #err(#tooManyMetrics { max = MAX_METRICS });$|    if (false) return #err(#tooManyMetrics { max = MAX_METRICS });|' src/CnbFold.mo

# a metric needs a key
try cnb-metric-key Compensation \
  sed -i 's|^      if (Text\.size(f\.metrics\[i\]\.key) == 0) return #err(#metricKeyRequired { ordinal = i + 1 });$|      if (false) return #err(#metricKeyRequired { ordinal = i + 1 });|' src/CnbFold.mo

# NO METRIC TWICE
try cnb-metric-twice Compensation \
  sed -i 's|^      while (j < i) { if (f\.metrics\[j\]\.key == f\.metrics\[i\]\.key) return #err(#metricTwice { key = f\.metrics\[i\]\.key }); j += 1 };$|      while (j < i) { if (false) return #err(#metricTwice { key = f\.metrics\[i\]\.key }); j += 1 };|' src/CnbFold.mo

# WEIGHTS SUM TO TEN THOUSAND
try cnb-weights-not-whole Compensation \
  sed -i 's|^    if (sum != WEIGHTS_WHOLE) return #err(#weightsNotWhole { sum });$|    if (false) return #err(#weightsNotWhole { sum });|' src/CnbFold.mo

# a score against an active plan
try cnb-score-retired-plan Compensation \
  sed -i 's|^    if (not p\.isActive) return #err(#planRetired { planId });$|    if (false) return #err(#planRetired { planId });|' src/CnbFold.mo

# a score of an active employee
try cnb-score-inactive Compensation \
  sed -i 's|^    if (not e\.isActive) return #err(#inactiveEmployee { employeeId });   // the one scored$|    if (false) return #err(#inactiveEmployee { employeeId });   // the one scored|' src/CnbFold.mo

# NOBODY SCORES THEMSELVES
try cnb-score-oneself Compensation \
  sed -i 's|^    if (c\.caller == f\.subject) return #err(#ownRecord { subject = c\.caller });   // scoring oneself$|    if (false) return #err(#ownRecord { subject = c\.caller });   // scoring oneself|' src/CnbFold.mo

# ONE SCORE PER METRIC
try cnb-score-shape Compensation \
  sed -i 's|^    if (f\.scores\.size() != metrics\.size()) return #err(#scoreShape { scores = f\.scores\.size(); metrics = metrics\.size() });$|    if (false) return #err(#scoreShape { scores = f\.scores\.size(); metrics = metrics\.size() });|' src/CnbFold.mo

# A SCORE WITHIN TEN THOUSAND
try cnb-score-unbounded Compensation \
  sed -i 's|^    for (s in f\.scores\.vals()) { if (s > SCORE_MAX) return #err(#scoreBound { score = s; max = SCORE_MAX }) };$|    for (s in f\.scores\.vals()) { if (false) return #err(#scoreBound { score = s; max = SCORE_MAX }) };|' src/CnbFold.mo

# ONCE PER PLAN PER EMPLOYEE PER PERIOD
try cnb-scored-twice Compensation \
  sed -i 's|^      if (sc\.employeeId == employeeId and sc\.periodDay == f\.periodDay) return #err(#alreadyScored { planId = f\.planId; employeeId; periodDay = f\.periodDay });$|      if (false) return #err(#alreadyScored { planId = f\.planId; employeeId; periodDay = f\.periodDay });|' src/CnbFold.mo

# THE FINAL FIGURE THE FOLD'S
try cnb-final-arithmetic Compensation \
  sed -i 's|^    sum \* maxBps / (WEIGHTS_WHOLE \* SCORE_MAX)$|    sum \* maxBps / (WEIGHTS_WHOLE \* SCORE_MAX) + 1|' src/CnbFold.mo

# THE AMOUNT THE FOLD'S
try cnb-amount-arithmetic Compensation \
  sed -i 's|^    let amount = baseMonthly \* finalBps / WEIGHTS_WHOLE;$|    let amount = baseMonthly \* finalBps / WEIGHTS_WHOLE + 1;|' src/CnbFold.mo

# a payment to an active employee
try cnb-payment-inactive Compensation \
  sed -i 's|^    if (not e\.isActive) return #err(#inactiveEmployee { employeeId });   // the payee$|    if (false) return #err(#inactiveEmployee { employeeId });   // the payee|' src/CnbFold.mo

# NOBODY PAYS THEMSELVES
try cnb-payment-to-oneself Compensation \
  sed -i 's|^    if (c\.caller == f\.subject) return #err(#ownRecord { subject = c\.caller });   // paying oneself$|    if (false) return #err(#ownRecord { subject = c\.caller });   // paying oneself|' src/CnbFold.mo

# a payment needs a title
try cnb-payment-title Compensation \
  sed -i 's|^    if (Text\.size(f\.title) == 0) return #err(#nameRequired { what = "a payment" });$|    if (false) return #err(#nameRequired { what = "a payment" });|' src/CnbFold.mo

# A PAYMENT IS OF SOMETHING
try cnb-payment-gross-required Compensation \
  sed -i 's|^    if (f\.gross == 0) return #err(#amountRequired { what = "a payment'\''s gross" });$|    if (false) return #err(#amountRequired { what = "a payment'\''s gross" });|' src/CnbFold.mo

# DEDUCTIONS WITHIN THE GROSS
try cnb-deductions-exceed Compensation \
  sed -i 's|^    if (f\.deductions > f\.gross) return #err(#deductionsExceedGross { gross = f\.gross; deductions = f\.deductions });$|    if (false) return #err(#deductionsExceedGross { gross = f\.gross; deductions = f\.deductions });|' src/CnbFold.mo

# A SCORE PAYS ITS OWN SUBJECT
try cnb-score-not-subjects Compensation \
  sed -i 's|^      if (sc\.subject != f\.subject) return #err(#scoreNotTheSubjects { scoreId = f\.scoreId });$|      if (false) return #err(#scoreNotTheSubjects { scoreId = f\.scoreId });|' src/CnbFold.mo

# A SCORE PAID ONCE
try cnb-score-paid-twice Compensation \
  sed -i 's|^      if (sc\.paymentId != 0) return #err(#scoreAlreadyPaid { scoreId = f\.scoreId; paymentId = sc\.paymentId });$|      if (false) return #err(#scoreAlreadyPaid { scoreId = f\.scoreId; paymentId = sc\.paymentId });|' src/CnbFold.mo

# A SCORE PAID AS A BONUS
try cnb-score-not-bonus Compensation \
  sed -i 's|^      if (f\.kind != #bonus) return #err(#scoreNotABonus { scoreId = f\.scoreId });$|      if (false) return #err(#scoreNotABonus { scoreId = f\.scoreId });|' src/CnbFold.mo

# A SCORE PAID EXACTLY
try cnb-score-amount-differs Compensation \
  sed -i 's|^      if (f\.gross != sc\.amount) return #err(#scoreAmountDiffers { gross = f\.gross; amount = sc\.amount });$|      if (false) return #err(#scoreAmountDiffers { gross = f\.gross; amount = sc\.amount });|' src/CnbFold.mo

# THE NET THE FOLD'S
try cnb-net-arithmetic Compensation \
  sed -i 's|^      net = f\.gross - f\.deductions; scoreId = f\.scoreId; state = #pending; moveId = 0; createdBy = c\.caller; decidedBy = c\.caller; lastBlock = c\.block });$|      net = f\.gross; scoreId = f\.scoreId; state = #pending; moveId = 0; createdBy = c\.caller; decidedBy = c\.caller; lastBlock = c\.block });|' src/CnbFold.mo

# THE PAYEE DOES NOT APPROVE
try cnb-approve-by-payee Compensation \
  sed -i 's|^    if (c\.caller == p\.subject) return #err(#ownRecord { subject = c\.caller });   // approving one'\''s own payment$|    if (false) return #err(#ownRecord { subject = c\.caller });   // approving one'\''s own payment|' src/CnbFold.mo

# a pending payment alone is approved, rejected, cancelled
try cnb-payment-not-pending Compensation \
  sed -i 's|^    if (p\.state != #pending) return #err(#paymentNotInState { paymentId; state = paymentStateName(p\.state); wanted = "pending" });$|    if (false) return #err(#paymentNotInState { paymentId; state = paymentStateName(p\.state); wanted = "pending" });|' src/CnbFold.mo

# THE DEDUCTIONS HELD ON THE LEDGER
try cnb-deductions-not-posted Compensation \
  sed -i 's|^    if (p\.deductions > 0) List\.add(lines, { accountId = policy\.deductionsAccountId; partnerId = 0; name = "off-cycle deductions"; debit = 0; credit = p\.deductions; amountCurrency = 0; taxId = 0 });$|    if (false) List\.add(lines, { accountId = policy\.deductionsAccountId; partnerId = 0; name = "off-cycle deductions"; debit = 0; credit = p\.deductions; amountCurrency = 0; taxId = 0 });|' src/CnbFold.mo

# THE CREATOR DOES NOT REJECT
try cnb-reject-by-creator Compensation \
  sed -i 's|^    if (c\.caller == p\.createdBy) return #err(#sameHands { what = "created"; subject = c\.caller });   // rejecting one'\''s own$|    if (false) return #err(#sameHands { what = "created"; subject = c\.caller });   // rejecting one'\''s own|' src/CnbFold.mo

# a rejection of a payment needs a reason
try cnb-reject-reason Compensation \
  sed -i 's|^    if (Text\.size(reason) == 0) return #err(#reasonRequired { what = "a rejection of a payment" });$|    if (false) return #err(#reasonRequired { what = "a rejection of a payment" });|' src/CnbFold.mo

# A PAYMENT CANCELLED BY ITS CREATOR
try cnb-cancel-by-other Compensation \
  sed -i 's|^    if (c\.caller != p\.createdBy) return #err(#notTheCreator { subject = c\.caller });$|    if (false) return #err(#notTheCreator { subject = c\.caller });|' src/CnbFold.mo

# THE SCORE FREE AGAIN (the one line in the rejection and the cancellation both)
try cnb-score-not-freed Compensation \
  sed -i 's|^    freeScore(c, p\.scoreId);$|    ignore p\.scoreId;|' src/CnbFold.mo

# a loan by an active employee
try cnb-loan-inactive Compensation \
  sed -i 's|^    if (not e\.isActive) return #err(#inactiveEmployee { employeeId });   // the borrower$|    if (false) return #err(#inactiveEmployee { employeeId });   // the borrower|' src/CnbFold.mo

# A LOAN IS OF SOMETHING
try cnb-loan-nothing Compensation \
  sed -i 's|^    if (f\.amount == 0) return #err(#amountRequired { what = "a loan" });$|    if (false) return #err(#amountRequired { what = "a loan" });|' src/CnbFold.mo

# WITHIN A YEAR'S BASE
try cnb-loan-bound Compensation \
  sed -i 's|^    if (f\.amount > baseMonthly \* LOAN_MONTHS or not moneyFits(f\.amount)) return #err(#loanBound { amount = f\.amount; max = baseMonthly \* LOAN_MONTHS });$|    if (false) return #err(#loanBound { amount = f\.amount; max = baseMonthly \* LOAN_MONTHS });|' src/CnbFold.mo

# a loan needs a justification
try cnb-loan-justification Compensation \
  sed -i 's|^    if (Text\.size(f\.justification) == 0) return #err(#reasonRequired { what = "a loan" });$|    if (false) return #err(#reasonRequired { what = "a loan" });|' src/CnbFold.mo

# ONE LOAN OPEN AT A TIME
try cnb-loan-one-open Compensation \
  sed -i 's|^    switch (openLoanOf(c\.cnb, employeeId)) { case (?loanId) return #err(#loanOpen { employeeId; loanId }); case null {} };$|    ignore openLoanOf(c\.cnb, employeeId);|' src/CnbFold.mo

# withdrawn while requested
try cnb-loan-withdrawn-late Compensation \
  sed -i 's|^    if (l\.state != #requested) return #err(#loanNotInState { loanId; state = loanStateName(l\.state); wanted = "requested" });   // withdrawn while requested$|    if (false) return #err(#loanNotInState { loanId; state = loanStateName(l\.state); wanted = "requested" });   // withdrawn while requested|' src/CnbFold.mo

# withdrawn by the borrower
try cnb-loan-withdrawn-by-other Compensation \
  sed -i 's|^    if (c\.caller != l\.subject) return #err(#notTheBorrower { subject = c\.caller });$|    if (false) return #err(#notTheBorrower { subject = c\.caller });|' src/CnbFold.mo

# a loan decided while requested
try cnb-loan-decided-twice Compensation \
  sed -i 's|^    if (l\.state != #requested) return #err(#loanNotInState { loanId; state = loanStateName(l\.state); wanted = "requested" });$|    if (false) return #err(#loanNotInState { loanId; state = loanStateName(l\.state); wanted = "requested" });|' src/CnbFold.mo

# NOBODY DECIDES THEIR OWN LOAN
try cnb-loan-decided-by-borrower Compensation \
  sed -i 's|^    if (c\.caller == l\.subject) return #err(#ownRecord { subject = c\.caller });   // deciding one'\''s own loan$|    if (false) return #err(#ownRecord { subject = c\.caller });   // deciding one'\''s own loan|' src/CnbFold.mo

# APPROVED WITHIN THE REQUEST
try cnb-loan-approved-unbounded Compensation \
  sed -i 's|^    if (approve and (approvedAmount == 0 or approvedAmount > l\.requestedAmount)) return #err(#approvedBound { approved = approvedAmount; requested = l\.requestedAmount });$|    if (false) return #err(#approvedBound { approved = approvedAmount; requested = l\.requestedAmount });|' src/CnbFold.mo

# a rejection of a loan needs a note
try cnb-loan-rejection-note Compensation \
  sed -i 's|^    if (not approve and Text\.size(note) == 0) return #err(#reasonRequired { what = "a rejection of a loan" });$|    if (false) return #err(#reasonRequired { what = "a rejection of a loan" });|' src/CnbFold.mo

# an approved loan is disbursed
try cnb-disburse-unapproved Compensation \
  sed -i 's|^    if (l\.state != #approved) return #err(#loanNotInState { loanId; state = loanStateName(l\.state); wanted = "approved" });$|    if (false) return #err(#loanNotInState { loanId; state = loanStateName(l\.state); wanted = "approved" });|' src/CnbFold.mo

# NOBODY DISBURSES THEIR OWN LOAN
try cnb-disburse-by-borrower Compensation \
  sed -i 's|^    if (c\.caller == l\.subject) return #err(#ownRecord { subject = c\.caller });   // disbursing one'\''s own loan$|    if (false) return #err(#ownRecord { subject = c\.caller });   // disbursing one'\''s own loan|' src/CnbFold.mo

# DISBURSED FROM AN ASSET
try cnb-disburse-from-income Compensation \
  sed -i 's|^    if (cash\.accountType != #asset) return #err(#accountKind { what = "the account disbursed from"; found = accountTypeName(cash\.accountType) });$|    if (false) return #err(#accountKind { what = "the account disbursed from"; found = accountTypeName(cash\.accountType) });|' src/CnbFold.mo

# not from the receivable itself
try cnb-disburse-same-account Compensation \
  sed -i 's|^    if (cashAccountId == policy\.loanReceivableAccountId) return #err(#sameAccount { accountId = cashAccountId });$|    if (false) return #err(#sameAccount { accountId = cashAccountId });|' src/CnbFold.mo

# a disbursed loan is repaid
try cnb-repay-undisbursed Compensation \
  sed -i 's|^    if (l\.state != #disbursed) return #err(#loanNotInState { loanId = f\.loanId; state = loanStateName(l\.state); wanted = "disbursed" });$|    if (false) return #err(#loanNotInState { loanId = f\.loanId; state = loanStateName(l\.state); wanted = "disbursed" });|' src/CnbFold.mo

# NEVER PAST WHAT IS OWED
try cnb-repay-overpaid Compensation \
  sed -i 's|^    if (f\.amount > outstanding) return #err(#overpaid { amount = f\.amount; outstanding });$|    if (false) return #err(#overpaid { amount = f\.amount; outstanding });|' src/CnbFold.mo

# repaid into an asset or a liability
try cnb-repay-into-income Compensation \
  sed -i 's|^    if (cash\.accountType != #asset and cash\.accountType != #liability and cash\.accountType != #payable) return #err(#accountKind { what = "the account repaid into"; found = accountTypeName(cash\.accountType) });$|    if (false) return #err(#accountKind { what = "the account repaid into"; found = accountTypeName(cash\.accountType) });|' src/CnbFold.mo

# not into the receivable itself
try cnb-repay-same-account Compensation \
  sed -i 's|^    if (f\.cashAccountId == policy\.loanReceivableAccountId) return #err(#sameAccount { accountId = f\.cashAccountId });   // repaid$|    if (false) return #err(#sameAccount { accountId = f\.cashAccountId });   // repaid|' src/CnbFold.mo

# THE REPAYMENT ADDED ON THE LOAN
try cnb-repaid-not-added Compensation \
  sed -i 's|^    let repaid = l\.repaid + f\.amount;$|    let repaid = l\.repaid;|' src/CnbFold.mo

# SETTLED WHEN NOTHING IS OWED
try cnb-never-settled Compensation \
  sed -i 's|^    RowStore\.put<CR\.EmployeeLoan>(c\.cnb\.loans, CR\.employeeLoan, f\.loanId, { l with repaid; repayments = l\.repayments + 1; state = if (repaid == l\.approvedAmount) #settled else #disbursed; lastBlock = c\.block });$|    RowStore\.put<CR\.EmployeeLoan>(c\.cnb\.loans, CR\.employeeLoan, f\.loanId, { l with repaid; repayments = l\.repayments + 1; state = #disbursed; lastBlock = c\.block });|' src/CnbFold.mo

# THE INSTALMENTS THE FOLD'S, the remainder on the last
try cnb-instalments-arithmetic Compensation \
  sed -i 's|^    while (k <= n) { List\.add(out, if (k < n) each else amount - each \* (n - 1)); k += 1 };$|    while (k <= n) { List\.add(out, each); k += 1 };|' src/CnbFold.mo

# WHAT IS OWED THE FOLD'S
try cnb-outstanding-arithmetic Compensation \
  sed -i 's|^  public func outstandingOf(l : CR\.EmployeeLoan) : Nat { if (l\.repaid >= l\.approvedAmount) 0 else l\.approvedAmount - l\.repaid };$|  public func outstandingOf(l : CR\.EmployeeLoan) : Nat { if (l\.repaid >= l\.approvedAmount) 0 else l\.approvedAmount };|' src/CnbFold.mo

# THE COMPA-RATIO PER MILLE
try cnb-compa-arithmetic Compensation \
  sed -i 's|^  public func compaRatio(base : Nat, midAmount : Nat) : Nat { if (midAmount == 0) 0 else base \* 1000 / midAmount };$|  public func compaRatio(base : Nat, midAmount : Nat) : Nat { if (midAmount == 0) 0 else base \* 100 / midAmount };|' src/CnbFold.mo

# a benefit plan needs a name
try cnb-benefit-plan-name Compensation \
  sed -i 's|^    if (Text\.size(f\.name) == 0) return #err(#nameRequired { what = "a benefit plan" });$|    if (false) return #err(#nameRequired { what = "a benefit plan" });|' src/CnbFold.mo

# a benefit plan needs a provider
try cnb-benefit-plan-provider Compensation \
  sed -i 's|^    if (Text\.size(f\.provider) == 0) return #err(#nameRequired { what = "a benefit plan'\''s provider" });$|    if (false) return #err(#nameRequired { what = "a benefit plan'\''s provider" });|' src/CnbFold.mo

# A PLAN OFFERS A TIER
try cnb-benefit-no-tier Compensation \
  sed -i 's|^    if (f\.tiers\.size() == 0) return #err(#noTier);$|    if (false) return #err(#noTier);|' src/CnbFold.mo

# NO TIER TWICE
try cnb-tier-twice Compensation \
  sed -i 's|^      if (tierOffered(mask, t)) return #err(#tierTwice { tier = E\.benefitTierText(t) });$|      if (false) return #err(#tierTwice { tier = E\.benefitTierText(t) });|' src/CnbFold.mo

# a plan toggled to what it is not
try cnb-toggle-already Compensation \
  sed -i 's|^    if (p\.isActive == isActive) return #err(#planAlready { planId; isActive });$|    if (false) return #err(#planAlready { planId; isActive });|' src/CnbFold.mo

# a period needs a name
try cnb-period-name Compensation \
  sed -i 's|^    if (Text\.size(f\.name) == 0) return #err(#nameRequired { what = "an enrolment period" });$|    if (false) return #err(#nameRequired { what = "an enrolment period" });|' src/CnbFold.mo

# A PERIOD ENDS NOT BEFORE IT STARTS
try cnb-period-order Compensation \
  sed -i 's|^    if (f\.endDay < f\.startDay) return #err(#periodOrder { startDay = f\.startDay; endDay = f\.endDay });$|    if (false) return #err(#periodOrder { startDay = f\.startDay; endDay = f\.endDay });|' src/CnbFold.mo

# A PERIOD NOT ALREADY PAST
try cnb-period-past Compensation \
  sed -i 's|^    if (f\.endDay < c\.day) return #err(#periodPast { endDay = f\.endDay; today = c\.day });$|    if (false) return #err(#periodPast { endDay = f\.endDay; today = c\.day });|' src/CnbFold.mo

# NO TWO PERIODS OVERLAP
try cnb-period-overlaps Compensation \
  sed -i 's|^      if (p\.startDay <= f\.endDay and f\.startDay <= p\.endDay) return #err(#periodOverlaps { periodId = id });$|      if (false) return #err(#periodOverlaps { periodId = id });|' src/CnbFold.mo

# an enrolment by an active employee
try cnb-enrol-inactive Compensation \
  sed -i 's|^    if (not e\.isActive) return #err(#inactiveEmployee { employeeId });   // the one enrolling$|    if (false) return #err(#inactiveEmployee { employeeId });   // the one enrolling|' src/CnbFold.mo

# AN INACTIVE PLAN TAKES NOBODY
try cnb-enrol-inactive-plan Compensation \
  sed -i 's|^    if (not p\.isActive) return #err(#noSuchBenefitPlan { planId = f\.planId });   // an inactive plan takes nobody$|    if (false) return #err(#noSuchBenefitPlan { planId = f\.planId });   // an inactive plan takes nobody|' src/CnbFold.mo

# A TIER THE PLAN OFFERS
try cnb-enrol-tier-not-offered Compensation \
  sed -i 's|^    if (not tierOffered(p\.tiersMask, f\.tier)) return #err(#tierNotOffered { tier = E\.benefitTierText(f\.tier) });$|    if (false) return #err(#tierNotOffered { tier = E\.benefitTierText(f\.tier) });|' src/CnbFold.mo

# OPEN ON A DAY IS A READ AGAINST THE CALENDAR
try cnb-period-always-open Compensation \
  sed -i 's|^  public func isOpenOn(p : CR\.EnrolmentPeriod, day : Nat) : Bool { p\.startDay <= day and day <= p\.endDay };$|  public func isOpenOn(p : CR\.EnrolmentPeriod, day : Nat) : Bool { true };|' src/CnbFold.mo

# ONE ROW PER EMPLOYEE PER PLAN, standing once
try cnb-enrolled-twice Compensation \
  sed -i 's|^        if (en\.isActive) return #err(#alreadyEnrolled { planId = f\.planId; employeeId });$|        if (false) return #err(#alreadyEnrolled { planId = f\.planId; employeeId });|' src/CnbFold.mo

# waived once
try cnb-waive-not-enrolled Compensation \
  sed -i 's|^    if (not en\.isActive) return #err(#notEnrolled { planId; employeeId });   // waived already$|    if (false) return #err(#notEnrolled { planId; employeeId });   // waived already|' src/CnbFold.mo

# WAIVED WHILE A PERIOD IS OPEN
try cnb-waive-outside-period Compensation \
  sed -i 's|^    if (openPeriodOn(c\.cnb, companyId, c\.day) == null) return #err(#noOpenPeriod { day = c\.day });   // waived in a period$|    if (false) return #err(#noOpenPeriod { day = c\.day });   // waived in a period|' src/CnbFold.mo

# THE COST OVER WHAT STANDS
try cnb-cost-counts-waived Compensation \
  sed -i 's|^      if (en\.isActive) {$|      if (true) {|' src/CnbFold.mo



# ── fleet ─────────────────────────────────────────────────────────────────────
# Every rule the Fleet battery states, removed one at a time from `src/FltFold.mo`.
# Not injected, each defended twice: the logger posting their own cost (the ledger's `checkGenerated` refuses a
# proposer who is the caller).

# every act a member's
# Not injected, and why: fleet-stranger-acts - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# THE VEHICLE EXPENSE AN EXPENSE
try fleet-policy-expense-kind Fleet \
  sed -i 's|^    if (expense\.accountType != #expense) return #err(#accountKind { what = "the vehicle expense"; found = accountTypeName(expense\.accountType) });$|    if (false) return #err(#accountKind { what = "the vehicle expense"; found = accountTypeName(expense\.accountType) });|' src/FltFold.mo

# THE FLEET PAYABLE A PAYABLE
try fleet-policy-payable-kind Fleet \
  sed -i 's|^    if (payable\.accountType != #payable and payable\.accountType != #liability) return #err(#accountKind { what = "the fleet payable"; found = accountTypeName(payable\.accountType) });$|    if (false) return #err(#accountKind { what = "the fleet payable"; found = accountTypeName(payable\.accountType) });|' src/FltFold.mo

# a vehicle needs a plate
try fleet-plate-required Fleet \
  sed -i 's|^    if (Text\.size(f\.plate) == 0) return #err(#nameRequired { what = "a vehicle'\''s plate" });$|    if (false) return #err(#nameRequired { what = "a vehicle'\''s plate" });|' src/FltFold.mo

# a vehicle needs a model
try fleet-model-required Fleet \
  sed -i 's|^    if (Text\.size(f\.model) == 0) return #err(#nameRequired { what = "a vehicle'\''s model" });$|    if (false) return #err(#nameRequired { what = "a vehicle'\''s model" });|' src/FltFold.mo

# an odometer that fits
try fleet-odometer-fits Fleet \
  sed -i 's|^    if (not qtyFits(f\.odometerKm)) return #err(#amountTooLarge { what = "the odometer" });$|    if (false) return #err(#amountTooLarge { what = "the odometer" });|' src/FltFold.mo

# ONE VEHICLE PER PLATE
try fleet-plate-twice Fleet \
  sed -i 's|^    switch (vehicleByPlate(c\.flt, f\.companyId, plate)) { case (?(id, _)) return #err(#plateTaken { vehicleId = id }); case null {} };$|    switch (vehicleByPlate(c\.flt, f\.companyId, plate)) { case (?(_, _)) {}; case null {} };|' src/FltFold.mo

# CARRIED AS AN ASSET NOT DISPOSED OF
try fleet-asset-disposed Fleet \
  sed -i 's|^      if (a\.state == #disposed) return #err(#assetDisposed { assetId = f\.assetId });$|      if (false) return #err(#assetDisposed { assetId = f\.assetId });|' src/FltFold.mo

# ONE VEHICLE PER ASSET
try fleet-asset-twice Fleet \
  sed -i 's|^      for ((id, v) in vehiclesOf(c\.flt, f\.companyId)\.vals()) { if (v\.assetId == f\.assetId) return #err(#assetTaken { assetId = f\.assetId; vehicleId = id }) };$|      for ((id, v) in vehiclesOf(c\.flt, f\.companyId)\.vals()) { if (false) return #err(#assetTaken { assetId = f\.assetId; vehicleId = id }) };|' src/FltFold.mo

# a retired vehicle takes nothing
try fleet-vehicle-retired-used Fleet \
  sed -i 's|^    if (not v\.isActive) return #err(#vehicleRetired { vehicleId });$|    if (false) return #err(#vehicleRetired { vehicleId });|' src/FltFold.mo

# a vehicle is its company's
try fleet-vehicle-wrong-company Fleet \
  sed -i 's|^    if (v\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = v\.companyId });$|    if (false) return #err(#wrongCompany { expected = companyId; found = v\.companyId });|' src/FltFold.mo

# RETIRED WHEN NO DRIVER HOLDS IT
try fleet-retire-while-held Fleet \
  sed -i 's|^    if (v\.driverEmployeeId != 0) return #err(#driverAssigned { vehicleId; employeeId = v\.driverEmployeeId });$|    if (false) return #err(#driverAssigned { vehicleId; employeeId = v\.driverEmployeeId });|' src/FltFold.mo

# a driver is an active employee
try fleet-driver-inactive Fleet \
  sed -i 's|^    if (not e\.isActive) return #err(#inactiveEmployee { employeeId });   // the driver$|    if (false) return #err(#inactiveEmployee { employeeId });   // the driver|' src/FltFold.mo

# A DRIVER ASSIGNED BY SOMEBODY ELSE
try fleet-assign-oneself Fleet \
  sed -i 's|^    if (c\.caller == f\.subject) return #err(#ownRecord { subject = c\.caller });   // assigning oneself$|    if (false) return #err(#ownRecord { subject = c\.caller });   // assigning oneself|' src/FltFold.mo

# ONE DRIVER PER VEHICLE
try fleet-one-driver-per-vehicle Fleet \
  sed -i 's|^    if (v\.driverEmployeeId != 0) return #err(#vehicleHasDriver { vehicleId = f\.vehicleId; employeeId = v\.driverEmployeeId });$|    if (false) return #err(#vehicleHasDriver { vehicleId = f\.vehicleId; employeeId = v\.driverEmployeeId });|' src/FltFold.mo

# ONE VEHICLE PER DRIVER
try fleet-one-vehicle-per-driver Fleet \
  sed -i 's|^    for ((id, other) in vehiclesOf(c\.flt, f\.companyId)\.vals()) { if (other\.driverEmployeeId == employeeId) return #err(#driverHasVehicle { employeeId; vehicleId = id }) };$|    for ((id, other) in vehiclesOf(c\.flt, f\.companyId)\.vals()) { if (false) return #err(#driverHasVehicle { employeeId; vehicleId = id }) };|' src/FltFold.mo

# released where a driver holds it
try fleet-release-nobody Fleet \
  sed -i 's|^    if (v\.driverEmployeeId == 0) return #err(#noDriver { vehicleId });$|    if (false) return #err(#noDriver { vehicleId });|' src/FltFold.mo

# THE READING THE DRIVER'S OWN
try fleet-not-the-driver Fleet \
  sed -i 's|^      case (?e) { if (e\.subject != c\.caller) return ?#notTheDriver { vehicleId; subject = c\.caller } };$|      case (?e) { if (false) return ?#notTheDriver { vehicleId; subject = c\.caller } };|' src/FltFold.mo

# A CONTRACT WITH A SUPPLIER
try fleet-not-a-supplier Fleet \
  sed -i 's|^    if (not c\.isSupplier(f\.companyId, f\.partnerId)) return #err(#notASupplier { partnerId = f\.partnerId });$|    if (false) return #err(#notASupplier { partnerId = f\.partnerId });|' src/FltFold.mo

# A TERM THAT ENDS NOT BEFORE IT STARTS
try fleet-term-order Fleet \
  sed -i 's|^    if (f\.endDay < f\.startDay) return #err(#termOrder { startDay = f\.startDay; endDay = f\.endDay });$|    if (false) return #err(#termOrder { startDay = f\.startDay; endDay = f\.endDay });|' src/FltFold.mo

# a contract has a monthly cost
try fleet-contract-no-cost Fleet \
  sed -i 's|^    if (f\.monthlyCost == 0) return #err(#amountRequired { what = "a contract'\''s monthly cost" });$|    if (false) return #err(#amountRequired { what = "a contract'\''s monthly cost" });|' src/FltFold.mo

# NO TWO OF A KIND OVERLAPPING
try fleet-contracts-overlap Fleet \
  sed -i 's|^      if (k\.state == #active and k\.kind == f\.kind and k\.startDay <= f\.endDay and f\.startDay <= k\.endDay) return #err(#contractOverlaps { contractId = id });$|      if (false) return #err(#contractOverlaps { contractId = id });|' src/FltFold.mo

# a contract cancelled once
try fleet-cancel-twice Fleet \
  sed -i 's|^    if (k\.state != #active) return #err(#contractCancelled { contractId });$|    if (false) return #err(#contractCancelled { contractId });|' src/FltFold.mo

# a cancellation needs a reason
try fleet-cancel-reason Fleet \
  sed -i 's|^    if (Text\.size(reason) == 0) return #err(#reasonRequired { what = "a cancellation of a contract" });$|    if (false) return #err(#reasonRequired { what = "a cancellation of a contract" });|' src/FltFold.mo

# THE ODOMETER NEVER GOES BACKWARDS
try fleet-odometer-backwards Fleet \
  sed -i 's|^    if (f\.reading <= v\.odometerKm) return #err(#odometerBackwards { reading = f\.reading; current = v\.odometerKm });$|    if (false) return #err(#odometerBackwards { reading = f\.reading; current = v\.odometerKm });|' src/FltFold.mo

# THE VEHICLE CARRIES THE LAST READING
try fleet-odometer-not-carried Fleet \
  sed -i 's|^    RowStore\.put<FR\.Vehicle>(c\.flt\.vehicles, FR\.vehicle, f\.vehicleId, { v with odometerKm = f\.reading; lastBlock = c\.block });$|    RowStore\.put<FR\.Vehicle>(c\.flt\.vehicles, FR\.vehicle, f\.vehicleId, { v with lastBlock = c\.block });|' src/FltFold.mo

# A FUELLING NOT BEHIND THE ODOMETER
try fleet-fuel-behind Fleet \
  sed -i 's|^    if (f\.odometer < v\.odometerKm) return #err(#odometerBackwards { reading = f\.odometer; current = v\.odometerKm });   // at the pump$|    if (false) return #err(#odometerBackwards { reading = f\.odometer; current = v\.odometerKm });   // at the pump|' src/FltFold.mo

# A FUELLING OF LITRES
try fleet-fuel-no-litres Fleet \
  sed -i 's|^    if (f\.litres == 0 or not qtyFits(f\.litres)) return #err(#litresRequired);$|    if (false) return #err(#litresRequired);|' src/FltFold.mo

# A FUELLING AT A PRICE
try fleet-fuel-no-price Fleet \
  sed -i 's|^    if (f\.pricePerLitre == 0 or not moneyFits(f\.pricePerLitre)) return #err(#priceRequired);$|    if (false) return #err(#priceRequired);|' src/FltFold.mo

# THE AMOUNT THE FOLD'S
try fleet-fuel-arithmetic Fleet \
  sed -i 's|^  public func fuelAmount(litres : Nat, pricePerLitre : Nat) : Nat { litres \* pricePerLitre / 1000 };$|  public func fuelAmount(litres : Nat, pricePerLitre : Nat) : Nat { litres \* pricePerLitre / 1000 + 1 };|' src/FltFold.mo

# WHAT THE VEHICLE BURNS, THE ARITHMETIC
try fleet-consumption-arithmetic Fleet \
  sed -i 's|^    litres \* 100 / (last - first)$|    litres \* 100 / (last - first) + 1|' src/FltFold.mo

# THE FIRST FUELLING FILLS THE TANK, NOT THE ROAD
try fleet-consumption-counts-first Fleet \
  sed -i 's|^    while (i < logs\.size()) { litres += logs\[i\]\.1\.litres; i += 1 };$|    while (i < logs\.size()) { litres += logs\[i\]\.1\.litres; i += 1 }; litres += logs\[0\]\.1\.litres;|' src/FltFold.mo

# FUEL IS A FUELLING
try fleet-fuel-as-cost Fleet \
  sed -i 's|^    if (f\.kind == #fuel) return #err(#fuelThroughTheLog);$|    if (false) return #err(#fuelThroughTheLog);|' src/FltFold.mo

# a cost is of something
try fleet-cost-nothing Fleet \
  sed -i 's|^    if (f\.amount == 0) return #err(#amountRequired { what = "a vehicle cost" });$|    if (false) return #err(#amountRequired { what = "a vehicle cost" });|' src/FltFold.mo

# A COST NOT AFTER TODAY
try fleet-cost-tomorrow Fleet \
  sed -i 's|^    if (f\.day > c\.day) return #err(#dayInFuture { day = f\.day; today = c\.day });$|    if (false) return #err(#dayInFuture { day = f\.day; today = c\.day });|' src/FltFold.mo

# A CHARGE ON ITS OWN VEHICLE
try fleet-contract-other-vehicle Fleet \
  sed -i 's|^      if (k\.vehicleId != f\.vehicleId) return #err(#contractNotTheVehicles { contractId = f\.contractId; vehicleId = f\.vehicleId });$|      if (false) return #err(#contractNotTheVehicles { contractId = f\.contractId; vehicleId = f\.vehicleId });|' src/FltFold.mo

# A CHARGE WITHIN THE TERM
try fleet-contract-not-in-force Fleet \
  sed -i 's|^      if (not inForceOn(k, f\.day)) return #err(#contractNotInForce { contractId = f\.contractId; day = f\.day });$|      if (false) return #err(#contractNotInForce { contractId = f\.contractId; day = f\.day });|' src/FltFold.mo

# A CHARGE OF THE CONTRACT'S KIND
try fleet-contract-kind Fleet \
  sed -i 's|^      if (f\.kind != E\.contractCostKind(k\.kind)) return #err(#contractKindDiffers { contractId = f\.contractId; kind = E\.vehicleCostKindText(E\.contractCostKind(k\.kind)) });$|      if (false) return #err(#contractKindDiffers { contractId = f\.contractId; kind = E\.vehicleCostKindText(E\.contractCostKind(k\.kind)) });|' src/FltFold.mo

# A CHARGE AT THE CONTRACT'S AMOUNT
try fleet-contract-amount Fleet \
  sed -i 's|^      if (f\.amount != k\.monthlyCost) return #err(#contractAmountDiffers { contractId = f\.contractId; monthlyCost = k\.monthlyCost });$|      if (false) return #err(#contractAmountDiffers { contractId = f\.contractId; monthlyCost = k\.monthlyCost });|' src/FltFold.mo

# ONE CHARGE A CIVIL MONTH
try fleet-month-twice Fleet \
  sed -i 's|^        if (x\.periodMonth == periodMonth and x\.state != #rejected) return #err(#monthAlreadyCharged { contractId = f\.contractId; periodMonth; costId = id });$|        if (false) return #err(#monthAlreadyCharged { contractId = f\.contractId; periodMonth; costId = id });|' src/FltFold.mo

# IN FORCE ON A DAY IS A READ
try fleet-always-in-force Fleet \
  sed -i 's|^  public func inForceOn(k : FR\.VehicleContract, day : Nat) : Bool { k\.state == #active and k\.startDay <= day and day <= k\.endDay };$|  public func inForceOn(k : FR\.VehicleContract, day : Nat) : Bool { k\.state == #active };|' src/FltFold.mo

# a logged cost alone is posted or rejected
try fleet-cost-not-logged Fleet \
  sed -i 's|^    if (x\.state != #logged) return #err(#costNotInState { costId; state = E\.vehicleCostStateText(x\.state); wanted = "logged" });$|    if (false) return #err(#costNotInState { costId; state = E\.vehicleCostStateText(x\.state); wanted = "logged" });|' src/FltFold.mo

# REJECTED BY SOMEBODY WHO DID NOT LOG IT
try fleet-reject-by-logger Fleet \
  sed -i 's|^    if (c\.caller == x\.loggedBy) return #err(#sameHands { what = "logged"; subject = c\.caller });   // rejecting one'\''s own$|    if (false) return #err(#sameHands { what = "logged"; subject = c\.caller });   // rejecting one'\''s own|' src/FltFold.mo

# a rejection needs a reason
try fleet-reject-reason Fleet \
  sed -i 's|^    if (Text\.size(reason) == 0) return #err(#reasonRequired { what = "a rejection of a cost" });$|    if (false) return #err(#reasonRequired { what = "a rejection of a cost" });|' src/FltFold.mo

# THE TOTAL COUNTED ON THE VEHICLE
try fleet-total-not-counted Fleet \
  sed -i 's|^    RowStore\.put<FR\.Vehicle>(c\.flt\.vehicles, FR\.vehicle, x\.vehicleId, { v with postedTotal = v\.postedTotal + x\.amount; lastBlock = c\.block });$|    RowStore\.put<FR\.Vehicle>(c\.flt\.vehicles, FR\.vehicle, x\.vehicleId, { v with postedTotal = v\.postedTotal; lastBlock = c\.block });|' src/FltFold.mo


# ── discussion ────────────────────────────────────────────────────────────────
# Every rule the Discuss battery states, removed one at a time from `src/DscFold.mo` and the indexes of `src/DscRows.mo`.
# Not injected, each defended twice: the company that is not there (nobody is a member of it, so the membership
# refuses first), and a notification that names no record (no table holds a row 0, so the record's own lookup
# refuses it as `#noSuchRelated`).

# every act a member's
# Not injected, and why: dsc-stranger-acts - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# A SLICE IS BOUNDED, at both ends
try dsc-slice-of-nothing Discuss \
  sed -i 's|^    if (limit == 0) return ?(#sliceEmpty);$|    if (false) return ?(#sliceEmpty);|' src/DscFold.mo
try dsc-slice-unbounded Discuss \
  sed -i 's|^    if (limit > MAX_SLICE) return ?(#sliceTooLarge { asked = limit; max = MAX_SLICE });$|    if (false) return ?(#sliceTooLarge { asked = limit; max = MAX_SLICE });|' src/DscFold.mo

# every text bounded
try dsc-text-unbounded Discuss \
  sed -i 's|^    if (Text\.size(t) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });$|    if (false) return #err(#textTooLong { max = MAX_TEXT });|' src/DscFold.mo

# A CHANNEL: one per name, case and space aside, its creator in it with the members named
try dsc-channel-nameless Discuss \
  sed -i 's|^    if (Text\.size(CR\.normalise(f\.name)) == 0) return #err(#nameRequired { what = "a channel'\''s name" });$|    if (false) return #err(#nameRequired { what = "a channel'\''s name" });|' src/DscFold.mo
try dsc-channel-name-twice Discuss \
  sed -i 's|^    switch (channelByName(c\.dsc, f\.companyId, f\.name)) { case (?(id, _)) return #err(#channelNameTaken { channelId = id }); case null {} };$|    switch (channelByName(c.dsc, f.companyId, f.name)) { case (?(_id, _)) {}; case null {} };|' src/DscFold.mo
try dsc-channel-name-case Discuss \
  sed -i 's|^  public func channelNameHash(name : Text) : Blob { Sha256\.fromBlob(#sha256, Text\.encodeUtf8(CR\.normalise(name))) };$|  public func channelNameHash(name : Text) : Blob { Sha256.fromBlob(#sha256, Text.encodeUtf8(name)) };|' src/DscFold.mo
try dsc-channel-crowd Discuss \
  sed -i 's|^    if (f\.members\.size() > MAX_INITIAL_MEMBERS) return #err(#tooManyMembers { max = MAX_INITIAL_MEMBERS });$|    if (false) return #err(#tooManyMembers { max = MAX_INITIAL_MEMBERS });|' src/DscFold.mo
try dsc-channel-creator-named Discuss \
  sed -i 's|^      if (p == c\.caller) return #err(#memberTwice { subject = p });$|      if (false) return #err(#memberTwice { subject = p });|' src/DscFold.mo
try dsc-channel-stranger-named Discuss \
  sed -i 's|^      if (not c\.isMember(f\.companyId, p)) return #err(#notAMemberRecipient { subject = p });$|      if (false) return #err(#notAMemberRecipient { subject = p });|' src/DscFold.mo
try dsc-channel-member-twice Discuss \
  sed -i 's|^      while (j < i) { if (f\.members\[j\] == p) return #err(#memberTwice { subject = p }); j += 1 };$|      while (j < i) { j += 1 };|' src/DscFold.mo
try dsc-channel-members-miscounted Discuss \
  sed -i 's|^      createdBy = c\.caller; members = 1 + f\.members\.size(); messages = 0; lastMessageId = 0; lastBlock = c\.block });$|      createdBy = c.caller; members = 1; messages = 0; lastMessageId = 0; lastBlock = c.block });|' src/DscFold.mo

# THE CHANNEL'S OWN COMPANY, and nobody in an archived one
try dsc-channel-other-company Discuss \
  sed -i 's|^    if (ch\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = ch\.companyId });$|    if (false) return #err(#wrongCompany { expected = companyId; found = ch.companyId });|' src/DscFold.mo
try dsc-archived-open Discuss \
  sed -i 's|^    if (ch\.isArchived) return #err(#channelArchived { channelId });$|    if (false) return #err(#channelArchived { channelId });|' src/DscFold.mo

# ARCHIVED AND REMOVED FROM BY ITS CREATOR (one line, both acts)
try dsc-anyone-archives-or-removes Discuss \
  sed -i 's|^    if (ch\.createdBy != c\.caller) return #err(#notTheCreator { channelId; subject = c\.caller });$|    if (false) return #err(#notTheCreator { channelId; subject = c.caller });|' src/DscFold.mo

# A PRIVATE CHANNEL IS ENTERED ONLY BY BEING ADDED
try dsc-private-joined Discuss \
  sed -i 's|^    if (ch\.isPrivate) return #err(#channelPrivate { channelId });$|    if (false) return #err(#channelPrivate { channelId });|' src/DscFold.mo
try dsc-joined-twice Discuss \
  sed -i 's|^    if (isIn(c\.dsc, channelId, c\.caller)) return #err(#alreadyInChannel { channelId; subject = c\.caller });$|    if (false) return #err(#alreadyInChannel { channelId; subject = c.caller });|' src/DscFold.mo
try dsc-joins-not-counted Discuss \
  sed -i 's|^    RowStore\.put<DR\.Channel>(c\.dsc\.channels, DR\.channel, channelId, { ch with members = ch\.members + 1; lastBlock = c\.block });$|    RowStore.put<DR.Channel>(c.dsc.channels, DR.channel, channelId, { ch with members = ch.members; lastBlock = c.block });|' src/DscFold.mo

# ONLY THOSE IN IT ADD TO IT AND SPEAK IN IT (one line, both acts)
try dsc-outsider-adds-or-speaks Discuss \
  sed -i 's|^    if (not isIn(c\.dsc, channelId, c\.caller)) return #err(#notInChannel { channelId; subject = c\.caller });$|    if (false) return #err(#notInChannel { channelId; subject = c.caller });|' src/DscFold.mo
try dsc-stranger-added Discuss \
  sed -i 's|^    if (not c\.isMember(companyId, subject)) return #err(#notAMemberRecipient { subject });$|    if (false) return #err(#notAMemberRecipient { subject });|' src/DscFold.mo
try dsc-added-twice Discuss \
  sed -i 's|^    if (isIn(c\.dsc, channelId, subject)) return #err(#alreadyInChannel { channelId; subject });$|    if (false) return #err(#alreadyInChannel { channelId; subject });|' src/DscFold.mo

# A CHANNEL KEEPS ONE MEMBER until it is archived
try dsc-taken-out-twice Discuss \
  sed -i 's|^    if (not m\.isActive) return #err(#notInChannel { channelId; subject });$|    if (false) return #err(#notInChannel { channelId; subject });|' src/DscFold.mo
try dsc-last-member-leaves Discuss \
  sed -i 's|^    if (ch\.members <= 1 and not ch\.isArchived) return #err(#lastMember { channelId });$|    if (false) return #err(#lastMember { channelId });|' src/DscFold.mo
try dsc-last-member-stays-archived Discuss \
  sed -i 's|^    if (ch\.members <= 1 and not ch\.isArchived) return #err(#lastMember { channelId });$|    if (ch.members <= 1) return #err(#lastMember { channelId });|' src/DscFold.mo
try dsc-leaving-not-counted Discuss \
  sed -i 's|^    RowStore\.put<DR\.Channel>(c\.dsc\.channels, DR\.channel, channelId, { ch with members = ch\.members - 1; lastBlock = c\.block });$|    RowStore.put<DR.Channel>(c.dsc.channels, DR.channel, channelId, { ch with members = ch.members; lastBlock = c.block });|' src/DscFold.mo
try dsc-creator-removes-themselves Discuss \
  sed -i 's|^    if (subject == c\.caller) return #err(#creatorRemovesThemselves);$|    if (false) return #err(#creatorRemovesThemselves);|' src/DscFold.mo

# A MESSAGE: said in the channel, deleted by its sender alone, the row kept
try dsc-silent-message Discuss \
  sed -i 's|^    if (Text\.size(body) == 0) return #err(#nameRequired { what = "a message" });$|    if (false) return #err(#nameRequired { what = "a message" });|' src/DscFold.mo
try dsc-messages-not-counted Discuss \
  sed -i 's|^    RowStore\.put<DR\.Channel>(c\.dsc\.channels, DR\.channel, channelId, { ch with messages = ch\.messages + 1; lastMessageId = id; lastBlock = c\.block });$|    RowStore.put<DR.Channel>(c.dsc.channels, DR.channel, channelId, { ch with messages = ch.messages; lastBlock = c.block });|' src/DscFold.mo
try dsc-anyone-deletes Discuss \
  sed -i 's|^    if (x\.sender != c\.caller) return #err(#notTheSender { messageId; subject = c\.caller });$|    if (false) return #err(#notTheSender { messageId; subject = c.caller });|' src/DscFold.mo
try dsc-deleted-twice Discuss \
  sed -i 's|^    if (x\.isDeleted) return #err(#messageDeleted { messageId });$|    if (false) return #err(#messageDeleted { messageId });|' src/DscFold.mo
try dsc-deletion-not-kept Discuss \
  sed -i 's|^    RowStore\.put<DR\.ChannelMessage>(c\.dsc\.messages, DR\.channelMessage, messageId, { x with isDeleted = true; deletedBlock = c\.block });$|    RowStore.put<DR.ChannelMessage>(c.dsc.messages, DR.channelMessage, messageId, { x with isDeleted = false; deletedBlock = c.block });|' src/DscFold.mo

# THE READ MARK ONLY MOVES FORWARD, to a message of that channel
try dsc-outsider-marks-read Discuss \
  sed -i 's|^    if (not m\.isActive) return #err(#notInChannel { channelId; subject = c\.caller });$|    if (false) return #err(#notInChannel { channelId; subject = c.caller });|' src/DscFold.mo
try dsc-mark-on-another-channel Discuss \
  sed -i 's|^    if (x\.channelId != channelId) return #err(#messageNotTheChannels { messageId; channelId });$|    if (false) return #err(#messageNotTheChannels { messageId; channelId });|' src/DscFold.mo
try dsc-mark-backwards Discuss \
  sed -i 's|^    if (messageId <= m\.readUpTo) return #err(#readMarkBackwards { messageId; readUpTo = m\.readUpTo });$|    if (false) return #err(#readMarkBackwards { messageId; readUpTo = m.readUpTo });|' src/DscFold.mo
try dsc-unread-counts-own-and-deleted Discuss \
  sed -i 's|^      case (#ok pg) Array\.filter<(Nat, DR\.ChannelMessage)>(pg\.rows, func((_, x)) { not x\.isDeleted and x\.sender != p });$|      case (#ok pg) Array.filter<(Nat, DR.ChannelMessage)>(pg.rows, func((_, x)) { true });|' src/DscFold.mo

# THE AUDIENCE: nobody suspended, named by every field that names anything
try dsc-audience-suspended Discuss \
  sed -i 's|^    if (m\.status == #Terminated or m\.status == #Suspended) return false;$|    if (false) return false;|' src/DscFold.mo
try dsc-audience-any-role Discuss \
  sed -i 's|^    if (a\.roleMask != 0 and (a\.roleMask / roleBit(m\.role)) % 2 == 0) return false;$|    if (false) return false;|' src/DscFold.mo
try dsc-audience-any-department Discuss \
  sed -i 's|^    if (a\.departmentIds\.size() > 0 and not contains(a\.departmentIds, m\.departmentId)) return false;$|    if (false) return false;|' src/DscFold.mo
try dsc-audience-any-title Discuss \
  sed -i 's|^    if (a\.jobTitleIds\.size() > 0 and not contains(a\.jobTitleIds, m\.jobTitleId)) return false;$|    if (false) return false;|' src/DscFold.mo

# STANDING ON A DAY, a read
try dsc-stands-withdrawn Discuss \
  sed -i 's|^    not a\.isWithdrawn and a\.startDay <= day and (a\.endDay == 0 or day <= a\.endDay)$|    a.startDay <= day and (a.endDay == 0 or day <= a.endDay)|' src/DscFold.mo
try dsc-stands-before-start Discuss \
  sed -i 's|^    not a\.isWithdrawn and a\.startDay <= day and (a\.endDay == 0 or day <= a\.endDay)$|    not a.isWithdrawn and (a.endDay == 0 or day <= a.endDay)|' src/DscFold.mo
try dsc-stands-after-end Discuss \
  sed -i 's|^    not a\.isWithdrawn and a\.startDay <= day and (a\.endDay == 0 or day <= a\.endDay)$|    not a.isWithdrawn and a.startDay <= day|' src/DscFold.mo

# AN ANNOUNCEMENT: its window in order and not in the past, its audience recorded and named once
try dsc-announcement-untitled Discuss \
  sed -i 's|^    if (Text\.size(f\.title) == 0) return #err(#nameRequired { what = "an announcement'\''s title" });$|    if (false) return #err(#nameRequired { what = "an announcement'\''s title" });|' src/DscFold.mo
try dsc-announcement-bodiless Discuss \
  sed -i 's|^    if (Text\.size(f\.body) == 0) return #err(#nameRequired { what = "an announcement'\''s body" });$|    if (false) return #err(#nameRequired { what = "an announcement'\''s body" });|' src/DscFold.mo
try dsc-start-zero-not-today Discuss \
  sed -i 's|^    let startDay = if (f\.startDay == 0) c\.day else f\.startDay;$|    let startDay = f.startDay;|' src/DscFold.mo
try dsc-start-past Discuss \
  sed -i 's|^    if (startDay < c\.day) return #err(#dayInPast { day = startDay; today = c\.day });$|    if (false) return #err(#dayInPast { day = startDay; today = c.day });|' src/DscFold.mo
try dsc-start-too-large Discuss \
  sed -i 's|^    if (not dayFits(startDay)) return #err(#dayTooLarge { day = startDay });$|    if (false) return #err(#dayTooLarge { day = startDay });|' src/DscFold.mo
try dsc-window-reversed Discuss \
  sed -i 's|^    if (f\.endDay != 0 and f\.endDay < startDay) return #err(#windowOrder { startDay; endDay = f\.endDay });$|    if (false) return #err(#windowOrder { startDay; endDay = f.endDay });|' src/DscFold.mo
try dsc-audience-location Discuss \
  sed -i 's|^    if (f\.audience\.locations\.size() > 0) return #err(#audienceUnrecorded { field = "location" });$|    if (false) return #err(#audienceUnrecorded { field = "location" });|' src/DscFold.mo
try dsc-audience-nationality Discuss \
  sed -i 's|^    if (f\.audience\.nationalities\.size() > 0) return #err(#audienceUnrecorded { field = "nationality" });$|    if (false) return #err(#audienceUnrecorded { field = "nationality" });|' src/DscFold.mo
try dsc-audience-role-twice Discuss \
  sed -i 's|^      if ((roleMask / roleBit(r)) % 2 == 1) return #err(#audienceNamedTwice { field = "role"; id = Nat8\.toNat(E\.companyRoleByte(r)) });$|      if (false) return #err(#audienceNamedTwice { field = "role"; id = Nat8.toNat(E.companyRoleByte(r)) });|' src/DscFold.mo
try dsc-audience-too-wide Discuss \
  sed -i 's|^    if (ids\.size() > W\.AUDIENCE_SLOTS) return #err(#audienceTooWide { field; max = W\.AUDIENCE_SLOTS });$|    if (false) return #err(#audienceTooWide { field; max = W.AUDIENCE_SLOTS });|' src/DscFold.mo
try dsc-audience-names-nothing Discuss \
  sed -i 's|^      if (not exists(ids\[i\])) return #err(missing(ids\[i\]));$|      if (false) return #err(missing(ids[i]));|' src/DscFold.mo
try dsc-audience-id-twice Discuss \
  sed -i 's|^      while (j < i) { if (ids\[j\] == ids\[i\]) return #err(#audienceNamedTwice { field; id = ids\[i\] }); j += 1 };$|      while (j < i) { j += 1 };|' src/DscFold.mo

# AMENDED, PINNED AND WITHDRAWN: by its author, never while its sweep runs
try dsc-withdrawn-live Discuss \
  sed -i 's|^    if (a\.isWithdrawn) return #err(#announcementWithdrawn { announcementId });$|    if (false) return #err(#announcementWithdrawn { announcementId });|' src/DscFold.mo
try dsc-anyone-amends Discuss \
  sed -i 's|^    if (a\.createdBy != c\.caller) return #err(#notTheAuthor { announcementId = f\.announcementId; subject = c\.caller });$|    if (false) return #err(#notTheAuthor { announcementId = f.announcementId; subject = c.caller });|' src/DscFold.mo
try dsc-amend-end-before-start Discuss \
  sed -i 's|^    if (f\.endDay != 0 and f\.endDay < a\.startDay) return #err(#windowOrder { startDay = a\.startDay; endDay = f\.endDay });$|    if (false) return #err(#windowOrder { startDay = a.startDay; endDay = f.endDay });|' src/DscFold.mo
try dsc-amend-end-past Discuss \
  sed -i 's|^    if (f\.endDay != 0 and f\.endDay < c\.day) return #err(#dayInPast { day = f\.endDay; today = c\.day });$|    if (false) return #err(#dayInPast { day = f.endDay; today = c.day });|' src/DscFold.mo
try dsc-pinned-twice Discuss \
  sed -i 's|^    if (a\.isPinned == isPinned) return #err(#alreadyInState { what = if (isPinned) "pinned" else "unpinned" });$|    if (false) return #err(#alreadyInState { what = if (isPinned) "pinned" else "unpinned" });|' src/DscFold.mo
try dsc-anyone-withdraws Discuss \
  sed -i 's|^    if (a\.createdBy != c\.caller) return #err(#notTheAuthor { announcementId; subject = c\.caller });$|    if (false) return #err(#notTheAuthor { announcementId; subject = c.caller });|' src/DscFold.mo
try dsc-withdrawn-mid-sweep Discuss \
  sed -i 's|^      case (?(runId, run)) { if (run\.state == #running) return #err(#sweepRunning { announcementId; runId }) };$|      case (?(_runId, _run)) {};|' src/DscFold.mo

# A REACTION: the audience's, on a standing announcement, one per emoji, toggled (one line with the sweep's opening)
try dsc-reaction-not-standing Discuss \
  sed -i 's|^    if (not standsOn(a, c\.day)) return #err(#notStanding { announcementId; day = c\.day });$|    if (false) return #err(#notStanding { announcementId; day = c.day });|' src/DscFold.mo
try dsc-reaction-outside-audience Discuss \
  sed -i 's|^    if (not inAudience(a, m)) return #err(#notInAudience { announcementId; subject = c\.caller });$|    if (false) return #err(#notInAudience { announcementId; subject = c.caller });|' src/DscFold.mo
try dsc-reaction-emojiless Discuss \
  sed -i 's|^    if (Text\.size(emoji) == 0) return #err(#emojiRequired);$|    if (false) return #err(#emojiRequired);|' src/DscFold.mo
try dsc-reaction-untoggled Discuss \
  sed -i 's|^        let reactions = if (x\.isActive) a\.reactions - 1 else a\.reactions + 1;$|        let reactions = a.reactions + 1;|' src/DscFold.mo
try dsc-reaction-flag-kept Discuss \
  sed -i 's|^        RowStore\.put<DR\.Reaction>(c\.dsc\.reactions, DR\.reaction, id, { x with isActive = not x\.isActive; lastBlock = c\.block });$|        RowStore.put<DR.Reaction>(c.dsc.reactions, DR.reaction, id, { x with isActive = true; lastBlock = c.block });|' src/DscFold.mo

# THE SWEEP: once per announcement, the company's members in order, the author aside, done when short
try dsc-swept-unasked Discuss \
  sed -i 's|^    if (not a\.notify) return #err(#notNotifying { announcementId });$|    if (false) return #err(#notNotifying { announcementId });|' src/DscFold.mo
try dsc-swept-twice Discuss \
  sed -i 's|^      case (?(runId, _)) return #err(#alreadySwept { announcementId; runId });$|      case (?(_runId, _)) {};|' src/DscFold.mo
try dsc-open-any-plan Discuss \
  sed -i 's|^    if (planHash != expected) return #err(#planHashMismatch { runId = 0 });$|    if (false) return #err(#planHashMismatch { runId = 0 });|' src/DscFold.mo
try dsc-slice-of-other-company Discuss \
  sed -i 's|^    if (run\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = run\.companyId });$|    if (false) return #err(#wrongCompany { expected = companyId; found = run.companyId });|' src/DscFold.mo
try dsc-slice-after-done Discuss \
  sed -i 's|^    if (run\.state != #running) return #err(#runNotRunning { runId });$|    if (false) return #err(#runNotRunning { runId });|' src/DscFold.mo
try dsc-slice-any-plan Discuss \
  sed -i 's|^    if (run\.planHash != planHash) return #err(#planHashMismatch { runId });$|    if (false) return #err(#planHashMismatch { runId });|' src/DscFold.mo
try dsc-author-told Discuss \
  sed -i 's|^      if (m\.subject != a\.createdBy and inAudience(a, m)) {$|      if (inAudience(a, m)) {|' src/DscFold.mo
try dsc-everyone-told Discuss \
  sed -i 's|^      if (m\.subject != a\.createdBy and inAudience(a, m)) {$|      if (m.subject != a.createdBy) {|' src/DscFold.mo
try dsc-cursor-stuck Discuss \
  sed -i 's|^      last := membershipId;$|      last := last;|' src/DscFold.mo
try dsc-done-at-once Discuss \
  sed -i 's|^      state = if (walked\.size() < limit) #done else #running; lastBlock = c\.block });$|      state = if (walked.size() <= limit) #done else #running; lastBlock = c.block });|' src/DscFold.mo
try dsc-never-done Discuss \
  sed -i 's|^      state = if (walked\.size() < limit) #done else #running; lastBlock = c\.block });$|      state = if (false) #done else #running; lastBlock = c.block });|' src/DscFold.mo
try dsc-scanned-not-counted Discuss \
  sed -i 's|^      run with cursor = last; scanned = run\.scanned + walked\.size(); acted = run\.acted + List\.size(ids);$|      run with cursor = last; scanned = run.scanned; acted = run.acted + List.size(ids);|' src/DscFold.mo
try dsc-notified-not-counted Discuss \
  sed -i 's|^    RowStore\.put<DR\.Announcement>(c\.dsc\.announcements, DR\.announcement, run\.announcementId, { a with notified = a\.notified + List\.size(ids); lastBlock = c\.block });$|    RowStore.put<DR.Announcement>(c.dsc.announcements, DR.announcement, run.announcementId, { a with notified = a.notified; lastBlock = c.block });|' src/DscFold.mo
try dsc-pinned-not-high Discuss \
  sed -i 's|^          companyId; recipient = m\.subject; sender = c\.caller; kind = #announcement; priority = if (a\.isPinned) #high else #normal;$|          companyId; recipient = m.subject; sender = c.caller; kind = #announcement; priority = #normal;|' src/DscFold.mo

# A NOTIFICATION: to a member, held to the record its kind reports
try dsc-notification-to-stranger Discuss \
  sed -i 's|^    if (not c\.isMember(f\.companyId, f\.recipient)) return #err(#notAMemberRecipient { subject = f\.recipient });$|    if (false) return #err(#notAMemberRecipient { subject = f.recipient });|' src/DscFold.mo
try dsc-notification-untitled Discuss \
  sed -i 's|^    if (Text\.size(f\.title) == 0) return #err(#nameRequired { what = "a notification'\''s title" });$|    if (false) return #err(#nameRequired { what = "a notification'\''s title" });|' src/DscFold.mo
try dsc-system-names-something Discuss \
  sed -i 's|^    if (f\.kind == #systemNotice) { if (f\.relatedId != 0) return ?#systemNamesNothing { relatedId = f\.relatedId }; return null };$|    if (f.kind == #systemNotice) { return null };|' src/DscFold.mo
try dsc-announcement-told-unstanding Discuss \
  sed -i 's|^      if (a\.companyId != f\.companyId or not standsOn(a, c\.day)) return ?#noSuchRelated { kind; relatedId = f\.relatedId };$|      if (a.companyId != f.companyId) return ?#noSuchRelated { kind; relatedId = f.relatedId };|' src/DscFold.mo
try dsc-announcement-told-outside Discuss \
  sed -i 's|^      if (not inAudience(a, m)) return notParty;$|      if (false) return notParty;|' src/DscFold.mo
try dsc-approval-unapproved Discuss \
  sed -i 's|^      case (#leaveApproved, #leave l) { if (l\.state != #Approved) return ?#noSuchRelated { kind; relatedId = f\.relatedId }; if (l\.decidedBy != c\.caller) return fromWrong; if (l\.subject != f\.recipient) return notParty };$|      case (#leaveApproved, #leave l) { if (l.decidedBy != c.caller) return fromWrong; if (l.subject != f.recipient) return notParty };|' src/DscFold.mo
try dsc-approval-by-anyone Discuss \
  sed -i 's|^      case (#leaveApproved, #leave l) { if (l\.state != #Approved) return ?#noSuchRelated { kind; relatedId = f\.relatedId }; if (l\.decidedBy != c\.caller) return fromWrong; if (l\.subject != f\.recipient) return notParty };$|      case (#leaveApproved, #leave l) { if (l.state != #Approved) return ?#noSuchRelated { kind; relatedId = f.relatedId }; if (l.subject != f.recipient) return notParty };|' src/DscFold.mo
try dsc-approval-to-anyone Discuss \
  sed -i 's|^      case (#leaveApproved, #leave l) { if (l\.state != #Approved) return ?#noSuchRelated { kind; relatedId = f\.relatedId }; if (l\.decidedBy != c\.caller) return fromWrong; if (l\.subject != f\.recipient) return notParty };$|      case (#leaveApproved, #leave l) { if (l.state != #Approved) return ?#noSuchRelated { kind; relatedId = f.relatedId }; if (l.decidedBy != c.caller) return fromWrong; };|' src/DscFold.mo
try dsc-rejection-unrejected Discuss \
  sed -i 's|^      case (#leaveRejected, #leave l) { if (l\.state != #Rejected) return ?#noSuchRelated { kind; relatedId = f\.relatedId }; if (l\.decidedBy != c\.caller) return fromWrong; if (l\.subject != f\.recipient) return notParty };$|      case (#leaveRejected, #leave l) { if (l.decidedBy != c.caller) return fromWrong; if (l.subject != f.recipient) return notParty };|' src/DscFold.mo
try dsc-rejection-by-anyone Discuss \
  sed -i 's|^      case (#leaveRejected, #leave l) { if (l\.state != #Rejected) return ?#noSuchRelated { kind; relatedId = f\.relatedId }; if (l\.decidedBy != c\.caller) return fromWrong; if (l\.subject != f\.recipient) return notParty };$|      case (#leaveRejected, #leave l) { if (l.state != #Rejected) return ?#noSuchRelated { kind; relatedId = f.relatedId }; if (l.subject != f.recipient) return notParty };|' src/DscFold.mo
try dsc-request-undecided Discuss \
  sed -i 's|^      case (#leaveRequest, #leave l) { if (l\.state != #Pending) return ?#noSuchRelated { kind; relatedId = f\.relatedId }; if (l\.subject != c\.caller) return fromWrong; if (l\.subject == f\.recipient) return notParty };$|      case (#leaveRequest, #leave l) { if (l.subject != c.caller) return fromWrong; if (l.subject == f.recipient) return notParty };|' src/DscFold.mo
try dsc-request-by-anyone Discuss \
  sed -i 's|^      case (#leaveRequest, #leave l) { if (l\.state != #Pending) return ?#noSuchRelated { kind; relatedId = f\.relatedId }; if (l\.subject != c\.caller) return fromWrong; if (l\.subject == f\.recipient) return notParty };$|      case (#leaveRequest, #leave l) { if (l.state != #Pending) return ?#noSuchRelated { kind; relatedId = f.relatedId }; if (l.subject == f.recipient) return notParty };|' src/DscFold.mo
try dsc-request-to-oneself Discuss \
  sed -i 's|^      case (#leaveRequest, #leave l) { if (l\.state != #Pending) return ?#noSuchRelated { kind; relatedId = f\.relatedId }; if (l\.subject != c\.caller) return fromWrong; if (l\.subject == f\.recipient) return notParty };$|      case (#leaveRequest, #leave l) { if (l.state != #Pending) return ?#noSuchRelated { kind; relatedId = f.relatedId }; if (l.subject != c.caller) return fromWrong; };|' src/DscFold.mo
try dsc-payslip-to-anyone Discuss \
  sed -i 's|^      case (#payrollProcessed, #payslip p) { if (p\.subject != f\.recipient) return notParty };$|      case (#payrollProcessed, #payslip p) { };|' src/DscFold.mo
try dsc-review-to-anyone Discuss \
  sed -i 's|^      case (#performanceReview, #review r) { if (r\.subject != f\.recipient) return notParty };$|      case (#performanceReview, #review r) { };|' src/DscFold.mo
try dsc-task-to-anyone Discuss \
  sed -i 's|^      case (#taskAssigned, #task t) { if (t\.assignee != f\.recipient) return notParty };$|      case (#taskAssigned, #task t) { };|' src/DscFold.mo
try dsc-invite-cancelled Discuss \
  sed -i 's|^      case (#meetingInvite, #booking b) { if (b\.isCancelled) return ?#noSuchRelated { kind; relatedId = f\.relatedId }; if (b\.bookedBy != c\.caller) return fromWrong };$|      case (#meetingInvite, #booking b) { if (b.bookedBy != c.caller) return fromWrong };|' src/DscFold.mo
try dsc-invite-by-anyone Discuss \
  sed -i 's|^      case (#meetingInvite, #booking b) { if (b\.isCancelled) return ?#noSuchRelated { kind; relatedId = f\.relatedId }; if (b\.bookedBy != c\.caller) return fromWrong };$|      case (#meetingInvite, #booking b) { if (b.isCancelled) return ?#noSuchRelated { kind; relatedId = f.relatedId }; };|' src/DscFold.mo

# READ, MARKED ALL READ AND DISMISSED BY ITS RECIPIENT ALONE
try dsc-anyone-reads Discuss \
  sed -i 's|^    if (n\.recipient != c\.caller) return #err(#notTheRecipient { notificationId; subject = c\.caller });$|    if (false) return #err(#notTheRecipient { notificationId; subject = c.caller });|' src/DscFold.mo
try dsc-dismissed-read Discuss \
  sed -i 's|^    if (n\.isDismissed) return #err(#notificationDismissed { notificationId });$|    if (false) return #err(#notificationDismissed { notificationId });|' src/DscFold.mo
try dsc-read-twice Discuss \
  sed -i 's|^    if (n\.isRead) return #err(#alreadyRead { notificationId });$|    if (false) return #err(#alreadyRead { notificationId });|' src/DscFold.mo
try dsc-mark-all-unbounded Discuss \
  sed -i 's|^    let rows = switch (unreadNotificationsOf(c\.dsc, companyId, c\.caller, limit)) { case (#err _) \[\]; case (#ok pg) pg\.rows };$|    let rows = switch (unreadNotificationsOf(c.dsc, companyId, c.caller, MAX_SLICE)) { case (#err _) []; case (#ok pg) pg.rows };|' src/DscFold.mo
try dsc-dismissal-not-kept Discuss \
  sed -i 's|^    RowStore\.put<DR\.Notification>(c\.dsc\.notifications, DR\.notification, notificationId, { n with isDismissed = true });$|    RowStore.put<DR.Notification>(c.dsc.notifications, DR.notification, notificationId, { n with isDismissed = false });|' src/DscFold.mo

# the indexes the reads walk
try dsc-unread-index-keeps-read Discuss \
  sed -i 's|^        keyOf = func(id : Nat, x : Notification) : ?Blob { if (not x\.isRead and not x\.isDismissed) ?personKey(x\.companyId, x\.recipient, id) else null } },$|        keyOf = func(id : Nat, x : Notification) : ?Blob { if (not x.isDismissed) ?personKey(x.companyId, x.recipient, id) else null } },|' src/DscRows.mo
try dsc-active-index-keeps-gone Discuss \
  sed -i 's|^        keyOf = func(id : Nat, x : ChannelMember) : ?Blob { if (x\.isActive) ?PR\.pairKey(x\.channelId, id) else null } },$|        keyOf = func(id : Nat, x : ChannelMember) : ?Blob { ?PR.pairKey(x.channelId, id) } },|' src/DscRows.mo
try dsc-person-index-keeps-gone Discuss \
  sed -i 's|^        keyOf = func(id : Nat, x : ChannelMember) : ?Blob { if (x\.isActive) ?personKey(x\.companyId, x\.subject, id) else null } },$|        keyOf = func(id : Nat, x : ChannelMember) : ?Blob { ?personKey(x.companyId, x.subject, id) } },|' src/DscRows.mo
try dsc-reaction-index-keeps-gone Discuss \
  sed -i 's|^        keyOf = func(id : Nat, x : Reaction) : ?Blob { if (x\.isActive) ?PR\.pairKey(x\.announcementId, id) else null } },$|        keyOf = func(id : Nat, x : Reaction) : ?Blob { ?PR.pairKey(x.announcementId, id) } },|' src/DscRows.mo

# ── knowledge ─────────────────────────────────────────────────────────────────
# Every rule the Knowledge battery states, removed one at a time from `src/KbFold.mo` and the indexes of `src/KbRows.mo`.
# Not injected: the company that is not there, defended twice (nobody is a member of it, so the membership
# refuses first); and the lookups of a document, an article and a version that are not there, each a `let … else`
# with no row to go on with, so the fold has no path without it that compiles.

# every act a member's
# Not injected, and why: kb-stranger-acts - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).

# every text bounded
try kb-text-unbounded Knowledge \
  sed -i 's|^    if (Text\.size(t) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });$|    if (false) return #err(#textTooLong { max = MAX_TEXT });|' src/KbFold.mo

# A VERSION: a title, at most four tags each normalised, a word, at most sixteen bytes, reading back as written, named once (the title's line is the opening's and the revision's alike)
try kb-untitled Knowledge \
  sed -i 's|^    if (Text\.size(f\.title) == 0) return #err(#nameRequired { what = "an article'\''s title" });$|    if (false) return #err(#nameRequired { what = "an article'\''s title" });|' src/KbFold.mo
try kb-tags-unbounded Knowledge \
  sed -i 's|^    if (tags\.size() > W\.KB_TAGS) return #err(#tooManyTags { max = W\.KB_TAGS });$|    if (false) return #err(#tooManyTags { max = W.KB_TAGS });|' src/KbFold.mo
try kb-tags-unnormalised Knowledge \
  sed -i 's|^      let n = CR\.normalise(t);$|      let n = t;|' src/KbFold.mo
try kb-tag-empty Knowledge \
  sed -i 's|^      if (Text\.size(n) == 0) return #err(#tagRequired);$|      if (false) return #err(#tagRequired);|' src/KbFold.mo
try kb-tag-unbounded-bytes Knowledge \
  sed -i 's|^      let ?field = F\.textField(n, W\.CODE) else return #err(#tagDoesNotFit { tag = n; max = W\.CODE });$|      let ?field = F.textField(n, 4 * W.CODE) else return #err(#tagDoesNotFit { tag = n; max = W.CODE });|' src/KbFold.mo
try kb-tag-reads-back-other Knowledge \
  sed -i 's|^      if (F\.textOfField(field) != ?n) return #err(#tagDoesNotFit { tag = n; max = W\.CODE });$|      if (false) return #err(#tagDoesNotFit { tag = n; max = W.CODE });|' src/KbFold.mo
try kb-tag-twice Knowledge \
  sed -i 's|^      for (seen in out\.vals()) { if (seen == field) return #err(#tagTwice { tag = n }) };$|      for (seen in out.vals()) { ignore seen };|' src/KbFold.mo

# A VERSION'S WORDS: a company document of the company, active, the caller's upload, no other version's
try kb-document-other-company Knowledge \
  sed -i 's|^    if (d\.companyId != companyId) return ?#wrongCompany { expected = companyId; found = d\.companyId };$|    if (false) return ?#wrongCompany { expected = companyId; found = d.companyId };|' src/KbFold.mo
try kb-document-not-company Knowledge \
  sed -i 's|^    if (d\.kind != #company) return ?#documentNotShared { documentId };$|    if (false) return ?#documentNotShared { documentId };|' src/KbFold.mo
try kb-document-inactive Knowledge \
  sed -i 's|^    if (d\.state != #active) return ?#documentNotActive { documentId };$|    if (false) return ?#documentNotActive { documentId };|' src/KbFold.mo
try kb-document-not-uploader Knowledge \
  sed -i 's|^    if (d\.uploadedBy != c\.caller) return ?#notTheUploader { documentId; subject = c\.caller };$|    if (false) return ?#notTheUploader { documentId; subject = c.caller };|' src/KbFold.mo
try kb-document-twice Knowledge \
  sed -i 's|^      case (?(_, v)) return ?#documentAlreadyAVersion { documentId; articleId = v\.articleId };$|      case (?(_, _v)) {};|' src/KbFold.mo
try kb-version-author Knowledge \
  sed -i 's|^      author = c\.caller; day = c\.day; lastBlock = c\.block });$|      author = Principal.fromBlob("\\04"); day = c.day; lastBlock = c.block });|' src/KbFold.mo
try kb-version-day Knowledge \
  sed -i 's|^      author = c\.caller; day = c\.day; lastBlock = c\.block });$|      author = c.caller; day = 0; lastBlock = c.block });|' src/KbFold.mo

# THE FIRST VERSION OPENS A DRAFT
try kb-first-version-not-one Knowledge \
  sed -i 's|^    let versionId = switch (writeVersion(c, articleId, 1, f, tags)) { case (#ok id) id; case (#err e) return #err(e) };$|    let versionId = switch (writeVersion(c, articleId, 2, f, tags)) { case (#ok id) id; case (#err e) return #err(e) };|' src/KbFold.mo
try kb-opened-published Knowledge \
  sed -i 's|^      companyId = f\.companyId; category = f\.category; tags; state = #draft; createdBy = c\.caller; versions = 1;$|      companyId = f.companyId; category = f.category; tags; state = #published; createdBy = c.caller; versions = 1;|' src/KbFold.mo

# THE ARTICLE'S OWN COMPANY
try kb-article-other-company Knowledge \
  sed -i 's|^    if (a\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = a\.companyId });$|    if (false) return #err(#wrongCompany { expected = companyId; found = a.companyId });|' src/KbFold.mo

# THE NEXT VERSION: of an article not archived; a draft takes it at once, a published article keeps its own
try kb-archived-revised Knowledge \
  sed -i 's|^    if (a\.state == #archived) return #err(#articleArchived { articleId });$|    if (false) return #err(#articleArchived { articleId });|' src/KbFold.mo
try kb-revision-not-counted Knowledge \
  sed -i 's|^    RowStore\.put<KR\.Article>(c\.kb\.articles, KR\.article, articleId, { a with versions = number; category; tags = shown; lastBlock = c\.block });$|    RowStore.put<KR.Article>(c.kb.articles, KR.article, articleId, { a with versions = a.versions; category; tags = shown; lastBlock = c.block });|' src/KbFold.mo
try kb-published-takes-new-category Knowledge \
  sed -i 's|^    let (category, shown) = if (a\.state == #draft) (f\.category, tags) else (a\.category, a\.tags);$|    let (category, shown) = (f.category, tags);|' src/KbFold.mo
try kb-draft-keeps-old-category Knowledge \
  sed -i 's|^    let (category, shown) = if (a\.state == #draft) (f\.category, tags) else (a\.category, a\.tags);$|    let (category, shown) = (a.category, a.tags);|' src/KbFold.mo

# PUBLISHED BY SOMEBODY WHO DID NOT WRITE IT, its document active; the article carries the version's category and tags
try kb-republished-same Knowledge \
  sed -i 's|^    if (a\.state == #published and a\.publishedVersion == number) return #err(#alreadyPublished { articleId; number });$|    if (false) return #err(#alreadyPublished { articleId; number });|' src/KbFold.mo
try kb-author-publishes Knowledge \
  sed -i 's|^    if (v\.author == c\.caller) return #err(#authorPublishes { articleId; number; subject = c\.caller });$|    if (false) return #err(#authorPublishes { articleId; number; subject = c.caller });|' src/KbFold.mo
try kb-erased-published Knowledge \
  sed -i 's|^    if (d\.state != #active) return #err(#documentNotActive { documentId = v\.documentId });$|    if (false) return #err(#documentNotActive { documentId = v.documentId });|' src/KbFold.mo
try kb-publish-keeps-category Knowledge \
  sed -i 's|^      a with state = #published; publishedVersion = number; publishedDay = c\.day; category = v\.category; tags = v\.tags; lastBlock = c\.block });$|      a with state = #published; publishedVersion = number; publishedDay = c.day; category = a.category; tags = a.tags; lastBlock = c.block });|' src/KbFold.mo
try kb-publish-day Knowledge \
  sed -i 's|^      a with state = #published; publishedVersion = number; publishedDay = c\.day; category = v\.category; tags = v\.tags; lastBlock = c\.block });$|      a with state = #published; publishedVersion = number; publishedDay = a.publishedDay; category = v.category; tags = v.tags; lastBlock = c.block });|' src/KbFold.mo
try kb-publish-version Knowledge \
  sed -i 's|^      a with state = #published; publishedVersion = number; publishedDay = c\.day; category = v\.category; tags = v\.tags; lastBlock = c\.block });$|      a with state = #published; publishedVersion = a.versions; publishedDay = c.day; category = v.category; tags = v.tags; lastBlock = c.block });|' src/KbFold.mo

# ARCHIVED BY A MEMBER, and for no reader
try kb-archived-twice Knowledge \
  sed -i 's|^    if (a\.state == #archived) return #err(#alreadyArchived { articleId });$|    if (false) return #err(#alreadyArchived { articleId });|' src/KbFold.mo
try kb-archive-not-kept Knowledge \
  sed -i 's|^    RowStore\.put<KR\.Article>(c\.kb\.articles, KR\.article, articleId, { a with state = #archived; lastBlock = c\.block });$|    RowStore.put<KR.Article>(c.kb.articles, KR.article, articleId, { a with state = a.state; lastBlock = c.block });|' src/KbFold.mo

# A VIEW once, of a published article, with the version read
try kb-unpublished-read Knowledge \
  sed -i 's|^    if (a\.state != #published) return #err(#notPublished { articleId });$|    if (false) return #err(#notPublished { articleId });|' src/KbFold.mo
try kb-viewed-twice Knowledge \
  sed -i 's|^    switch (viewOf(c\.kb, articleId, c\.caller)) { case (?_) return #err(#alreadyViewed { articleId; subject = c\.caller }); case null {} };$|    switch (viewOf(c.kb, articleId, c.caller)) { case (?_) {}; case null {} };|' src/KbFold.mo
try kb-view-version Knowledge \
  sed -i 's|^      companyId; articleId; viewer = c\.caller; version = a\.publishedVersion; day = c\.day; lastBlock = c\.block });$|      companyId; articleId; viewer = c.caller; version = a.versions; day = c.day; lastBlock = c.block });|' src/KbFold.mo
try kb-views-not-counted Knowledge \
  sed -i 's|^    RowStore\.put<KR\.Article>(c\.kb\.articles, KR\.article, articleId, { a with views = a\.views + 1; lastBlock = c\.block });$|    RowStore.put<KR.Article>(c.kb.articles, KR.article, articleId, { a with views = a.views; lastBlock = c.block });|' src/KbFold.mo

# A VOTE: one per member, never the published version's author's, moved
try kb-author-votes Knowledge \
  sed -i 's|^    if (v\.author == c\.caller) return #err(#authorVotes { articleId; subject = c\.caller });$|    if (false) return #err(#authorVotes { articleId; subject = c.caller });|' src/KbFold.mo
try kb-same-vote-twice Knowledge \
  sed -i 's|^        if (x\.isHelpful == isHelpful) return #err(#alreadyVoted { articleId; isHelpful });$|        if (false) return #err(#alreadyVoted { articleId; isHelpful });|' src/KbFold.mo
try kb-vote-not-moved Knowledge \
  sed -i 's|^        RowStore\.put<KR\.Vote>(c\.kb\.votes, KR\.vote, id, { x with isHelpful; lastBlock = c\.block });$|        RowStore.put<KR.Vote>(c.kb.votes, KR.vote, id, { x with lastBlock = c.block });|' src/KbFold.mo
try kb-moved-vote-added Knowledge \
  sed -i 's|^        let (helpful, notHelpful) = if (isHelpful) (a\.helpful + 1, a\.notHelpful - 1) else (a\.helpful - 1, a\.notHelpful + 1);$|        let (helpful, notHelpful) = if (isHelpful) (a.helpful + 1, a.notHelpful) else (a.helpful, a.notHelpful + 1);|' src/KbFold.mo
try kb-new-vote-miscounted Knowledge \
  sed -i 's|^        let (helpful, notHelpful) = if (isHelpful) (a\.helpful + 1, a\.notHelpful) else (a\.helpful, a\.notHelpful + 1);$|        let (helpful, notHelpful) = if (isHelpful) (a.helpful, a.notHelpful + 1) else (a.helpful + 1, a.notHelpful);|' src/KbFold.mo

# the indexes: what a reader looks through is published, by its category; the articles in a state
try kb-published-index-keeps-drafts Knowledge \
  sed -i 's|^        keyOf = func(id : Nat, x : Article) : ?Blob { if (x\.state == #published) ?categoryKey(x\.companyId, x\.category, id) else null } },$|        keyOf = func(id : Nat, x : Article) : ?Blob { ?categoryKey(x.companyId, x.category, id) } },|' src/KbRows.mo
try kb-published-index-one-category Knowledge \
  sed -i 's|^        keyOf = func(id : Nat, x : Article) : ?Blob { if (x\.state == #published) ?categoryKey(x\.companyId, x\.category, id) else null } },$|        keyOf = func(id : Nat, x : Article) : ?Blob { if (x.state == #published) ?categoryKey(x.companyId, #hr, id) else null } },|' src/KbRows.mo
try kb-state-index-one-state Knowledge \
  sed -i 's|^        keyOf = func(id : Nat, x : Article) : ?Blob { ?stateKey(x\.companyId, x\.state, id) } },$|        keyOf = func(id : Nat, x : Article) : ?Blob { ?stateKey(x.companyId, #published, id) } },|' src/KbRows.mo

# ── the tombstone walk (src/Lookup.mo, test/Tombstones.test.mo) ────────────────

# THE WALK STOPS AT ITS FIRST PAGE: every lookup in the tree is the bare page again
try walk-stops-at-one-page Tombstones   sed -i 's|^              cursor := ?k;$|              return #ok({ rows = List.toArray(out); next = ?k; examined });|' src/Lookup.mo

# and one site at a time, each read put back to one page from the head
try close-latest-from-the-head Tombstones   sed -i 's|Lookup\.upTo<AR\.CloseRun>(st\.closeRuns, AR\.closeRun, "by_closed", lo, hi, 1)|RowStore.page<AR.CloseRun>(st.closeRuns, AR.closeRun, "by_closed", lo, hi, null, 1)|' src/AcctFold.mo
try import-run-from-the-head Tombstones   sed -i 's|Lookup\.upTo<PR\.ImportRun>(c\.ppl\.runs, PR\.importRun, "by_kind_state", lo, hi, 1)|RowStore.page<PR.ImportRun>(c.ppl.runs, PR.importRun, "by_kind_state", lo, hi, null, 1)|' src/PeopleFold.mo
try match-run-from-the-head Tombstones   sed -i 's|Lookup\.upTo<FR\.MatchRun>(c\.fin\.runs, FR\.matchRun, "by_kind_state", lo, hi, 1)|RowStore.page<FR.MatchRun>(c.fin.runs, FR.matchRun, "by_kind_state", lo, hi, null, 1)|' src/FinFold.mo
try account-of-a-type-from-the-head Tombstones   sed -i 's|Lookup\.upTo<AR\.Account>(c\.acct\.accounts, AR\.account, "by_type", lo, hi, 1)|RowStore.page<AR.Account>(c.acct.accounts, AR.account, "by_type", lo, hi, null, 1)|' src/ProjFold.mo
try mail-in-flight-from-the-head Tombstones   sed -i 's|Lookup\.upTo<CR\.MailingRecipient>(c\.crm\.recipients, CR\.mailingRecipient, "by_state", lo, hi, 1)|RowStore.page<CR.MailingRecipient>(c.crm.recipients, CR.mailingRecipient, "by_state", lo, hi, null, 1)|' src/CrmFold.mo
try text-in-flight-from-the-head Tombstones   sed -i 's|Lookup\.upTo<SR\.SmsRecipient>(st\.recipients, SR\.smsRecipient, "by_state", lo, hi, 1)|RowStore.page<SR.SmsRecipient>(st.recipients, SR.smsRecipient, "by_state", lo, hi, null, 1)|' src/SmsFold.mo

# ── policies, compliance, the dashboard and the figures (src/GovFold.mo, test/Governance.test.mo) ───────────────
# Not injected, each defended twice: a company that does not exist (every act's member check refuses it as no
# member first); the acknowledgement's width (a fingerprint not of 32 bytes cannot equal the 64-hex fingerprint the
# register keeps); a stranger's policy (the document's own uploader check refuses it first); the let-else lookups,
# whose absence does not compile; a certification's holder who is not a member (a certification of the company is
# its employee's, whose membership the employee register requires).

# THE BOUND OF A TEXT, AND WHO GOVERNS
try gov-text-unbounded Governance \
  sed -i 's|^    if (Text\.size(t) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });$|    if (false) return #err(#textTooLong { max = MAX_TEXT });|' src/GovFold.mo
try gov-admin-not-a-governor Governance \
  sed -i 's|^      case (?#CompanyAdmin) null;$|      case (?#CompanyAdmin) ?#notAGovernor { subject = c.caller };|' src/GovFold.mo
try gov-hr-not-a-governor Governance \
  sed -i 's|^      case (?#HR) null;$|      case (?#HR) ?#notAGovernor { subject = c.caller };|' src/GovFold.mo
try gov-anyone-governs Governance \
  sed -i 's|^      case _ ?#notAGovernor { subject = c\.caller };$|      case _ null;|' src/GovFold.mo

# A VERSION'S WORDS: a company document of the company, active, the writer's own upload, no other version's
try gov-document-other-company Governance \
  sed -i 's|^    if (d\.companyId != companyId) return ?#wrongCompany { expected = companyId; found = d\.companyId };$|    if (false) return ?#wrongCompany { expected = companyId; found = d.companyId };|' src/GovFold.mo
try gov-document-not-shared Governance \
  sed -i 's|^    if (d\.kind != #company) return ?#documentNotShared { documentId };$|    if (false) return ?#documentNotShared { documentId };|' src/GovFold.mo
try gov-document-inactive Governance \
  sed -i 's|^    if (d\.state != #active) return ?#documentNotActive { documentId };$|    if (false) return ?#documentNotActive { documentId };|' src/GovFold.mo
try gov-document-not-uploader Governance \
  sed -i 's|^    if (d\.uploadedBy != c\.caller) return ?#notTheUploader { documentId; subject = c\.caller };$|    if (false) return ?#notTheUploader { documentId; subject = c.caller };|' src/GovFold.mo
try gov-document-twice Governance \
  sed -i 's|^      case (?(_, v)) return ?#documentAlreadyAVersion { documentId; policyId = v\.policyId };$|      case (?(_, _v)) {};|' src/GovFold.mo
try gov-title-required Governance \
  sed -i 's|^    if (Text\.size(f\.title) == 0) return ?#nameRequired { what = "a policy|    if (false) return ?#nameRequired { what = "a policy|' src/GovFold.mo
try gov-day-unbounded Governance \
  sed -i 's|^    if (f\.effectiveDay > maxDay()) return ?#dayTooLarge { day = f\.effectiveDay };$|    if (false) return ?#dayTooLarge { day = f.effectiveDay };|' src/GovFold.mo
try gov-first-version-not-one Governance \
  sed -i 's|^    let versionId = switch (writeVersion(c, policyId, 1, f)) { case (#ok id) id; case (#err e) return #err(e) };$|    let versionId = switch (writeVersion(c, policyId, 2, f)) { case (#ok id) id; case (#err e) return #err(e) };|' src/GovFold.mo
try gov-version-acks-not-zero Governance \
  sed -i '/func writeVersion/,/^  };/ s|acks = 0;|acks = 1;|' src/GovFold.mo

# THE POLICY'S OWN COMPANY; the next version of a policy not archived
try gov-policy-other-company Governance \
  sed -i 's|^    if (p\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = p\.companyId });$|    if (false) return #err(#wrongCompany { expected = companyId; found = p.companyId });|' src/GovFold.mo
try gov-archived-revised Governance \
  sed -i 's|^    if (p\.state == #archived) return #err(#policyArchived { policyId });$|    if (false) return #err(#policyArchived { policyId });|' src/GovFold.mo

# PUBLISHED BY A GOVERNOR WHO DID NOT WRITE IT, its words active, at most sixteen owed; it carries the version's acknowledgements
try gov-republished-same Governance \
  sed -i 's|^    if (p\.state == #published and p\.publishedVersion == number) return #err(#alreadyPublished { policyId; number });$|    if (false) return #err(#alreadyPublished { policyId; number });|' src/GovFold.mo
try gov-author-publishes Governance \
  sed -i 's|^    if (v\.author == c\.caller) return #err(#authorPublishes { policyId; number; subject = c\.caller });$|    if (false) return #err(#authorPublishes { policyId; number; subject = c.caller });|' src/GovFold.mo
try gov-archived-words-published Governance \
  sed -i 's|^    if (d\.state != #active) return #err(#documentNotActive { documentId = v\.documentId });$|    if (false) return #err(#documentNotActive { documentId = v.documentId });|' src/GovFold.mo
try gov-owed-unbounded Governance \
  sed -i 's|^    if (v\.requiresAck and not alreadyOwed and owedIn(c\.gov, companyId)\.size() >= MAX_OWED) return #err(#tooManyOwed { max = MAX_OWED });$|    if (false) return #err(#tooManyOwed { max = MAX_OWED });|' src/GovFold.mo
try gov-owed-counts-itself Governance \
  sed -i 's|^    let alreadyOwed = p\.state == #published and p\.requiresAck;$|    let alreadyOwed = false;|' src/GovFold.mo
try gov-publish-acks-reset Governance \
  sed -i 's|^      effectiveDay = v\.effectiveDay; acks = v\.acks; lastBlock = c\.block });$|      effectiveDay = v.effectiveDay; acks = 0; lastBlock = c.block });|' src/GovFold.mo
try gov-publish-keeps-version Governance \
  sed -i 's|^      p with state = #published; publishedVersion = number; publishedDay = c\.day;|      p with state = #published; publishedVersion = p.publishedVersion; publishedDay = c.day;|' src/GovFold.mo
try gov-publish-keeps-ack Governance \
  sed -i 's|category = v\.category; requiresAck = v\.requiresAck;$|category = v.category; requiresAck = p.requiresAck;|' src/GovFold.mo
try gov-archived-twice Governance \
  sed -i 's|^    if (p\.state == #archived) return #err(#alreadyArchived { policyId });$|    if (false) return #err(#alreadyArchived { policyId });|' src/GovFold.mo
try gov-archive-not-kept Governance \
  sed -i 's|^    RowStore\.put<GR\.Policy>(c\.gov\.policies, GR\.policy, policyId, { p with state = #archived; lastBlock = c\.block });$|    RowStore.put<GR.Policy>(c.gov.policies, GR.policy, policyId, { p with lastBlock = c.block });|' src/GovFold.mo

# AN ACKNOWLEDGEMENT of the version published, of its words, once; counted on the version and on the policy
try gov-ack-unpublished Governance \
  sed -i 's|^    if (p\.state != #published) return #err(#notPublished { policyId });$|    if (false) return #err(#notPublished { policyId });|' src/GovFold.mo
try gov-ack-not-asked Governance \
  sed -i 's|^    if (not p\.requiresAck) return #err(#noAcknowledgementAsked { policyId });$|    if (false) return #err(#noAcknowledgementAsked { policyId });|' src/GovFold.mo
try gov-ack-other-version Governance \
  sed -i 's|^    if (number != p\.publishedVersion) return|    if (false) return|' src/GovFold.mo
try gov-ack-other-words Governance \
  sed -i 's|^    if (Text\.toLower(C\.hex(plainHash)) != Text\.toLower(d\.plainHash)) return|    if (false) return|' src/GovFold.mo
try gov-ack-twice Governance \
  sed -i 's|^    switch (ackOf(c\.gov, policyId, number, c\.caller)) { case (?_) return #err(#alreadyAcknowledged { policyId; number; subject = c\.caller }); case null {} };$|    switch (ackOf(c.gov, policyId, number, c.caller)) { case (?_) {}; case null {} };|' src/GovFold.mo
try gov-ack-version-not-counted Governance \
  sed -i 's|{ v with acks = v\.acks + 1; lastBlock = c\.block });$|{ v with lastBlock = c.block });|' src/GovFold.mo
try gov-ack-policy-not-counted Governance \
  sed -i 's|{ p with acks = v\.acks + 1; lastBlock = c\.block });$|{ p with acks = v.acks; lastBlock = c.block });|' src/GovFold.mo
try gov-ack-other-member Governance \
  sed -i 's|{ companyId; policyId; number; member = c\.caller; plainHash;|{ companyId; policyId; number; member = p.createdBy; plainHash;|' src/GovFold.mo

# A REQUIREMENT: roles, each once; a title; ten years at most; sixteen in force; of the company; retired once
try gov-roles-required Governance \
  sed -i 's|^    if (roles\.size() == 0) return #err(#rolesRequired);$|    if (false) return #err(#rolesRequired);|' src/GovFold.mo
try gov-role-twice Governance \
  sed -i 's|^      if (holdsRole(mask, r)) return #err(#roleTwice|      if (false) return #err(#roleTwice|' src/GovFold.mo
try gov-requirement-title-required Governance \
  sed -i 's|^    if (Text\.size(f\.title) == 0) return #err(#nameRequired { what = "a requirement|    if (false) return #err(#nameRequired { what = "a requirement|' src/GovFold.mo
try gov-validity-unbounded Governance \
  sed -i 's|^    if (f\.validityDays > MAX_VALIDITY_DAYS) return|    if (false) return|' src/GovFold.mo
try gov-requirements-unbounded Governance \
  sed -i 's|^    if (activeRequirements(c\.gov, f\.companyId)\.size() >= MAX_REQUIREMENTS) return|    if (false) return|' src/GovFold.mo
try gov-requirement-other-company Governance \
  sed -i 's|^    if (r\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = r\.companyId });$|    if (false) return #err(#wrongCompany { expected = companyId; found = r.companyId });|' src/GovFold.mo
try gov-retired-twice Governance \
  sed -i '/public func retireRequirement/,/^  };/ s|^    if (r\.state == #retired) return #err(#requirementRetired { requirementId });$|    if (false) return #err(#requirementRetired { requirementId });|' src/GovFold.mo
try gov-retire-not-kept Governance \
  sed -i 's|{ r with state = #retired; lastBlock = c\.block });$|{ r with lastBlock = c.block });|' src/GovFold.mo

# A CITATION by somebody else, of the company's certification not revoked, of the kind, for a role held, moved once
try gov-retired-cited Governance \
  sed -i '/public func citeCertification/,/^  };/ s|^    if (r\.state == #retired) return #err(#requirementRetired { requirementId });$|    if (false) return #err(#requirementRetired { requirementId });|' src/GovFold.mo
try gov-cert-other-company Governance \
  sed -i 's|^    if (cert\.companyId != companyId) return|    if (false) return|' src/GovFold.mo
try gov-cert-revoked Governance \
  sed -i 's|^    if (cert\.state == #revoked) return #err(#certificationRevoked { certificationId });$|    if (false) return #err(#certificationRevoked { certificationId });|' src/GovFold.mo
try gov-cert-wrong-kind Governance \
  sed -i 's|^    if (cert\.kind != r\.certKind) return|    if (false) return|' src/GovFold.mo
try gov-own-citation Governance \
  sed -i 's|^    if (cert\.subject == c\.caller) return #err(#ownCitation { subject = c\.caller });$|    if (false) return #err(#ownCitation { subject = c.caller });|' src/GovFold.mo
try gov-role-not-held Governance \
  sed -i 's|^    if (not holdsRole(r\.roleMask, role)) return #err(#roleNotHeld|    if (false) return #err(#roleNotHeld|' src/GovFold.mo
try gov-cited-twice Governance \
  sed -i 's|^        if (x\.certificationId == certificationId) return #err(#alreadyCited|        if (false) return #err(#alreadyCited|' src/GovFold.mo
try gov-citation-not-moved Governance \
  sed -i 's|{ x with certificationId; citedBy = c\.caller; day = c\.day; lastBlock = c\.block });$|{ x with citedBy = c.caller; day = c.day; lastBlock = c.block });|' src/GovFold.mo

# A MEMBER'S DASHBOARD: sixteen widgets, each a word of sixteen bytes that reads back as itself, once; shown in order
try gov-widgets-unbounded Governance \
  sed -i 's|^    if (widgets\.size() > W\.GOV_WIDGETS) return|    if (false) return|' src/GovFold.mo
try gov-widget-required Governance \
  sed -i 's|^      if (Text\.size(n) == 0) return #err(#widgetRequired);$|      if (false) return #err(#widgetRequired);|' src/GovFold.mo
try gov-widget-reads-as-another Governance \
  sed -i 's|^      if (F\.textOfField(field) != ?n) return|      if (false) return|' src/GovFold.mo
try gov-widget-twice Governance \
  sed -i 's|^      for (seen in fields\.vals()) { if (seen == field) return #err(#widgetTwice { widget = n }) };$|      for (seen in fields.vals()) { if (false) return #err(#widgetTwice { widget = n }) };|' src/GovFold.mo
try gov-widget-all-shown Governance \
  sed -i 's|^      if (visible) mask += 2 \*\* i;$|      mask += 2 ** i;|' src/GovFold.mo
try gov-same-layout Governance \
  sed -i 's|^        if (x\.widgets == fields and x\.visibleMask == mask) return #err(#sameLayout);$|        if (false) return #err(#sameLayout);|' src/GovFold.mo
try gov-layout-not-replaced Governance \
  sed -i 's|{ x with widgets = fields; visibleMask = mask; lastBlock = c\.block });$|{ x with lastBlock = c.block });|' src/GovFold.mo

# A RUN: one at a time; slices of one to sixteen; of the company; never after it is published
try gov-run-twice Governance \
  sed -i 's|^    switch (runningRun(c\.gov, companyId)) { case (?(id, _)) return #err(#runRunning { runId = id }); case null {} };$|    switch (runningRun(c.gov, companyId)) { case (?_) {}; case null {} };|' src/GovFold.mo
try gov-slice-empty Governance \
  sed -i 's|^    if (limit == 0) return #err(#sliceEmpty);$|    if (false) return #err(#sliceEmpty);|' src/GovFold.mo
try gov-slice-unbounded Governance \
  sed -i 's|^    if (limit > MAX_SLICE) return|    if (false) return|' src/GovFold.mo
try gov-run-other-company Governance \
  sed -i 's|^    if (run\.companyId != companyId) return|    if (false) return|' src/GovFold.mo
try gov-run-finished Governance \
  sed -i 's|^    if (run\.state == #finished) return #err(#runFinished { runId });$|    if (false) return #err(#runFinished { runId });|' src/GovFold.mo

# THE MEMBERS PHASE: the active, each role, every requirement required, every owed policy
try gov-suspended-counted Governance \
  sed -i 's|^        if (active) {$|        if (true) {|' src/GovFold.mo
try gov-optional-counted Governance \
  sed -i 's|^            if (r\.isRequired) {$|            if (true) {|' src/GovFold.mo
try gov-compliant-as-expiring Governance \
  sed -i 's|case (#compliant) bump(figures, GR\.F_COMPLIANT, 1);|case (#compliant) bump(figures, GR.F_EXPIRING, 1);|' src/GovFold.mo
try gov-expiring-as-compliant Governance \
  sed -i 's|case (#expiring) bump(figures, GR\.F_EXPIRING, 1);|case (#expiring) bump(figures, GR.F_COMPLIANT, 1);|' src/GovFold.mo
try gov-expired-as-missing Governance \
  sed -i 's|case (#expired) bump(figures, GR\.F_EXPIRED, 1);|case (#expired) bump(figures, GR.F_MISSING, 1);|' src/GovFold.mo
try gov-missing-as-expired Governance \
  sed -i 's|case (#missing) bump(figures, GR\.F_MISSING, 1);|case (#missing) bump(figures, GR.F_EXPIRED, 1);|' src/GovFold.mo
try gov-acked-as-owed Governance \
  sed -i 's|case (?_) bump(figures, GR\.F_ACKED, 1);|case (?_) bump(figures, GR.F_OWED, 1);|' src/GovFold.mo
try gov-employees-skipped Governance \
  sed -i 's|^      if (pg\.done) { phase := GR\.PHASE_EMPLOYEES; cursor := 0 };$|      if (pg.done) { phase := GR.PHASE_POSTINGS; cursor := 0 };|' src/GovFold.mo
try gov-phase-cursor-kept Governance \
  sed -i 's|^      if (w\.done) { phase += 1; cursor := 0 };$|      if (w.done) { phase += 1 };|' src/GovFold.mo
try gov-run-never-published Governance \
  sed -i 's|^    let finished = phase == GR\.PHASE_DONE;$|    let finished = false;|' src/GovFold.mo

# WHERE A PERSON STANDS: the role held, the certification not revoked, the earlier of its expiry and the validity
try gov-every-role-held Governance \
  sed -i 's|^    if (not holdsRole(r\.roleMask, role)) return #notApplicable;$|    if (false) return #notApplicable;|' src/GovFold.mo
try gov-revoked-stands Governance \
  sed -i 's|^    if (cert\.state == #revoked) return #missing;$|    if (false) return #missing;|' src/GovFold.mo
try gov-validity-ignored Governance \
  sed -i 's|^    let byValidity = if (r\.validityDays == 0) 0 else cert\.issuedDay + r\.validityDays;$|    let byValidity = 0;|' src/GovFold.mo
try gov-later-of-the-two Governance \
  sed -i 's|Nat\.min(cert\.expiryDay, byValidity)|Nat.max(cert.expiryDay, byValidity)|' src/GovFold.mo
try gov-never-expired Governance \
  sed -i 's|^    if (until != 0 and until < day) return #expired;$|    if (false) return #expired;|' src/GovFold.mo
try gov-no-window Governance \
  sed -i 's|^    if (until != 0 and until <= day + EXPIRING_DAYS) return #expiring;$|    if (false) return #expiring;|' src/GovFold.mo

# THE LATER PHASES, each table's own filter (src/State.mo)
try gov-inactive-employees-counted Governance \
  sed -i 's|^            if (e\.isActive) \[(GovRows\.F_EMPLOYEES, 1)|            if (true) [(GovRows.F_EMPLOYEES, 1)|' src/State.mo
try gov-seniority-misread Governance \
  sed -i 's|(GovRows\.F_SENIORITY + Nat8\.toNat(E\.seniorityByte(e\.seniority)) - 1, 1)|(GovRows.F_SENIORITY, 1)|' src/State.mo
try gov-draft-postings-counted Governance \
  sed -i 's|func(x) { if (x\.state == #open) \[(GovRows\.F_POSTINGS, 1)\] else \[\] })|func(_x) { [(GovRows.F_POSTINGS, 1)] })|' src/State.mo
try gov-cancelled-tasks-counted Governance \
  sed -i 's|if (x\.state != #done and x\.state != #cancelled) \[(GovRows\.F_TASKS, 1)\]|if (x.state != #done) [(GovRows.F_TASKS, 1)]|' src/State.mo
try gov-every-leave-counted Governance \
  sed -i 's|func(x) { if (x\.state == #Pending) \[(GovRows\.F_LEAVES, 1)\] else \[\] })|func(_x) { [(GovRows.F_LEAVES, 1)] })|' src/State.mo
try gov-erased-candidates-counted Governance \
  sed -i 's|func(x) { if (x\.erasedDay == 0) \[(GovRows\.F_CANDIDATES, 1)\] else \[\] })|func(_x) { [(GovRows.F_CANDIDATES, 1)] })|' src/State.mo
try gov-cancelled-meetings-counted Governance \
  sed -i 's|if (x\.state != #cancelled and x\.day >= runDay) \[(GovRows\.F_MEETINGS, 1)\]|if (x.day >= runDay) [(GovRows.F_MEETINGS, 1)]|' src/State.mo
try gov-past-meetings-counted Governance \
  sed -i 's|if (x\.state != #cancelled and x\.day >= runDay) \[(GovRows\.F_MEETINGS, 1)\]|if (x.state != #cancelled) [(GovRows.F_MEETINGS, 1)]|' src/State.mo
try gov-walk-one-short Governance \
  sed -i 's|          { lastId = last; done = pg\.next == null; adds = List\.toArray(adds) }$|          { lastId = last; done = true; adds = List.toArray(adds) }|' src/State.mo

# ── approval workflows (src/WfFold.mo, src/State.mo; test/Workflow.test.mo and each chained kind's own battery) ──
# Not injected, each defended twice: a company that does not exist (the member check refuses it as no member
# first); the let-else lookups, whose absence does not compile; a record of another company, which the reader of
# every kind filters and which no request can name since a cycle and its records are of one company; a linked
# request naming record 0 (no table holds a row 0, so the record's own lookup refuses it first); and the gate's
# company check (a record's id is its table's own, and a request is started only about a record of its company, so
# a live request about a record is always of the record's company).

# A CYCLE: by a governor, named, one to six steps, the kind's one active cycle; retired once, by a governor, of its company
try wf-admin-not-a-governor Workflow \
  sed -i 's|^      case (?#CompanyAdmin) null;$|      case (?#CompanyAdmin) ?#notAGovernor { subject = c.caller };|' src/WfFold.mo
try wf-hr-not-a-governor Workflow \
  sed -i 's|^      case (?#HR) null;$|      case (?#HR) ?#notAGovernor { subject = c.caller };|' src/WfFold.mo
try wf-anyone-governs Workflow \
  sed -i 's|^      case _ ?#notAGovernor { subject = c\.caller };$|      case _ null;|' src/WfFold.mo
try wf-text-unbounded Workflow \
  sed -i 's|^    if (Text\.size(t) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });$|    if (false) return #err(#textTooLong { max = MAX_TEXT });|' src/WfFold.mo
try wf-cycle-name-required Workflow \
  sed -i 's|^    if (Text\.size(f\.name) == 0) return #err(#nameRequired|    if (false) return #err(#nameRequired|' src/WfFold.mo
try wf-steps-required Workflow \
  sed -i 's|^    if (f\.steps\.size() == 0) return #err(#stepsRequired);$|    if (false) return #err(#stepsRequired);|' src/WfFold.mo
try wf-steps-unbounded Workflow \
  sed -i 's|^    if (f\.steps\.size() > W\.WF_STEPS) return|    if (false) return|' src/WfFold.mo
try wf-old-cycle-kept-active Workflow \
  sed -i 's|^      case (?(id, old)) RowStore\.put<WR\.Cycle>(c\.wf\.cycles, WR\.cycle, id, { old with isActive = false; lastBlock = c\.block });$|      case (?(id, old)) RowStore.put<WR.Cycle>(c.wf.cycles, WR.cycle, id, { old with lastBlock = c.block });|' src/WfFold.mo
try wf-cycle-other-company Workflow \
  sed -i 's|^    if (cy\.companyId != companyId) return|    if (false) return|' src/WfFold.mo
try wf-retired-twice Workflow \
  sed -i 's|^    if (not cy\.isActive) return #err(#cycleRetired { cycleId });$|    if (false) return #err(#cycleRetired { cycleId });|' src/WfFold.mo
try wf-retire-not-kept Workflow \
  sed -i 's|^    RowStore\.put<WR\.Cycle>(c\.wf\.cycles, WR\.cycle, cycleId, { cy with isActive = false; lastBlock = c\.block });$|    RowStore.put<WR.Cycle>(c.wf.cycles, WR.cycle, cycleId, { cy with lastBlock = c.block });|' src/WfFold.mo

# A REQUEST: through the active cycle; a linked kind names a pending record of the requester's, one request at a time
try wf-settled-record-asked Workflow \
  sed -i '/public func startApproval/,/^  };/ s|^      if (not rec\.pending) return|      if (false) return|' src/WfFold.mo
try wf-anyone-asks Workflow \
  sed -i 's|^        case (?p) { if (p != c\.caller) return #err(#notTheRequester|        case (?p) { if (false) return #err(#notTheRequester|' src/WfFold.mo
try wf-two-in-flight Workflow \
  sed -i 's|^      switch (liveRequest(c\.wf, f\.kind, f\.recordId)) { case (?(id, _)) return #err(#requestInFlight { instanceId = id }); case null {} };$|      switch (liveRequest(c.wf, f.kind, f.recordId)) { case (?_) {}; case null {} };|' src/WfFold.mo
try wf-general-names-record Workflow \
  sed -i 's|^      if (f\.recordId != 0) return #err(#recordNamed|      if (false) return #err(#recordNamed|' src/WfFold.mo
try wf-general-about-nothing Workflow \
  sed -i 's|^      if (Text\.size(f\.subject) == 0) return #err(#nameRequired|      if (false) return #err(#nameRequired|' src/WfFold.mo
try wf-steps-not-copied Workflow \
  sed -i 's|requester = c\.caller; steps = cy\.steps;$|requester = c.caller; steps = [#CompanyAdmin];|' src/WfFold.mo
try wf-starts-at-two Workflow \
  sed -i 's|^      currentStep = 1; state = #pending; day = c\.day; decidedDay = 0; lastBlock = c\.block });$|      currentStep = 2; state = #pending; day = c.day; decidedDay = 0; lastBlock = c.block });|' src/WfFold.mo
try wf-request-other-company Workflow \
  sed -i 's|^    if (i\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = i\.companyId });$|    if (false) return #err(#wrongCompany { expected = companyId; found = i.companyId });|' src/WfFold.mo
try wf-decided-request-again Workflow \
  sed -i 's|^    if (i\.state != #pending) return #err(#requestNotPending|    if (false) return #err(#requestNotPending|' src/WfFold.mo

# WHO DECIDES: never the requester; the step's role in one's own name, or a standing delegation's; nobody twice
try wf-requester-decides Workflow \
  sed -i 's|^    if (c\.caller == i\.requester) return #err(#requesterDecides|    if (false) return #err(#requesterDecides|' src/WfFold.mo
try wf-lapsed-delegation-stands Workflow \
  sed -i 's|if (stands(d, c\.day) and d\.from != i\.requester and|if (d.state == #active and d.from != i.requester and|' src/WfFold.mo
try wf-requester-delegates Workflow \
  sed -i 's|if (stands(d, c\.day) and d\.from != i\.requester and|if (stands(d, c.day) and|' src/WfFold.mo
try wf-delegator-role-unread Workflow \
  sed -i 's|and c\.roleOf(i\.companyId, d\.from) == ?role) { found := ?d\.from; break scan };|) { found := ?d.from; break scan };|' src/WfFold.mo
try wf-decider-twice Workflow \
  sed -i 's|^          if (d\.decidedBy == c\.caller or d\.onBehalfOf == c\.caller) return|          if (false) return|' src/WfFold.mo
try wf-principal-twice Workflow \
  sed -i 's|^          if (d\.decidedBy == onBehalfOf or d\.onBehalfOf == onBehalfOf) return|          if (false) return|' src/WfFold.mo
try wf-behalf-is-the-caller Workflow \
  sed -i 's|^    #ok(onBehalfOf)$|    #ok(c.caller)|' src/WfFold.mo
try wf-stands-before-it-starts Workflow \
  sed -i 's|d\.state == #active and day <= d\.untilDay and day >= d\.fromDay|d.state == #active and day >= d.fromDay|' src/WfFold.mo

# A STEP DECIDED: a linked kind's last is its domain's; a record settled since is decided no longer; a rejection has its reason
try wf-last-step-decided-here Workflow \
  sed -i 's|^    if (approve and last and E\.approvalKindIsLinked(i\.kind)) return|    if (false) return|' src/WfFold.mo
try wf-settled-record-decided Workflow \
  sed -i '/public func decideApprovalStep/,/^  };/ s|^        case (?rec) { if (not rec\.pending) return|        case (?rec) { if (false) return|' src/WfFold.mo
try wf-reason-not-required Workflow \
  sed -i 's|^    if (not approve and Text\.size(note) == 0) return #err(#reasonRequired);$|    if (false) return #err(#reasonRequired);|' src/WfFold.mo
try wf-decision-order Workflow \
  sed -i 's|companyId = i\.companyId; instanceId; order = i\.currentStep; decidedBy = c\.caller;|companyId = i.companyId; instanceId; order = 1; decidedBy = c.caller;|' src/WfFold.mo
try wf-decision-not-counted Workflow \
  sed -i 's|^    c\.wf\.nextDecisionId += 1;$|    c.wf.nextDecisionId += 0;|' src/WfFold.mo
try wf-rejection-carries-on Workflow \
  sed -i 's|^    let next = if (not approve) { { i with state = #rejected; decidedDay = c\.day; lastBlock = c\.block } }$|    let next = if (false) { { i with state = #rejected; decidedDay = c.day; lastBlock = c.block } }|' src/WfFold.mo
try wf-last-approval-carries-on Workflow \
  sed -i 's|^      else if (last) { { i with state = #approved; decidedDay = c\.day; lastBlock = c\.block } }$|      else if (false) { { i with state = #approved; decidedDay = c.day; lastBlock = c.block } }|' src/WfFold.mo
try wf-step-not-moved Workflow \
  sed -i 's|^      else { { i with currentStep = i\.currentStep + 1; lastBlock = c\.block } };$|      else { { i with lastBlock = c.block } };|' src/WfFold.mo
try wf-withdrawn-by-anyone Workflow \
  sed -i 's|^    if (i\.requester != c\.caller) return #err(#notTheRequester|    if (false) return #err(#notTheRequester|' src/WfFold.mo
try wf-withdraw-not-kept Workflow \
  sed -i 's|{ i with state = #withdrawn; decidedDay = c\.day; lastBlock = c\.block });$|{ i with decidedDay = c.day; lastBlock = c.block });|' src/WfFold.mo

# THE DOMAIN'S GATE: approving waits for a request at its last step, decided by somebody who may; rejecting never waits
try wf-gate-rejection-waits Workflow \
  sed -i 's|^        if (not approve) return #ok(#chain { instanceId; onBehalfOf = c\.caller });$|        if (false) return #ok(#chain { instanceId; onBehalfOf = c.caller });|' src/WfFold.mo
try wf-gate-early-step Workflow \
  sed -i 's|^        if (i\.currentStep != i\.steps\.size()) return|        if (false) return|' src/WfFold.mo
try wf-gate-authority-unread Workflow \
  sed -i 's|^          case (#err e) #err(e);$|          case (#err _) #ok(#chain { instanceId; onBehalfOf = c.caller });|' src/WfFold.mo
try wf-gate-no-cycle-read Workflow \
  sed -i 's|^        if (approve and activeCycle(c\.wf, companyId, kind) != null) return|        if (false) return|' src/WfFold.mo
try wf-gate-rejection-held-without-request Workflow \
  sed -i 's|^        if (approve and activeCycle(c\.wf, companyId, kind) != null) return|        if (activeCycle(c.wf, companyId, kind) != null) return|' src/WfFold.mo
try wf-close-approves-rejections Workflow \
  sed -i 's|i with state = if (approve) #approved else #rejected; decidedDay = c\.day; lastBlock = c\.block });|i with state = #approved; decidedDay = c.day; lastBlock = c.block });|' src/WfFold.mo
try wf-close-writes-no-decision Workflow \
  sed -i 's|^        ignore writeDecision(c, instanceId, i, onBehalfOf, approve, TA\.EMPTY);$|        ignore (instanceId, onBehalfOf);|' src/WfFold.mo
try wf-closed-on-refusal Refusals \
  sed -i 's|^          switch (o) { case (#ok _) WfFold\.close(wfCtx, g, approve); case (#err _) {} };$|          WfFold.close(wfCtx, g, approve);|' src/State.mo

# A DELEGATION: to another member, from today to at most a year and a day on, one standing at a time; revoked by its giver
try wf-delegate-self Workflow \
  sed -i 's|^    if (delegate == c\.caller) return #err(#delegateIsSelf);$|    if (false) return #err(#delegateIsSelf);|' src/WfFold.mo
try wf-delegate-stranger Workflow \
  sed -i 's|^    if (not c\.isMember(companyId, delegate)) return|    if (false) return|' src/WfFold.mo
try wf-delegation-in-past Workflow \
  sed -i 's|^    if (untilDay < c\.day) return #err(#dayInPast|    if (false) return #err(#dayInPast|' src/WfFold.mo
try wf-delegation-unbounded Workflow \
  sed -i 's|^    if (untilDay - c\.day > MAX_DELEGATION_DAYS) return|    if (false) return|' src/WfFold.mo
try wf-two-delegations Workflow \
  sed -i 's|^        if (stands(d, c\.day)) return #err(#delegationStands { delegationId = id });$|        if (false) return #err(#delegationStands { delegationId = id });|' src/WfFold.mo
try wf-old-delegation-not-lapsed Workflow \
  sed -i 's|{ d with state = #lapsed; lastBlock = c\.block });$|{ d with lastBlock = c.block });|' src/WfFold.mo
try wf-delegation-from-tomorrow Workflow \
  sed -i 's|companyId; from = c\.caller; to = delegate; fromDay = c\.day; untilDay;|companyId; from = c.caller; to = delegate; fromDay = c.day + 1; untilDay;|' src/WfFold.mo
try wf-delegation-other-company Workflow \
  sed -i 's|^    if (d\.companyId != companyId) return|    if (false) return|' src/WfFold.mo
try wf-revoked-by-delegate Workflow \
  sed -i 's|^    if (d\.from != c\.caller) return #err(#notTheDelegator|    if (false) return #err(#notTheDelegator|' src/WfFold.mo
try wf-revoked-twice Workflow \
  sed -i 's|^    if (not stands(d, c\.day)) return #err(#delegationNotActive|    if (false) return #err(#delegationNotActive|' src/WfFold.mo
try wf-revoke-not-kept Workflow \
  sed -i 's|{ d with state = #revoked; lastBlock = c\.block });$|{ d with lastBlock = c.block });|' src/WfFold.mo

# EACH CHAINED KIND'S DECISION goes through the gate (src/State.mo), each reader its own pending state and requester
try wf-leave-unchained Workflow \
  sed -i 's|{ chained(#leave, companyId, requestId, approve, func() { hr(HrFold\.decideLeave(ctx, companyId, requestId, approve)) }) };|{ hr(HrFold.decideLeave(ctx, companyId, requestId, approve)) };|' src/State.mo
try wf-wfh-unchained Workflow \
  sed -i 's|{ chained(#wfh, companyId, wfhId, approve, func() { af(AttFold\.decideWorkFromHome(attCtx, companyId, wfhId, approve, note)) }) };|{ af(AttFold.decideWorkFromHome(attCtx, companyId, wfhId, approve, note)) };|' src/State.mo
try wf-payroll-run-unchained Payroll \
  sed -i 's|{ chained(#payrollRun, companyId, runId, true, func() { pay(PayFold\.approveRun(payCtx, companyId, runId)) }) };|{ pay(PayFold.approveRun(payCtx, companyId, runId)) };|' src/State.mo
try wf-expense-approval-unchained Refusals \
  sed -i 's|{ chained(#expense, companyId, claimId, true, func() { xf(ExpFold\.approveClaim(expCtx, companyId, claimId)) }) };|{ xf(ExpFold.approveClaim(expCtx, companyId, claimId)) };|' src/State.mo
try wf-expense-rejection-held Refusals \
  sed -i 's|chained(#expense, companyId, claimId, false, func() { xf(ExpFold\.rejectClaim|chained(#expense, companyId, claimId, true, func() { xf(ExpFold.rejectClaim|' src/State.mo
try wf-purchase-unchained Refusals \
  sed -i 's|if (isPurchase(orderId)) chained(#purchase, companyId, orderId, true, func() { ord(OrderFold\.confirmOrder(ordCtx, companyId, orderId)) })|if (false) chained(#purchase, companyId, orderId, true, func() { ord(OrderFold.confirmOrder(ordCtx, companyId, orderId)) })|' src/State.mo
try wf-sale-chained Refusals \
  sed -i 's|if (isPurchase(orderId)) chained(#purchase, companyId, orderId, true, func() { ord(OrderFold\.confirmOrder(ordCtx, companyId, orderId)) })|if (true) chained(#purchase, companyId, orderId, true, func() { ord(OrderFold.confirmOrder(ordCtx, companyId, orderId)) })|' src/State.mo
try wf-purchase-cancel-held Refusals \
  sed -i 's|chained(#purchase, companyId, orderId, false, func() { ord(OrderFold\.cancelOrder|chained(#purchase, companyId, orderId, true, func() { ord(OrderFold.cancelOrder|' src/State.mo
try wf-payment-unchained Compensation \
  sed -i 's|{ chained(#offCyclePay, companyId, paymentId, true, func() { cnb(CnbFold\.approvePayment(cnbCtx, companyId, paymentId)) }) };|{ cnb(CnbFold.approvePayment(cnbCtx, companyId, paymentId)) };|' src/State.mo
try wf-payment-rejection-held Compensation \
  sed -i 's|chained(#offCyclePay, companyId, paymentId, false, func() { cnb(CnbFold\.rejectPayment|chained(#offCyclePay, companyId, paymentId, true, func() { cnb(CnbFold.rejectPayment|' src/State.mo
try wf-loan-unchained Compensation \
  sed -i 's|{ chained(#loan, companyId, loanId, approve, func() { cnb(CnbFold\.decideLoan(cnbCtx, companyId, loanId, approve, approvedAmount, note)) }) };|{ cnb(CnbFold.decideLoan(cnbCtx, companyId, loanId, approve, approvedAmount, note)) };|' src/State.mo
try wf-overtime-unchained Attendance \
  sed -i 's|{ chained(#overtime, companyId, overtimeId, approve, func() { af(AttFold\.decideOvertime(attCtx, companyId, overtimeId, approve, note)) }) };|{ af(AttFold.decideOvertime(attCtx, companyId, overtimeId, approve, note)) };|' src/State.mo
try wf-offer-unchained Recruitment \
  sed -i 's|{ chained(#jobOffer, companyId, offerId, true, func() { rf(RecFold\.sendOffer(recCtx, companyId, offerId, subject)) }) };|{ rf(RecFold.sendOffer(recCtx, companyId, offerId, subject)) };|' src/State.mo
try wf-rescind-held Recruitment \
  sed -i 's|chained(#jobOffer, companyId, offerId, false, func() { rf(RecFold\.rescindOffer|chained(#jobOffer, companyId, offerId, true, func() { rf(RecFold.rescindOffer|' src/State.mo
try wf-leave-always-pending Workflow \
  sed -i 's|?{ requester = ?x\.subject; pending = x\.state == #Pending }|?{ requester = ?x.subject; pending = true }|' src/State.mo
try wf-leave-anyone-asks Workflow \
  sed -i 's|?{ requester = ?x\.subject; pending = x\.state == #Pending }|?{ requester = null; pending = x.state == #Pending }|' src/State.mo
try wf-wfh-always-pending Refusals \
  sed -i '/case (#wfh) { switch/,/case null null/ s|pending = x\.state == #pending }|pending = true }|' src/State.mo
try wf-expense-always-pending Refusals \
  sed -i 's|?{ requester = ?x\.claimant; pending = x\.state == #submitted }|?{ requester = ?x.claimant; pending = true }|' src/State.mo
try wf-expense-anyone-asks Refusals \
  sed -i 's|?{ requester = ?x\.claimant; pending = x\.state == #submitted }|?{ requester = null; pending = x.state == #submitted }|' src/State.mo
try wf-loan-always-pending Compensation \
  sed -i 's|pending = x\.state == #requested }|pending = true }|' src/State.mo
try wf-loan-anyone-asks Compensation \
  sed -i '/case (#loan) { switch/,/case null null/ s|?{ requester = ?x\.subject;|?{ requester = null;|' src/State.mo
try wf-payment-always-pending Compensation \
  sed -i '/case (#offCyclePay) { switch/,/case null null/ s|pending = x\.state == #pending }|pending = true }|' src/State.mo
try wf-payment-anyone-asks Compensation \
  sed -i '/case (#offCyclePay) { switch/,/case null null/ s|?{ requester = ?x\.createdBy;|?{ requester = null;|' src/State.mo
try wf-run-always-pending Payroll \
  sed -i 's|pending = x\.state == #Computed }|pending = true }|' src/State.mo
try wf-overtime-always-pending Attendance \
  sed -i '/case (#overtime) { switch/,/case null null/ s|pending = x\.state == #submitted }|pending = true }|' src/State.mo
try wf-overtime-anyone-asks Attendance \
  sed -i '/case (#overtime) { switch/,/case null null/ s|?{ requester = ?x\.subject;|?{ requester = null;|' src/State.mo
try wf-offer-always-pending Recruitment \
  sed -i '/case (#jobOffer) { switch/,/case null null/ s|pending = x\.state == #draft }|pending = true }|' src/State.mo
try wf-offer-anyone-asks Recruitment \
  sed -i '/case (#jobOffer) { switch/,/case null null/ s|?{ requester = ?x\.createdBy;|?{ requester = null;|' src/State.mo
try wf-purchase-always-pending Refusals \
  sed -i '/case (#purchase) { switch/,/case null null/ s|pending = x\.state == #draft }|pending = true }|' src/State.mo

# THE LEAVE REPORT (src/HrFold.mo): a page of one state, from the request after the cursor
try leave-report-other-states Workflow \
  sed -i 's|^    let (_, hi) = R\.leaveStateRange(companyId, s);$|    let (_, hi) = R.leaveStateRange(companyId, #Withdrawn);|' src/HrFold.mo
try leave-report-cursor-kept Workflow \
  sed -i 's|R\.leaveStateKey(companyId, s, afterId + 1), hi, limit)|R.leaveStateKey(companyId, s, afterId), hi, limit)|' src/HrFold.mo

# ── studio: custom fields on every record (src/StudioFold.mo, src/StudioRows.mo, src/State.mo; test/Studio.test.mo) ──
# Every rule the Studio battery states, removed one at a time. That every table is a record kind, held by its own
# store, is the record-kinds lint's to hold over the tree's own text (tools/studio_lint.py, its own control); the
# battery holds a value to an absent record of every one of the kinds. Not injected: the lookups of a field, its
# rule in force and a value that are not there, each a `let … else` with no row to go on with, so the fold has no
# path without it that compiles; and the company-and-code key a field's code is free on, which the code-taken
# injection reaches through the same lookup.
# A FIELD AND ITS RULE ARE AN ADMINISTRATOR'S, in standing; a value a writer's, whose role the rule in force names
try st-any-role-administers Studio \
  sed -i 's|^      case (#ok _) ?#notAnAdministrator { subject = c\.caller };$|      case (#ok _) null;|' src/StudioFold.mo
try st-suspended-acts Studio \
  sed -i 's|^          case (?(_, m)) { if (m\.status == #Suspended or m\.status == #Terminated) null else ?m\.companyRole };$|          case (?(_, m)) { if (m.status == #Terminated) null else ?m.companyRole };|' src/State.mo
try st-no-such-company Studio \
  sed -i 's|^    if (not c\.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });$|    if (false) return #err(#wrongCompany { expected = companyId; found = 0 });|' src/StudioFold.mo
try st-any-role-writes Studio \
  sed -i 's|^    if (not SDR\.writes(r\.writers, role)) return #err(#notAWriter { fieldId; subject = c\.caller });$|    if (false) return #err(#notAWriter { fieldId; subject = c.caller });|' src/StudioFold.mo
try st-writer-bits-shared Studio \
  sed -i 's|^    switch (r) { case (#CompanyAdmin) 1; case (#HR) 2; case (#Director) 4; case (#Manager) 8; case (#Employee) 16 }$|    switch (r) { case (#CompanyAdmin) 1; case (#HR) 2; case (#Director) 4; case (#Manager) 4; case (#Employee) 16 }|' src/StudioRows.mo
try st-rule-of-another-company Studio \
  sed -i 's|^    if (rule\.companyId != f\.companyId) return #err(#wrongCompany { expected = f\.companyId; found = rule\.companyId });$|    if (false) return #err(#wrongCompany { expected = f.companyId; found = rule.companyId });|' src/StudioFold.mo
try st-field-of-another-company Studio \
  sed -i 's|^    if (x\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x\.companyId });$|    if (false) return #err(#wrongCompany { expected = companyId; found = x.companyId });|' src/StudioFold.mo

# A FIELD: on a kind of record, its code free on that kind, its shape one its type takes
try st-unknown-kind Studio \
  sed -i 's|^    if (c\.recordOf(f\.record, 0) == #unknownKind) return #err(#unknownRecordKind { record = f\.record });$|    if (false) return #err(#unknownRecordKind { record = f.record });|' src/StudioFold.mo
try st-captionless-field Studio \
  sed -i '/public func defineStudioField/,/^  };$/ s|^    if (Text\.size(f\.caption) == 0) return #err(#nameRequired { what = "a field'\''s caption" });$|    if (false) return #err(#nameRequired { what = "a field'\''s caption" });|' src/StudioFold.mo
try st-code-taken-twice Studio \
  sed -i 's|^      case (?_) return #err(#codeTaken { record = f\.record; code = CR\.normalise(f\.code) });$|      case (?_) {};|' src/StudioFold.mo
try st-codeless Studio \
  sed -i 's|^    if (Text\.size(n) == 0) return #err(#nameRequired { what = "a field'\''s code" });$|    if (false) return #err(#nameRequired { what = "a field'\''s code" });|' src/StudioFold.mo
try st-code-not-normalised Studio \
  sed -i '/func codeField/,/^  };$/ s|^    let n = CR\.normalise(code);$|    let n = code;|' src/StudioFold.mo
try st-code-not-read-back Studio \
  sed -i 's|^    if (F\.textOfField(b) != ?n) return #err(#codeDoesNotFit { code = n; max = W\.CODE });$|    if (false) return #err(#codeDoesNotFit { code = n; max = W.CODE });|' src/StudioFold.mo
try st-choices-unbounded Studio \
  sed -i 's|^    if (choices\.size() > W\.STUDIO_CHOICES) return #err(#tooManyChoices { max = W\.STUDIO_CHOICES });$|    if (false) return #err(#tooManyChoices { max = W.STUDIO_CHOICES });|' src/StudioFold.mo
try st-choice-empty Studio \
  sed -i 's|^      if (Text\.size(n) == 0 or F\.textOfField(b) != ?n) return #err(#choiceDoesNotFit { choice = n; max = W\.CODE });$|      if (F.textOfField(b) != ?n) return #err(#choiceDoesNotFit { choice = n; max = W.CODE });|' src/StudioFold.mo
try st-choice-not-read-back Studio \
  sed -i 's|^      if (Text\.size(n) == 0 or F\.textOfField(b) != ?n) return #err(#choiceDoesNotFit { choice = n; max = W\.CODE });$|      if (Text.size(n) == 0) return #err(#choiceDoesNotFit { choice = n; max = W.CODE });|' src/StudioFold.mo
try st-choice-twice Studio \
  sed -i 's|^      for (seen in out\.vals()) { if (seen == b) return #err(#choiceTwice { choice = n }) };$|      for (seen in out.vals()) { if (false) return #err(#choiceTwice { choice = n }) };|' src/StudioFold.mo
try st-choice-not-normalised Studio \
  sed -i '/public func choiceFields/,/^  };$/ s|^      let n = CR\.normalise(t);$|      let n = t;|' src/StudioFold.mo
try st-width-any Studio \
  sed -i 's|^    if (width < lo or width > hi) return ?#widthOutOfRange { valueType = typeText(t); width; min = lo; max = hi };$|    if (false) return ?#widthOutOfRange { valueType = typeText(t); width; min = lo; max = hi };|' src/StudioFold.mo
try st-width-zero Studio \
  sed -i 's|^    if (width < lo or width > hi) return ?#widthOutOfRange { valueType = typeText(t); width; min = lo; max = hi };$|    if (width > hi) return ?#widthOutOfRange { valueType = typeText(t); width; min = lo; max = hi };|' src/StudioFold.mo
try st-scale-past-six Studio \
  sed -i 's|^      if (scale > W\.STUDIO_SCALE_MAX or scale > width) return ?#scaleOutOfRange { scale; max = Nat\.min(W\.STUDIO_SCALE_MAX, width) };$|      if (scale > width) return ?#scaleOutOfRange { scale; max = Nat.min(W.STUDIO_SCALE_MAX, width) };|' src/StudioFold.mo
try st-scale-past-digits Studio \
  sed -i 's|^      if (scale > W\.STUDIO_SCALE_MAX or scale > width) return ?#scaleOutOfRange { scale; max = Nat\.min(W\.STUDIO_SCALE_MAX, width) };$|      if (scale > W.STUDIO_SCALE_MAX) return ?#scaleOutOfRange { scale; max = Nat.min(W.STUDIO_SCALE_MAX, width) };|' src/StudioFold.mo
try st-scale-off-a-number Studio \
  sed -i 's|^    } else if (scale != 0) return ?#scaleOutOfRange { scale; max = 0 };$|    } else if (false) return ?#scaleOutOfRange { scale; max = 0 };|' src/StudioFold.mo
try st-unique-flag Studio \
  sed -i 's|^    if (unique and (t == #flag or t == #choice)) return ?#uniqueNotOffered { valueType = typeText(t) };$|    if (unique and (t == #choice)) return ?#uniqueNotOffered { valueType = typeText(t) };|' src/StudioFold.mo
try st-unique-choice Studio \
  sed -i 's|^    if (unique and (t == #flag or t == #choice)) return ?#uniqueNotOffered { valueType = typeText(t) };$|    if (unique and (t == #flag)) return ?#uniqueNotOffered { valueType = typeText(t) };|' src/StudioFold.mo
try st-choice-field-of-nothing Studio \
  sed -i 's|^      if (choices\.size() == 0) return ?#choicesRequired;$|      if (false) return ?#choicesRequired;|' src/StudioFold.mo
try st-choices-off-a-choice Studio \
  sed -i 's|^    } else if (choices\.size() != 0) return ?#choicesNotOffered { valueType = typeText(t) };$|    } else if (false) return ?#choicesNotOffered { valueType = typeText(t) };|' src/StudioFold.mo
try st-first-rule-unchecked Studio \
  sed -i '/public func defineStudioField/,/^  };$/ s|^    switch (checkRule({ valueType = f\.valueType; width = f\.width }, rule)) { case (?r) return #err(r); case null {} };$|    switch (checkRule({ valueType = f.valueType; width = f.width }, rule)) { case (?_) {}; case null {} };|' src/StudioFold.mo

# A RULE: its bounds within the range its type takes and in order, its writers named, each once
try st-text-bound-past-width Studio \
  sed -i 's|^      case (#text) ?(0, f\.width);$|      case (#text) ?(0, W.STUDIO_TEXT_MAX);|' src/StudioFold.mo
try st-number-bound-past-digits Studio \
  sed -i 's|^      case (#number) ?(-numberMax(f\.width), numberMax(f\.width));$|      case (#number) ?(-numberMax(W.STUDIO_DIGITS_MAX), numberMax(W.STUDIO_DIGITS_MAX));|' src/StudioFold.mo
try st-day-bound-zero Studio \
  sed -i 's|^      case (#day) ?(1, F\.pow256(W\.DAY) - 1);$|      case (#day) ?(0, F.pow256(W.DAY) - 1);|' src/StudioFold.mo
try st-bounds-on-a-flag Studio \
  sed -i 's|^        if (r\.minimum != null or r\.maximum != null) return ?#boundsNotOffered { valueType = typeText(f\.valueType) };$|        if (false) return ?#boundsNotOffered { valueType = typeText(f.valueType) };|' src/StudioFold.mo
try st-bound-below-range Studio \
  sed -i 's|^          switch (b) { case (?n) { if (n < lo or n > hi) return ?#boundOutOfRange { bound = n; min = lo; max = hi } }; case null {} };$|          switch (b) { case (?n) { if (n > hi) return ?#boundOutOfRange { bound = n; min = lo; max = hi } }; case null {} };|' src/StudioFold.mo
try st-bound-above-range Studio \
  sed -i 's|^          switch (b) { case (?n) { if (n < lo or n > hi) return ?#boundOutOfRange { bound = n; min = lo; max = hi } }; case null {} };$|          switch (b) { case (?n) { if (n < lo) return ?#boundOutOfRange { bound = n; min = lo; max = hi } }; case null {} };|' src/StudioFold.mo
try st-bounds-crossed Studio \
  sed -i 's|^          case (?mn, ?mx) { if (mn > mx) return ?#boundsCrossed { minimum = mn; maximum = mx } };$|          case (?mn, ?mx) { if (false) return ?#boundsCrossed { minimum = mn; maximum = mx } };|' src/StudioFold.mo
try st-no-writers Studio \
  sed -i 's|^    if (r\.writers\.size() == 0) return ?#writersRequired;$|    if (false) return ?#writersRequired;|' src/StudioFold.mo
try st-writer-twice Studio \
  sed -i 's|^        if (r\.writers\[i\] == r\.writers\[j\]) return ?#writerTwice { role = roleText(r\.writers\[i\]) };$|        if (false) return ?#writerTwice { role = roleText(r.writers[i]) };|' src/StudioFold.mo
try st-rule-unchecked Studio \
  sed -i '/public func setStudioRule/,/^  };$/ s|^    switch (checkRule({ valueType = x\.valueType; width = x\.width }, r)) { case (?e) return #err(e); case null {} };$|    switch (checkRule({ valueType = x.valueType; width = x.width }, r)) { case (?_) {}; case null {} };|' src/StudioFold.mo
try st-rule-on-retired Studio \
  sed -i '/public func setStudioRule/,/^  };$/ s|^    if (x\.state == #retired) return #err(#fieldRetired { fieldId });$|    if (false) return #err(#fieldRetired { fieldId });|' src/StudioFold.mo
try st-rule-unchanged Studio \
  sed -i 's|^        if (now\.required == r\.required and now\.minimum == r\.minimum and now\.maximum == r\.maximum and now\.writers == SDR\.writersMask(r\.writers))$|        if (false)|' src/StudioFold.mo
try st-rule-not-in-force Studio \
  sed -i 's|^    RowStore\.put<SDR\.Field>(c\.studio\.fields, SDR\.field, fieldId, { x with ruleVersion = version; lastBlock = c\.block });$|    RowStore.put<SDR.Field>(c.studio.fields, SDR.field, fieldId, { x with lastBlock = c.block });|' src/StudioFold.mo

# AN AMENDMENT: the caption, the width only wider, the choices only extended, and something changed; a field retired once
try st-amend-retired Studio \
  sed -i '/public func amendStudioField/,/^  };$/ s|^    if (x\.state == #retired) return #err(#fieldRetired { fieldId });$|    if (false) return #err(#fieldRetired { fieldId });|' src/StudioFold.mo
try st-amend-captionless Studio \
  sed -i '/public func amendStudioField/,/^  };$/ s|^    if (Text\.size(a\.caption) == 0) return #err(#nameRequired { what = "a field'\''s caption" });$|    if (false) return #err(#nameRequired { what = "a field'\''s caption" });|' src/StudioFold.mo
try st-width-narrowed Studio \
  sed -i 's|^    if (a\.width < x\.width) return #err(#widthNarrowed { fieldId; width = a\.width; was = x\.width });$|    if (false) return #err(#widthNarrowed { fieldId; width = a.width; was = x.width });|' src/StudioFold.mo
try st-choices-dropped Studio \
  sed -i 's|^    if (choices\.size() < x\.choices\.size()) return #err(#choicesRewritten { fieldId });$|    if (false) return #err(#choicesRewritten { fieldId });|' src/StudioFold.mo
try st-choices-reordered Studio \
  sed -i 's|^      if (choices\[i\] != x\.choices\[i\]) return #err(#choicesRewritten { fieldId });$|      if (false) return #err(#choicesRewritten { fieldId });|' src/StudioFold.mo
try st-amended-shape-unchecked Studio \
  sed -i 's|^    switch (checkShape(x\.valueType, a\.width, x\.scale, x\.unique, choices)) { case (?r) return #err(r); case null {} };$|    switch (checkShape(x.valueType, a.width, x.scale, x.unique, choices)) { case (?_) {}; case null {} };|' src/StudioFold.mo
try st-nothing-amended Studio \
  sed -i 's|^    if (sameCaption and a\.width == x\.width and choices\.size() == x\.choices\.size()) return #err(#nothingAmended { fieldId });$|    if (false) return #err(#nothingAmended { fieldId });|' src/StudioFold.mo
try st-retired-twice Studio \
  sed -i '/public func retireStudioField/,/^  };$/ s|^    if (x\.state == #retired) return #err(#fieldRetired { fieldId });$|    if (false) return #err(#fieldRetired { fieldId });|' src/StudioFold.mo
try st-retirement-not-kept Studio \
  sed -i 's|^    RowStore\.put<SDR\.Field>(c\.studio\.fields, SDR\.field, fieldId, { x with state = #retired; lastBlock = c\.block });$|    RowStore.put<SDR.Field>(c.studio.fields, SDR.field, fieldId, { x with lastBlock = c.block });|' src/StudioFold.mo

# A VALUE: on a record of the field's kind and company, of its type and width, within the rule in force, unique where the field is
try st-value-on-retired Studio \
  sed -i '/func writable/,/^  };$/ s|^    if (x\.state == #retired) return #err(#fieldRetired { fieldId });$|    if (false) return #err(#fieldRetired { fieldId });|' src/StudioFold.mo
try st-value-on-absent-record Studio \
  sed -i 's|^      case (#absent) ?#noSuchRecord { record; recordId };$|      case (#absent) null;|' src/StudioFold.mo
try st-value-on-another-companys-record Studio \
  sed -i 's|^      case (#company co) { if (co != x\.companyId) ?#recordOfAnotherCompany { record; recordId; companyId = co } else null };$|      case (#company co) { if (false) ?#recordOfAnotherCompany { record; recordId; companyId = co } else null };|' src/StudioFold.mo
try st-empty-text Studio \
  sed -i 's|^        if (bytes == 0) return #err(#valueRequired);$|        if (false) return #err(#valueRequired);|' src/StudioFold.mo
try st-text-past-width Studio \
  sed -i 's|^        if (bytes > x\.width) return #err(#valueTooWide { fieldId = v\.fieldId; width = x\.width });$|        if (false) return #err(#valueTooWide { fieldId = v.fieldId; width = x.width });|' src/StudioFold.mo
try st-text-measured-in-characters Studio \
  sed -i 's|^        let bytes = Text\.encodeUtf8(v\.text)\.size();$|        let bytes = Text.size(v.text);|' src/StudioFold.mo
try st-number-past-digits Studio \
  sed -i 's|^        if (Int\.abs(v\.number) > numberMax(x\.width)) return #err(#valueTooWide { fieldId = v\.fieldId; width = x\.width });$|        if (false) return #err(#valueTooWide { fieldId = v.fieldId; width = x.width });|' src/StudioFold.mo
try st-negative-past-digits Studio \
  sed -i 's|^        if (Int\.abs(v\.number) > numberMax(x\.width)) return #err(#valueTooWide { fieldId = v\.fieldId; width = x\.width });$|        if (v.number > numberMax(x.width)) return #err(#valueTooWide { fieldId = v.fieldId; width = x.width });|' src/StudioFold.mo
try st-day-out-of-range Studio \
  sed -i 's|^        if (not dayFits(v\.day)) return #err(#dayOutOfRange { day = v\.day });$|        if (false) return #err(#dayOutOfRange { day = v.day });|' src/StudioFold.mo
try st-not-a-choice Studio \
  sed -i 's|^        if (choice == 0) return #err(#notAChoice { fieldId = v\.fieldId; choice = n });$|        if (false) return #err(#notAChoice { fieldId = v.fieldId; choice = n });|' src/StudioFold.mo
try st-choice-value-not-normalised Studio \
  sed -i '/public func setStudioValue/,/^  };$/ s|^        let n = CR\.normalise(v\.choice);$|        let n = v.choice;|' src/StudioFold.mo
try st-below-minimum Studio \
  sed -i 's|^    switch (r\.minimum) { case (?mn) { if (measure < mn) return #err(#valueBelowMinimum { fieldId = v\.fieldId; minimum = mn }) }; case null {} };$|    switch (r.minimum) { case (?mn) { if (false) return #err(#valueBelowMinimum { fieldId = v.fieldId; minimum = mn }) }; case null {} };|' src/StudioFold.mo
try st-above-maximum Studio \
  sed -i 's|^    switch (r\.maximum) { case (?mx) { if (measure > mx) return #err(#valueAboveMaximum { fieldId = v\.fieldId; maximum = mx }) }; case null {} };$|    switch (r.maximum) { case (?mx) { if (false) return #err(#valueAboveMaximum { fieldId = v.fieldId; maximum = mx }) }; case null {} };|' src/StudioFold.mo
try st-value-unchanged-taken Studio \
  sed -i 's|^      case (?(_, h)) { if (h\.isSet and h\.hash == hash and h\.ruleVersion == x\.ruleVersion) return #err(#valueUnchanged { fieldId = v\.fieldId; recordId = v\.recordId }) };$|      case (?(_, h)) { if (false) return #err(#valueUnchanged { fieldId = v.fieldId; recordId = v.recordId }) };|' src/StudioFold.mo
try st-value-unchanged-across-rules Studio \
  sed -i 's|^      case (?(_, h)) { if (h\.isSet and h\.hash == hash and h\.ruleVersion == x\.ruleVersion) return #err(#valueUnchanged { fieldId = v\.fieldId; recordId = v\.recordId }) };$|      case (?(_, h)) { if (h.isSet and h.hash == hash) return #err(#valueUnchanged { fieldId = v.fieldId; recordId = v.recordId }) };|' src/StudioFold.mo
try st-cleared-value-unchanged Studio \
  sed -i 's|^      case (?(_, h)) { if (h\.isSet and h\.hash == hash and h\.ruleVersion == x\.ruleVersion) return #err(#valueUnchanged { fieldId = v\.fieldId; recordId = v\.recordId }) };$|      case (?(_, h)) { if (h.hash == hash and h.ruleVersion == x.ruleVersion) return #err(#valueUnchanged { fieldId = v.fieldId; recordId = v.recordId }) };|' src/StudioFold.mo
try st-unique-shared Studio \
  sed -i 's|^        case (?(_, other)) { if (other\.recordId != v\.recordId) return #err(#valueTaken { fieldId = v\.fieldId; recordId = other\.recordId }) };$|        case (?(_, other)) { if (false) return #err(#valueTaken { fieldId = v.fieldId; recordId = other.recordId }) };|' src/StudioFold.mo
try st-unique-held-when-cleared Studio \
  sed -i 's|^        keyOf = func(_id : Nat, x : Value) : ?Blob { if (x\.unique and x\.isSet) ?uniqueKey(x\.fieldId, x\.hash) else null } },$|        keyOf = func(_id : Nat, x : Value) : ?Blob { if (x.unique) ?uniqueKey(x.fieldId, x.hash) else null } },|' src/StudioRows.mo
try st-flag-fingerprint-blind Studio \
  sed -i 's|^      case (#flag) Blob\.fromArray(\[if (flag) 2 else 1\]);$|      case (#flag) Blob.fromArray([1]);|' src/StudioFold.mo
try st-number-fingerprint-unsigned Studio \
  sed -i 's|^      case (#number) { let w = SR\.buf(); SR\.putNat(w, F\.zig(number), W\.MONEY_SIGNED); SR\.done(w, W\.MONEY_SIGNED) };$|      case (#number) { let w = SR.buf(); SR.putNat(w, Int.abs(number), W.MONEY_SIGNED); SR.done(w, W.MONEY_SIGNED) };|' src/StudioFold.mo
try st-value-held-under-old-rule Studio \
  sed -i 's|^      ruleVersion = x\.ruleVersion; hash; setBy = c\.caller; setDay = c\.day; lastBlock = c\.block };$|      ruleVersion = 1; hash; setBy = c.caller; setDay = c.day; lastBlock = c.block };|' src/StudioFold.mo
try st-value-reset-not-counted Studio \
  sed -i 's|^        if (not h\.isSet) RowStore\.put<SDR\.Field>(c\.studio\.fields, SDR\.field, v\.fieldId, { x with values = x\.values + 1; lastBlock = c\.block });$|        if (false) RowStore.put<SDR.Field>(c.studio.fields, SDR.field, v.fieldId, { x with values = x.values + 1; lastBlock = c.block });|' src/StudioFold.mo

# A VALUE CLEARED: set, by a writer, and never one the rule in force requires; the row kept, not set
try st-clear-unset Studio \
  sed -i 's|^    if (not h\.isSet) return #err(#noValue { fieldId; recordId });$|    if (false) return #err(#noValue { fieldId; recordId });|' src/StudioFold.mo
try st-required-cleared Studio \
  sed -i 's|^    if (r\.required) return #err(#requiredByRule { fieldId; version = r\.version });$|    if (false) return #err(#requiredByRule { fieldId; version = r.version });|' src/StudioFold.mo
try st-cleared-still-set Studio \
  sed -i 's|^    RowStore\.put<SDR\.Value>(c\.studio\.values, SDR\.value, id, { h with isSet = false; setBy = c\.caller; setDay = c\.day; lastBlock = c\.block });$|    RowStore.put<SDR.Value>(c.studio.values, SDR.value, id, { h with setBy = c.caller; setDay = c.day; lastBlock = c.block });|' src/StudioFold.mo
try st-clear-not-counted Studio \
  sed -i 's|^    RowStore\.put<SDR\.Field>(c\.studio\.fields, SDR\.field, fieldId, { x with values = x\.values - 1; lastBlock = c\.block });$|    RowStore.put<SDR.Field>(c.studio.fields, SDR.field, fieldId, { x with lastBlock = c.block });|' src/StudioFold.mo

# THE READS: a record's fields with what is missing, and the values the rule in force would refuse
try st-missing-ignores-rule Studio \
  sed -i 's|^          { fieldId = id; field = f; value = v; missing = f\.state == #active and required and v == null }$|          { fieldId = id; field = f; value = v; missing = f.state == #active and v == null }|' src/StudioFold.mo
try st-missing-on-retired Studio \
  sed -i 's|^          { fieldId = id; field = f; value = v; missing = f\.state == #active and required and v == null }$|          { fieldId = id; field = f; value = v; missing = required and v == null }|' src/StudioFold.mo
try st-cleared-read-as-set Studio \
  sed -i 's|^          let v = switch (valueOf(st, id, recordId)) { case (?(_, x)) { if (x\.isSet) ?x else null }; case null null };$|          let v = switch (valueOf(st, id, recordId)) { case (?(_, x)) { ?x }; case null null };|' src/StudioFold.mo
try st-nonconforming-counts-cleared Studio \
  sed -i 's|^        let rows = Array\.filter<(Nat, SDR\.Value)>(pg\.rows, func((_, v)) { v\.isSet and not withinBounds(arena, f, r, v) });$|        let rows = Array.filter<(Nat, SDR.Value)>(pg.rows, func((_, v)) { not withinBounds(arena, f, r, v) });|' src/StudioFold.mo
try st-bounds-measured-in-characters Studio \
  sed -i 's|^      case (#text) { switch (TA\.get(arena, v\.text)) { case (?t) Text\.encodeUtf8(t)\.size(); case null 0 } };$|      case (#text) { switch (TA.get(arena, v.text)) { case (?t) Text.size(t); case null 0 } };|' src/StudioFold.mo
try st-nonconforming-pages-skip Studio \
  sed -i 's|^        for ((id, _) in pg\.rows\.vals()) last := id;$|        for ((id, _) in pg.rows.vals()) last := id + 1;|' src/StudioFold.mo

# ── controls: journal screening, duplicate bills and split orders, procedures under four eyes (src/CtlFold.mo, src/State.mo; test/Controls.test.mo) ──
# Every rule the Controls battery states, removed or moved one at a time: who records a profile, screens, concludes,
# prepares and reviews, each in standing; every parameter's bound and every list's length; each criterion at its
# edge; the population's bounds by block; the counts, the fingerprints and the digit test with its bands; the bills,
# the orders and the split windows; the seal and its chain. Not injected: the split rule's condition that a window
# hold two orders, which no window can fail alone - a window holds the order it ends at, which is below the
# threshold, so a sum at the threshold takes two - so removing it changes nothing a run can show.
try ctl-no-such-company Controls \
  sed -i 's|^    if (not c\.companyExists(companyId)) return #err(#wrongCompany { expected = companyId; found = 0 });$|    if (false) return #err(#wrongCompany { expected = companyId; found = 0 });|' src/CtlFold.mo
try ctl-suspended-in-standing Controls \
  sed -i '/^    let ctlCtx : CtlFold\.Ctx = {/,/^  };$/ s|^          case (?(_, m)) { if (m\.status == #Suspended or m\.status == #Terminated) null else ?m\.companyRole };$|          case (?(_, m)) { ?m.companyRole };|' src/State.mo
try ctl-any-role-an-officer Controls \
  sed -i 's|^      case (#ok _) ?#notAnOfficer { subject = c\.caller };$|      case (#ok _) null;|' src/CtlFold.mo
try ctl-any-role-screens Controls \
  sed -i '/^  func screener(c : Ctx/,/^  };$/ s|^    if (not CTR\.roleIn(prof\.screeners, role)) return #err(#notAScreener { subject = c\.caller });$|    if (false) return #err(#notAScreener { subject = c.caller });|' src/CtlFold.mo
try ctl-any-role-slices Controls \
  sed -i '/^  public func screenSlice(c : Ctx/,/^  };$/ s|^    if (not CTR\.roleIn(prof\.screeners, role)) return #err(#notAScreener { subject = c\.caller });$|    if (false) return #err(#notAScreener { subject = c.caller });|' src/CtlFold.mo
try ctl-slice-under-profile-in-force Controls \
  sed -i 's|^    let ?prof = RowStore\.get<CTR\.Profile>(c\.ctl\.profiles, CTR\.profile, run\.profileId) else return #err(#noProfile { companyId });$|    let ?(_, prof) = profileInForce(c.ctl, companyId) else return #err(#noProfile { companyId });|' src/CtlFold.mo
try ctl-no-criteria Controls \
  sed -i 's|^    if (f\.criteria\.size() == 0) return #err(#noCriteria);$|    if (false) return #err(#noCriteria);|' src/CtlFold.mo
try ctl-criterion-twice Controls \
  sed -i 's|^      if (CTR\.has(mask, k)) return #err(#criterionTwice { criterion = k });$|      if (false) return #err(#criterionTwice { criterion = k });|' src/CtlFold.mo
try ctl-criterion-not-offered-applied Controls \
  sed -i 's|^      switch (criterionOffered(k)) { case (?reason) return #err(#criterionNotOffered { criterion = k; reason }); case null {} };$|      switch (criterionOffered(k)) { case (?_) {}; case null {} };|' src/CtlFold.mo
try ctl-parameters-unbounded Controls \
  sed -i 's|^      if (CTR\.has(mask, k)) { switch (within(k, parameter, v, lo, hi)) { case (?r) return #err(r); case null {} } };$|      if (false) { switch (within(k, parameter, v, lo, hi)) { case (?r) return #err(r); case null {} } };|' src/CtlFold.mo
try ctl-parameter-bound-inclusive Controls \
  sed -i 's|^    if (v < lo or v > hi) ?#parameterOutOfRange { criterion; parameter; minimum = lo; maximum = hi } else null$|    if (v < lo or v >= hi) ?#parameterOutOfRange { criterion; parameter; minimum = lo; maximum = hi } else null|' src/CtlFold.mo
try ctl-digit-minimum-unbounded Controls \
  sed -i 's|^    if (f\.benfordMinimum < 1 or f\.benfordMinimum > moneyMax) return #err(#parameterOutOfRange { criterion = 0; parameter = "the digit test'\''s minimum"; minimum = 1; maximum = moneyMax });$|    if (false) return #err(#parameterOutOfRange { criterion = 0; parameter = "the digit test'\''s minimum"; minimum = 1; maximum = moneyMax });|' src/CtlFold.mo
try ctl-unapplied-parameter-recorded Controls \
  sed -i 's|^    func used(k : Nat, v : Nat) : Nat { if (CTR\.has(mask, k)) v else 0 };$|    func used(k : Nat, v : Nat) : Nat { v };|' src/CtlFold.mo
try ctl-unapplied-threshold-recorded Controls \
  sed -i 's|^    func usedEither(k1 : Nat, k2 : Nat, v : Nat) : Nat { if (CTR\.has(mask, k1) or CTR\.has(mask, k2)) v else 0 };$|    func usedEither(k1 : Nat, k2 : Nat, v : Nat) : Nat { v };|' src/CtlFold.mo
try ctl-list-unbounded Controls \
  sed -i 's|^      if (size > W\.CTL_LIST_MAX) return #err(#listTooLong { list = name; max = W\.CTL_LIST_MAX });$|      if (false) return #err(#listTooLong { list = name; max = W.CTL_LIST_MAX });|' src/CtlFold.mo
try ctl-list-bound-off-by-one Controls \
  sed -i 's|^      if (size > W\.CTL_LIST_MAX) return #err(#listTooLong { list = name; max = W\.CTL_LIST_MAX });$|      if (size >= W.CTL_LIST_MAX) return #err(#listTooLong { list = name; max = W.CTL_LIST_MAX });|' src/CtlFold.mo
try ctl-weekday-past-sunday Controls \
  sed -i 's|^      if (d > 6) return #err(#weekdayOutOfRange { weekday = d });$|      if (false) return #err(#weekdayOutOfRange { weekday = d });|' src/CtlFold.mo
try ctl-weekday-twice Controls \
  sed -i 's|^      if ((weekend \/ (2 \*\* d)) % 2 == 1) return #err(#itemTwice { list = "weekend"; item = "weekday " # n(d) });$|      if (false) return #err(#itemTwice { list = "weekend"; item = "weekday " # n(d) });|' src/CtlFold.mo
try ctl-holiday-not-a-day Controls \
  sed -i 's|^      if (not dayFits(d)) return #err(#dayOutOfRange { day = d });$|      if (false) return #err(#dayOutOfRange { day = d });|' src/CtlFold.mo
try ctl-holiday-twice Controls \
  sed -i 's|^      if (seen(#holiday, CTR\.natKey(d))) return #err(#itemTwice { list = "holiday"; item = "day " # n(d) });$|      if (false) return #err(#itemTwice { list = "holiday"; item = "day " # n(d) });|' src/CtlFold.mo
try ctl-keyword-case-kept Controls \
  sed -i 's|^      let low = asciiLower(stripped(kw));$|      let low = stripped(kw);|' src/CtlFold.mo
try ctl-keyword-spaces-kept Controls \
  sed -i 's|^      let low = asciiLower(stripped(kw));$|      let low = asciiLower(kw);|' src/CtlFold.mo
try ctl-keyword-not-a-word Controls \
  sed -i 's|^      if (not asciiWord(low)) return #err(#notAWord { what = "keyword"; word = kw });$|      if (false) return #err(#notAWord { what = "keyword"; word = kw });|' src/CtlFold.mo
try ctl-keyword-twice Controls \
  sed -i 's|^      if (seen(#keyword, key)) return #err(#itemTwice { list = "keyword"; item = low });$|      if (false) return #err(#itemTwice { list = "keyword"; item = low });|' src/CtlFold.mo
try ctl-account-of-another-company Controls \
  sed -i 's|^      if (acc\.companyId != f\.companyId) return #err(#accountOfAnotherCompany { accountId = a; companyId = acc\.companyId });$|      if (false) return #err(#accountOfAnotherCompany { accountId = a; companyId = acc.companyId });|' src/CtlFold.mo
try ctl-account-twice Controls \
  sed -i 's|^      if (seen(#account, CTR\.natKey(a))) return #err(#itemTwice { list = "account"; item = "account " # n(a) });$|      if (false) return #err(#itemTwice { list = "account"; item = "account " # n(a) });|' src/CtlFold.mo
try ctl-member-twice Controls \
  sed -i 's|^        if (seen(list, CTR\.principalKey(x))) return #err(#itemTwice { list = name; item = p(x) });$|        if (false) return #err(#itemTwice { list = name; item = p(x) });|' src/CtlFold.mo
try ctl-leaver-not-a-day Controls \
  sed -i 's|^      if (not dayFits(left)) return #err(#dayOutOfRange { day = left });$|      if (false) return #err(#dayOutOfRange { day = left });|' src/CtlFold.mo
try ctl-leaver-twice Controls \
  sed -i 's|^      if (seen(#leaver, CTR\.principalKey(x))) return #err(#itemTwice { list = "leaver"; item = p(x) });$|      if (false) return #err(#itemTwice { list = "leaver"; item = p(x) });|' src/CtlFold.mo
try ctl-debited-prefix-not-a-word Controls \
  sed -i 's|^      if (not asciiWord(dp)) return #err(#notAWord { what = "debited prefix"; word = dp });$|      if (false) return #err(#notAWord { what = "debited prefix"; word = dp });|' src/CtlFold.mo
try ctl-credited-prefix-not-a-word Controls \
  sed -i 's|^      if (not asciiWord(cp)) return #err(#notAWord { what = "credited prefix"; word = cp });$|      if (false) return #err(#notAWord { what = "credited prefix"; word = cp });|' src/CtlFold.mo
try ctl-pair-twice Controls \
  sed -i 's|^      if (seen(#pair, key)) return #err(#itemTwice { list = "pair"; item = dp # " to " # cp });$|      if (false) return #err(#itemTwice { list = "pair"; item = dp # " to " # cp });|' src/CtlFold.mo
try ctl-word-any-byte Controls \
  sed -i 's|^    for (x in b\.vals()) { if (x < 0x21 or x > 0x7E) return false };$|    for (x in b.vals()) { if (x > 0x7E) return false };|' src/CtlFold.mo
try ctl-no-screener Controls \
  sed -i 's|^    if (f\.screeners\.size() == 0) return #err(#screenerRequired);$|    if (false) return #err(#screenerRequired);|' src/CtlFold.mo
try ctl-screener-twice Controls \
  sed -i 's|^      if (CTR\.roleIn(screeners, r)) return #err(#screenerRequired);$|      if (false) return #err(#screenerRequired);|' src/CtlFold.mo
try ctl-currency-spaces-kept Controls \
  sed -i 's|^    let currencyText = Text\.trim(f\.currency, #char '\'' '\'');$|    let currencyText = f.currency;|' src/CtlFold.mo
try ctl-currency-empty Controls \
  sed -i 's|^    if (Text\.size(currencyText) == 0) return #err(#currencyNotACode { currency = f\.currency });$|    if (false) return #err(#currencyNotACode { currency = f.currency });|' src/CtlFold.mo
try ctl-version-not-advanced Controls \
  sed -i 's|^    let version = switch (standingOfCompany(c\.ctl, f\.companyId)) { case (?s) s\.version + 1; case null 1 };$|    let version = switch (standingOfCompany(c.ctl, f.companyId)) { case (?s) s.version + 2; case null 1 };|' src/CtlFold.mo
try ctl-new-version-forgets-open-run Controls \
  sed -i 's|^    let openRunId = switch (standingOfCompany(c\.ctl, f\.companyId)) { case (?s) s\.openRunId; case null 0 };$|    let openRunId = 0;|' src/CtlFold.mo
try ctl-slice-unbounded Controls \
  sed -i 's|^    if (limit == 0 or limit > Page\.MAX_LIMIT) ?#sliceBound { limit; max = Page\.MAX_LIMIT } else null$|    if (limit == 0) ?#sliceBound { limit; max = Page.MAX_LIMIT } else null|' src/CtlFold.mo
try ctl-run-day-not-a-day Controls \
  sed -i '/^  public func openScreening(c : Ctx/,/^  };$/ s|^    if (not dayFits(f\.fromDay)) return #err(#dayOutOfRange { day = f\.fromDay });$|    if (false) return #err(#dayOutOfRange { day = f.fromDay });|' src/CtlFold.mo
try ctl-run-period-reversed Controls \
  sed -i '/^  public func openScreening(c : Ctx/,/^  };$/ s|^    if (f\.fromDay > f\.throughDay) return #err(#periodReversed { fromDay = f\.fromDay; throughDay = f\.throughDay });$|    if (false) return #err(#periodReversed { fromDay = f.fromDay; throughDay = f.throughDay });|' src/CtlFold.mo
try ctl-two-runs-open Controls \
  sed -i 's|^    if (s\.openRunId != 0) return #err(#runOpen { companyId = f\.companyId; runId = s\.openRunId });$|    if (false) return #err(#runOpen { companyId = f.companyId; runId = s.openRunId });|' src/CtlFold.mo
try ctl-population-not-posted Controls \
  sed -i 's|^    if (m\.state != #posted) return false;$|    if (false) return false;|' src/CtlFold.mo
try ctl-population-posted-later Controls \
  sed -i 's|^    switch (postingOf(c\.ctl, moveId)) { case (?x) x\.lastBlock < run\.openedBlock; case null true }$|    switch (postingOf(c.ctl, moveId)) { case (?x) true; case null true }|' src/CtlFold.mo
try ctl-population-unrecorded-dropped Controls \
  sed -i 's|^    switch (postingOf(c\.ctl, moveId)) { case (?x) x\.lastBlock < run\.openedBlock; case null true }$|    switch (postingOf(c.ctl, moveId)) { case (?x) x.lastBlock < run.openedBlock; case null false }|' src/CtlFold.mo
try ctl-unrecorded-not-counted Controls \
  sed -i 's|^              if (posting == null) w\.unrecorded += 1;$|              if (false) w.unrecorded += 1;|' src/CtlFold.mo
try ctl-run-day-cursor-kept Controls \
  sed -i 's|^          w\.cursorDay := if (w\.phase == #screen) run\.fromDay else 0;$|          w.cursorDay := if (w.phase == #screen) w.cursorDay else 0;|' src/CtlFold.mo
try ctl-bills-past-bound Controls \
  sed -i 's|^        let pg = RowStore\.pageById<OR\.SupplierBill>(c\.ord\.supplierBills, OR\.supplierBill, Nat\.max(w\.cursorId, 1), run\.billBound - 1, null, limit);$|        let pg = RowStore.pageById<OR.SupplierBill>(c.ord.supplierBills, OR.supplierBill, Nat.max(w.cursorId, 1), c.ord.nextBillId - 1, null, limit);|' src/CtlFold.mo
try ctl-bills-any-company Controls \
  sed -i 's|^          if (b\.companyId == companyId and b\.billDay >= run\.fromDay and b\.billDay <= run\.throughDay) markBill(c, w, run, runId, prof, billId, b);$|          if (b.billDay >= run.fromDay and b.billDay <= run.throughDay) markBill(c, w, run, runId, prof, billId, b);|' src/CtlFold.mo
try ctl-bills-any-day Controls \
  sed -i 's|^          if (b\.companyId == companyId and b\.billDay >= run\.fromDay and b\.billDay <= run\.throughDay) markBill(c, w, run, runId, prof, billId, b);$|          if (b.companyId == companyId) markBill(c, w, run, runId, prof, billId, b);|' src/CtlFold.mo
try ctl-orders-confirmed-later Controls \
  sed -i 's|^          if (x\.companyId == companyId and x\.lastBlock < run\.openedBlock) {$|          if (x.companyId == companyId) {|' src/CtlFold.mo
try ctl-orders-any-company Controls \
  sed -i 's|^          if (x\.companyId == companyId and x\.lastBlock < run\.openedBlock) {$|          if (x.lastBlock < run.openedBlock) {|' src/CtlFold.mo
try ctl-orders-sales-too Controls \
  sed -i 's|^                if (o\.direction == #purchase and o\.orderDay >= run\.fromDay and o\.orderDay <= run\.throughDay) markOrder(c, w, runId, prof, orderId, o);$|                if (o.orderDay >= run.fromDay and o.orderDay <= run.throughDay) markOrder(c, w, runId, prof, orderId, o);|' src/CtlFold.mo
try ctl-orders-any-day Controls \
  sed -i 's|^                if (o\.direction == #purchase and o\.orderDay >= run\.fromDay and o\.orderDay <= run\.throughDay) markOrder(c, w, runId, prof, orderId, o);$|                if (o.direction == #purchase) markOrder(c, w, runId, prof, orderId, o);|' src/CtlFold.mo
try ctl-confirmation-not-recorded Controls \
  sed -i 's|^    c\.confirmed(companyId, orderId);$|    ignore companyId;|' src/OrderFold.mo
try ctl-posting-day-of-the-move Controls \
  sed -i 's|^    RowStore\.put<CTR\.Posting>(c\.ctl\.postings, CTR\.posting, moveId, { companyId; postedDay = c\.day; manual; reverses; lastBlock = c\.block });$|    RowStore.put<CTR.Posting>(c.ctl.postings, CTR.posting, moveId, { companyId; postedDay = m.businessDay; manual; reverses; lastBlock = c.block });|' src/AcctFold.mo
try ctl-posting-all-manual Controls \
  sed -i 's|^    RowStore\.put<CTR\.Posting>(c\.ctl\.postings, CTR\.posting, moveId, { companyId; postedDay = c\.day; manual; reverses; lastBlock = c\.block });$|    RowStore.put<CTR.Posting>(c.ctl.postings, CTR.posting, moveId, { companyId; postedDay = c.day; manual = true; reverses; lastBlock = c.block });|' src/AcctFold.mo
try ctl-posting-reverses-nothing Controls \
  sed -i 's|^    RowStore\.put<CTR\.Posting>(c\.ctl\.postings, CTR\.posting, moveId, { companyId; postedDay = c\.day; manual; reverses; lastBlock = c\.block });$|    RowStore.put<CTR.Posting>(c.ctl.postings, CTR.posting, moveId, { companyId; postedDay = c.day; manual; reverses = 0; lastBlock = c.block });|' src/AcctFold.mo
try ctl-manual-posting-generated Controls \
  sed -i 's|^  public func postManual(c : Ctx, companyId : Nat, moveId : Nat) : Outcome { postMoveInner(c, companyId, moveId, false, true, 0) };$|  public func postManual(c : Ctx, companyId : Nat, moveId : Nat) : Outcome { postMoveInner(c, companyId, moveId, false, false, 0) };|' src/AcctFold.mo
try ctl-account-counted-per-line Controls \
  sed -i 's|^      if (Array\.find<Nat>(accounts, func(a) { a == l\.accountId }) == null) accounts := Array\.concat(accounts, \[l\.accountId\]);$|      accounts := Array.concat(accounts, [l.accountId]);|' src/CtlFold.mo
try ctl-digits-below-minimum Controls \
  sed -i 's|^        if (v > 0 and v >= prof\.benfordMinimum) { bump(c, runId, #digits, CTR\.natKey(leadingTwo(v))); w\.benfordCount += 1 };$|        if (v > 0) { bump(c, runId, #digits, CTR.natKey(leadingTwo(v))); w.benfordCount += 1 };|' src/CtlFold.mo
try ctl-single-digit-unpadded Controls \
  sed -i 's|^    if (x < 10) x \* 10 else x$|    x|' src/CtlFold.mo
try ctl-fingerprint-ignores-amounts Controls \
  sed -i 's|^    for ((accountId, debit, credit) in rows\.vals()) { SR\.putNat(w, accountId, W\.ID); SR\.putNat(w, debit, W\.MONEY); SR\.putNat(w, credit, W\.MONEY) };$|    for ((accountId, debit, credit) in rows.vals()) { SR.putNat(w, accountId, W.ID); SR.putNat(w, 0, W.MONEY); SR.putNat(w, credit, W.MONEY) };|' src/CtlFold.mo
try ctl-fingerprint-in-line-order Controls \
  sed -i 's|^      func(x, y) { if (x\.0 != y\.0) Nat\.compare(x\.0, y\.0) else if (x\.1 != y\.1) Nat\.compare(x\.1, y\.1) else Nat\.compare(x\.2, y\.2) });$|      func(x, y) { #equal });|' src/CtlFold.mo
try ctl-flow-sideless Controls \
  sed -i 's|^  func sideOf(debit : Nat, credit : Nat) : Nat { if (debit > 0) 0x44 else if (credit > 0) 0x43 else 0x5A };$|  func sideOf(debit : Nat, credit : Nat) : Nat { 0x5A };|' src/CtlFold.mo
try ctl-preparer-is-poster Controls \
  sed -i 's|^    bump(c, runId, #preparer, CTR\.principalKey(m\.proposedBy));$|    bump(c, runId, #preparer, CTR.principalKey(m.postedBy));|' src/CtlFold.mo
try ctl-period-end-exclusive Controls \
  sed -i 's|^        met(CTR\.PERIOD_END, Int\.abs(posted - through) <= prof\.periodEndDays);$|        met(CTR.PERIOD_END, Int.abs(posted - through) < prof.periodEndDays);|' src/CtlFold.mo
try ctl-period-end-one-sided Controls \
  sed -i 's|^        met(CTR\.PERIOD_END, Int\.abs(posted - through) <= prof\.periodEndDays);$|        met(CTR.PERIOD_END, through - posted <= prof.periodEndDays);|' src/CtlFold.mo
try ctl-post-close-on-the-day Controls \
  sed -i 's|^        met(CTR\.POST_CLOSE, posted > through);$|        met(CTR.POST_CLOSE, posted >= through);|' src/CtlFold.mo
try ctl-self-approved-generated-too Controls \
  sed -i 's|^        met(CTR\.SELF_APPROVED, x\.manual and m\.postedBy == m\.proposedBy);$|        met(CTR.SELF_APPROVED, m.postedBy == m.proposedBy);|' src/CtlFold.mo
try ctl-self-approved-never Controls \
  sed -i 's|^        met(CTR\.SELF_APPROVED, x\.manual and m\.postedBy == m\.proposedBy);$|        met(CTR.SELF_APPROVED, false);|' src/CtlFold.mo
try ctl-weekday-from-sunday Controls \
  sed -i 's|^        let weekday = (x\.postedDay + 3) % 7;$|        let weekday = (x.postedDay + 4) % 7;|' src/CtlFold.mo
try ctl-holidays-ignored Controls \
  sed -i 's|^        met(CTR\.WEEKEND_HOLIDAY, (prof\.weekend \/ (2 \*\* weekday)) % 2 == 1 or listed(#holiday, CTR\.natKey(x\.postedDay)));$|        met(CTR.WEEKEND_HOLIDAY, (prof.weekend / (2 ** weekday)) % 2 == 1);|' src/CtlFold.mo
try ctl-holiday-of-the-move Controls \
  sed -i 's|^        met(CTR\.WEEKEND_HOLIDAY, (prof\.weekend \/ (2 \*\* weekday)) % 2 == 1 or listed(#holiday, CTR\.natKey(x\.postedDay)));$|        met(CTR.WEEKEND_HOLIDAY, (prof.weekend / (2 ** weekday)) % 2 == 1 or listed(#holiday, CTR.natKey(m.businessDay)));|' src/CtlFold.mo
try ctl-manual-never Controls \
  sed -i 's|^        met(CTR\.MANUAL, x\.manual);$|        met(CTR.MANUAL, false);|' src/CtlFold.mo
try ctl-reversal-any-day Controls \
  sed -i 's|^        met(CTR\.REVERSAL_AFTER_PERIOD, x\.reverses != 0 and posted > through);$|        met(CTR.REVERSAL_AFTER_PERIOD, x.reverses != 0);|' src/CtlFold.mo
try ctl-leaver-on-the-day Controls \
  sed -i 's|^          switch (itemOf(st, profileId, #leaver, CTR\.principalKey(who))) { case (?(_, it)) x\.postedDay > it\.nat; case null false }$|          switch (itemOf(st, profileId, #leaver, CTR.principalKey(who))) { case (?(_, it)) x.postedDay >= it.nat; case null false }|' src/CtlFold.mo
try ctl-leaver-preparer-only Controls \
  sed -i 's|^        met(CTR\.LEAVER, on(CTR\.LEAVER) and (leftBefore(m\.proposedBy) or leftBefore(m\.postedBy)));$|        met(CTR.LEAVER, on(CTR.LEAVER) and leftBefore(m.proposedBy));|' src/CtlFold.mo
try ctl-backdated-inclusive Controls \
  sed -i 's|^        met(CTR\.BACKDATED, posted - (m\.businessDay : Int) > prof\.backdatedDays);$|        met(CTR.BACKDATED, posted - (m.businessDay : Int) >= prof.backdatedDays);|' src/CtlFold.mo
try ctl-round-below-minimum Controls \
  sed -i 's|^    met(CTR\.ROUND_AMOUNT, on(CTR\.ROUND_AMOUNT) and anyAmount(func(v) { v > 0 and v >= prof\.roundMinimum and v % prof\.roundBase == 0 }));$|    met(CTR.ROUND_AMOUNT, on(CTR.ROUND_AMOUNT) and anyAmount(func(v) { v > 0 and v % prof.roundBase == 0 }));|' src/CtlFold.mo
try ctl-large-exclusive Controls \
  sed -i 's|^    met(CTR\.LARGE_AMOUNT, on(CTR\.LARGE_AMOUNT) and anyAmount(func(v) { v >= prof\.largeThreshold }));$|    met(CTR.LARGE_AMOUNT, on(CTR.LARGE_AMOUNT) and anyAmount(func(v) { v > prof.largeThreshold }));|' src/CtlFold.mo
try ctl-unusual-account-never Controls \
  sed -i 's|^    met(CTR\.UNUSUAL_ACCOUNT, on(CTR\.UNUSUAL_ACCOUNT) and anyLine(func((l, _)) { listed(#account, CTR\.natKey(l\.accountId)) }));$|    met(CTR.UNUSUAL_ACCOUNT, false);|' src/CtlFold.mo
try ctl-unusual-user-is-poster Controls \
  sed -i 's|^    met(CTR\.UNUSUAL_USER, on(CTR\.UNUSUAL_USER) and listed(#user, CTR\.principalKey(m\.proposedBy)));$|    met(CTR.UNUSUAL_USER, on(CTR.UNUSUAL_USER) and listed(#user, CTR.principalKey(m.postedBy)));|' src/CtlFold.mo
try ctl-description-unstripped Controls \
  sed -i 's|^    met(CTR\.NO_DESCRIPTION, on(CTR\.NO_DESCRIPTION) and anyLine(func((l, _)) { Text\.size(stripped(lineName(l))) < prof\.minDescription }));$|    met(CTR.NO_DESCRIPTION, on(CTR.NO_DESCRIPTION) and anyLine(func((l, _)) { Text.size(lineName(l)) < prof.minDescription }));|' src/CtlFold.mo
try ctl-description-inclusive Controls \
  sed -i 's|^    met(CTR\.NO_DESCRIPTION, on(CTR\.NO_DESCRIPTION) and anyLine(func((l, _)) { Text\.size(stripped(lineName(l))) < prof\.minDescription }));$|    met(CTR.NO_DESCRIPTION, on(CTR.NO_DESCRIPTION) and anyLine(func((l, _)) { Text.size(stripped(lineName(l))) <= prof.minDescription }));|' src/CtlFold.mo
try ctl-keyword-description-case-kept Controls \
  sed -i 's|^      let d = asciiLower(lineName(l));$|      let d = lineName(l);|' src/CtlFold.mo
try ctl-seldom-exclusive Controls \
  sed -i 's|^    met(CTR\.SELDOM_USED_ACCOUNT, on(CTR\.SELDOM_USED_ACCOUNT) and anyLine(func((l, _)) { countValue(c, runId, #account, CTR\.natKey(l\.accountId)) <= prof\.seldomMax }));$|    met(CTR.SELDOM_USED_ACCOUNT, on(CTR.SELDOM_USED_ACCOUNT) and anyLine(func((l, _)) { countValue(c, runId, #account, CTR.natKey(l.accountId)) < prof.seldomMax }));|' src/CtlFold.mo
try ctl-duplicate-of-itself Controls \
  sed -i 's|^    met(CTR\.DUPLICATE, on(CTR\.DUPLICATE) and countValue(c, runId, #fingerprint, fingerprintOf(ls)) >= 2);$|    met(CTR.DUPLICATE, on(CTR.DUPLICATE) and countValue(c, runId, #fingerprint, fingerprintOf(ls)) >= 1);|' src/CtlFold.mo
try ctl-flow-exclusive Controls \
  sed -i 's|^    met(CTR\.UNUSUAL_FLOW, on(CTR\.UNUSUAL_FLOW) and countValue(c, runId, #flow, flowOf(ls)) <= prof\.flowMax);$|    met(CTR.UNUSUAL_FLOW, on(CTR.UNUSUAL_FLOW) and countValue(c, runId, #flow, flowOf(ls)) < prof.flowMax);|' src/CtlFold.mo
try ctl-below-threshold-at-it Controls \
  sed -i 's|^      v > 0 and v < prof\.approvalThreshold and v \* 100 >= prof\.approvalThreshold \* (100 - prof\.bandPercent) }));$|      v > 0 and v <= prof.approvalThreshold and v * 100 >= prof.approvalThreshold * (100 - prof.bandPercent) }));|' src/CtlFold.mo
try ctl-below-threshold-bandless Controls \
  sed -i 's|^      v > 0 and v < prof\.approvalThreshold and v \* 100 >= prof\.approvalThreshold \* (100 - prof\.bandPercent) }));$|      v > 0 and v < prof.approvalThreshold }));|' src/CtlFold.mo
try ctl-approver-is-preparer Controls \
  sed -i 's|^    met(CTR\.UNAUTHORISED_APPROVER, on(CTR\.UNAUTHORISED_APPROVER) and not listed(#approver, CTR\.principalKey(m\.postedBy)));$|    met(CTR.UNAUTHORISED_APPROVER, on(CTR.UNAUTHORISED_APPROVER) and not listed(#approver, CTR.principalKey(m.proposedBy)));|' src/CtlFold.mo
try ctl-pair-either-side Controls \
  sed -i 's|^            and anyLine(func((l, code)) { l\.credit > 0 and Text\.startsWith(code, #text cp) })) hit := true;$|            and anyLine(func((l, code)) { Text.startsWith(code, #text cp) })) hit := true;|' src/CtlFold.mo
try ctl-pair-debit-side-unread Controls \
  sed -i 's|^        if (anyLine(func((l, code)) { l\.debit > 0 and Text\.startsWith(code, #text dp) })$|        if (anyLine(func((l, code)) { Text.startsWith(code, #text dp) })|' src/CtlFold.mo
try ctl-gap-never Controls \
  sed -i 's|^      met(CTR\.SEQUENCE_GAP, Lookup\.firstOf<AR\.Move>(c\.acct\.moves, AR\.move, "by_series", k, k) == null);$|      met(CTR.SEQUENCE_GAP, false);|' src/CtlFold.mo
try ctl-high-volume-inclusive Controls \
  sed -i 's|^    met(CTR\.HIGH_VOLUME_USER, on(CTR\.HIGH_VOLUME_USER) and countValue(c, runId, #preparer, CTR\.principalKey(m\.proposedBy)) > prof\.highVolumeMax);$|    met(CTR.HIGH_VOLUME_USER, on(CTR.HIGH_VOLUME_USER) and countValue(c, runId, #preparer, CTR.principalKey(m.proposedBy)) >= prof.highVolumeMax);|' src/CtlFold.mo
try ctl-many-lines-inclusive Controls \
  sed -i 's|^    met(CTR\.MANY_LINES, ls\.size() > prof\.manyLinesMax);$|    met(CTR.MANY_LINES, ls.size() >= prof.manyLinesMax);|' src/CtlFold.mo
try ctl-reference-unstripped Controls \
  sed -i 's|^    met(CTR\.NO_REFERENCE, Text\.size(stripped(textOf(c\.arena, m\.ref))) == 0);$|    met(CTR.NO_REFERENCE, Text.size(textOf(c.arena, m.ref)) == 0);|' src/CtlFold.mo
try ctl-criterion-not-applied-met Controls \
  sed -i 's|^    func met(k : Nat, b : Bool) { if (on(k) and b) mask += CTR\.bit(k) };$|    func met(k : Nat, b : Bool) { if (b) mask += CTR.bit(k) };|' src/CtlFold.mo
try ctl-finding-poster-unchained Controls \
  sed -i 's|^    F\.putPrincipal(d, poster);$|    F.putPrincipal(d, preparer);|' src/CtlFold.mo
try ctl-finding-uncounted-by-criterion Controls \
  sed -i 's|^    while (k <= W\.CTL_CRITERIA) { if (CTR\.has(criteria, k)) w\.byCriterion\[k - 1\] += 1; k += 1 };$|    while (k < W.CTL_CRITERIA) { if (CTR.has(criteria, k)) w.byCriterion[k - 1] += 1; k += 1 };|' src/CtlFold.mo
try ctl-flagged-uncounted Controls \
  sed -i 's|^                w\.flagged += 1;$|                w.flagged += 0;|' src/CtlFold.mo
try ctl-bill-reference-unnormalised Controls \
  sed -i 's|^      if (ch >= '\''a'\'' and ch <= '\''z'\'') out #= Char\.toText(Char\.fromNat32(Char\.toNat32(ch) - 32))$|      if (ch >= '\''a'\'' and ch <= '\''z'\'') out #= Char.toText(ch)|' src/CtlFold.mo
try ctl-bill-reference-punctuation-kept Controls \
  sed -i 's|^      else if ((ch >= '\''A'\'' and ch <= '\''Z'\'') or (ch >= '\''0'\'' and ch <= '\''9'\'')) out #= Char\.toText(ch);$|      else out #= Char.toText(ch);|' src/CtlFold.mo
try ctl-bill-reference-unread Controls \
  sed -i 's|^    if (Text\.size(reference) > 0) {$|    if (false) {|' src/CtlFold.mo
try ctl-bill-window-one-sided Controls \
  sed -i 's|^    let lo = if (b\.billDay > prof\.duplicateWindowDays) b\.billDay - prof\.duplicateWindowDays else 0;$|    let lo = b.billDay;|' src/CtlFold.mo
try ctl-bill-matches-itself Controls \
  sed -i 's|^    func hit(id : Nat) { if (id != billId and List\.find<Nat>(hits, func(x) { x == id }) == null) List\.add(hits, id) };$|    func hit(id : Nat) { if (List.find<Nat>(hits, func(x) { x == id }) == null) List.add(hits, id) };|' src/CtlFold.mo
try ctl-bill-matcher-concludes Controls \
  sed -i 's|^        case (?b) { if (b\.state == #matched and c\.caller == b\.matchedBy) return #err(#concluderPosted { subject = c\.caller }) };$|        case (?b) { if (false) return #err(#concluderPosted { subject = c.caller }) };|' src/CtlFold.mo
try ctl-foreign-uncounted Controls \
  sed -i 's|^    if (o\.currency != prof\.currency) w\.foreign += 1;$|    if (false) w.foreign += 1;|' src/CtlFold.mo
try ctl-split-foreign-currency Controls \
  sed -i 's|^    x\.kind == #orderSupplier and x\.amount > 0 and x\.amount < prof\.approvalThreshold and keyCurrency(x\.key) == prof\.currency$|    x.kind == #orderSupplier and x.amount > 0 and x.amount < prof.approvalThreshold|' src/CtlFold.mo
try ctl-split-at-threshold Controls \
  sed -i 's|^    x\.kind == #orderSupplier and x\.amount > 0 and x\.amount < prof\.approvalThreshold and keyCurrency(x\.key) == prof\.currency$|    x.kind == #orderSupplier and x.amount > 0 and x.amount <= prof.approvalThreshold and keyCurrency(x.key) == prof.currency|' src/CtlFold.mo
try ctl-split-window-wider Controls \
  sed -i 's|^    let lo = if (x\.day + 1 > prof\.splitWindowDays) x\.day + 1 - prof\.splitWindowDays else 0;$|    let lo = if (x.day > prof.splitWindowDays) x.day - prof.splitWindowDays else 0;|' src/CtlFold.mo
try ctl-split-below-threshold Controls \
  sed -i 's|^    if (window\.size() < 2 or sum < prof\.approvalThreshold) return;$|    if (window.size() < 2) return;|' src/CtlFold.mo
try ctl-band-bounds-moved Controls \
  sed -i 's|^    let band = if (s <= 12 \* bound) 1 else if (s <= 18 \* bound) 2 else if (s <= 22 \* bound) 3 else 4;$|    let band = if (s <= 12 * bound) 1 else if (s <= 18 * bound) 2 else if (s <= 24 * bound) 3 else 4;|' src/CtlFold.mo
try ctl-chain-unhashed-amount Controls \
  sed -i 's|^    SR\.putNat(d, amount, W\.MONEY);$|    SR.putNat(d, 0, W.MONEY);|' src/CtlFold.mo
try ctl-seal-tip-unread Controls \
  sed -i 's|^      sealed := { sealed with madE10 = b\.madE10; band = b\.band; chiE2 = b\.chiE2; sealedBlock = c\.block; tip = c\.tip };$|      sealed := { sealed with madE10 = b.madE10; band = b.band; chiE2 = b.chiE2; sealedBlock = c.block; tip = zero32() };|' src/CtlFold.mo
try ctl-seal-keeps-run-open Controls \
  sed -i 's|^        case (?s) RowStore\.put<CTR\.Standing>(c\.ctl\.standings, CTR\.standing, companyId, { s with openRunId = 0; lastBlock = c\.block });$|        case (?s) RowStore.put<CTR.Standing>(c.ctl.standings, CTR.standing, companyId, { s with lastBlock = c.block });|' src/CtlFold.mo
try ctl-hash-unbounded-population Controls \
  sed -i 's|^    SR\.putNat(w, run\.billBound, W\.ID);$|    SR.putNat(w, 0, W.ID);|' src/CtlFold.mo
try ctl-done-run-sliced Controls \
  sed -i 's|^    if (run\.phase == #done) return #err(#runDone { runId });$|    if (false) return #err(#runDone { runId });|' src/CtlFold.mo
try ctl-finding-of-run-not-done Controls \
  sed -i 's|^    if (run\.phase != #done) return #err(#runNotDone { runId = x\.runId });$|    if (false) return #err(#runNotDone { runId = x.runId });|' src/CtlFold.mo
try ctl-finding-concluded-twice Controls \
  sed -i 's|^    if (x\.state != #open) return #err(#findingConcluded { findingId });$|    if (false) return #err(#findingConcluded { findingId });|' src/CtlFold.mo
try ctl-preparer-concludes Controls \
  sed -i 's|^    if (c\.caller == x\.preparer) return #err(#concluderPrepared { subject = c\.caller });$|    if (false) return #err(#concluderPrepared { subject = c.caller });|' src/CtlFold.mo
try ctl-poster-concludes Controls \
  sed -i 's|^    if (c\.caller == x\.poster) return #err(#concluderPosted { subject = c\.caller });$|    if (false) return #err(#concluderPosted { subject = c.caller });|' src/CtlFold.mo
try ctl-noteless-conclusion Controls \
  sed -i 's|^    if (Text\.size(stripped(note)) == 0) return #err(#noteRequired);$|    if (false) return #err(#noteRequired);|' src/CtlFold.mo
try ctl-confirmed-uncounted Controls \
  sed -i 's|^      run with open = run\.open - 1; confirmed = run\.confirmed + (if (confirmed) 1 else 0); lastBlock = c\.block });$|      run with open = run.open - 1; confirmed = run.confirmed; lastBlock = c.block });|' src/CtlFold.mo
try ctl-finding-of-another-company Controls \
  sed -i '/^  public func concludeFinding(c : Ctx/,/^  };$/ s|^    if (x\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x\.companyId });$|    if (false) return #err(#wrongCompany { expected = companyId; found = x.companyId });|' src/CtlFold.mo
try ctl-codeless-procedure Controls \
  sed -i 's|^    if (Text\.size(codeText) == 0) return #err(#codeRequired);$|    if (false) return #err(#codeRequired);|' src/CtlFold.mo
try ctl-procedure-code-twice Controls \
  sed -i 's|^    if (procedureByCode(c\.ctl, f\.companyId, code) != null) return #err(#codeTaken { code = codeText });$|    if (false) return #err(#codeTaken { code = codeText });|' src/CtlFold.mo
try ctl-titleless-procedure Controls \
  sed -i 's|^    if (Text\.size(stripped(f\.title)) == 0) return #err(#titleRequired);$|    if (false) return #err(#titleRequired);|' src/CtlFold.mo
try ctl-employee-prepares Controls \
  sed -i 's|^      case (#ok(#Employee)) return #err(#notAPreparer { subject = c\.caller });$|      case (#ok(#Employee)) {};|' src/CtlFold.mo
try ctl-procedure-of-another-company Controls \
  sed -i 's|^    if (proc\.companyId != f\.companyId) return #err(#wrongCompany { expected = f\.companyId; found = proc\.companyId });$|    if (false) return #err(#wrongCompany { expected = f.companyId; found = proc.companyId });|' src/CtlFold.mo
try ctl-conclusion-period-reversed Controls \
  sed -i '/^  public func prepareControlConclusion(c : Ctx/,/^  };$/ s|^    if (f\.fromDay > f\.throughDay) return #err(#periodReversed { fromDay = f\.fromDay; throughDay = f\.throughDay });$|    if (false) return #err(#periodReversed { fromDay = f.fromDay; throughDay = f.throughDay });|' src/CtlFold.mo
try ctl-period-concluded-twice Controls \
  sed -i 's|^    if (conclusionOfPeriod(c\.ctl, f\.procedureId, f\.fromDay, f\.throughDay) != null) return #err(#periodConcluded { procedureId = f\.procedureId; fromDay = f\.fromDay; throughDay = f\.throughDay });$|    if (false) return #err(#periodConcluded { procedureId = f.procedureId; fromDay = f.fromDay; throughDay = f.throughDay });|' src/CtlFold.mo
try ctl-screening-without-run Controls \
  sed -i 's|^      if (f\.runId == 0) return #err(#runRequired { procedureId = f\.procedureId });$|      if (false) return #err(#runRequired { procedureId = f.procedureId });|' src/CtlFold.mo
try ctl-run-of-another-company-cited Controls \
  sed -i 's|^      if (run\.companyId != f\.companyId) return #err(#wrongCompany { expected = f\.companyId; found = run\.companyId });$|      if (false) return #err(#wrongCompany { expected = f.companyId; found = run.companyId });|' src/CtlFold.mo
try ctl-run-not-done-cited Controls \
  sed -i '/^  public func prepareControlConclusion(c : Ctx/,/^  };$/ s|^      if (run\.phase != #done) return #err(#runNotDone { runId = f\.runId });$|      if (false) return #err(#runNotDone { runId = f.runId });|' src/CtlFold.mo
try ctl-run-of-another-period-cited Controls \
  sed -i 's|^      if (run\.fromDay != f\.fromDay or run\.throughDay != f\.throughDay) return #err(#runPeriodDiffers { runId = f\.runId; fromDay = run\.fromDay; throughDay = run\.throughDay });$|      if (false) return #err(#runPeriodDiffers { runId = f.runId; fromDay = run.fromDay; throughDay = run.throughDay });|' src/CtlFold.mo
try ctl-open-findings-effective Controls \
  sed -i 's|^    if (run\.open > 0) return ?#findingsOpen { runId; open = run\.open };$|    if (false) return ?#findingsOpen { runId; open = run.open };|' src/CtlFold.mo
try ctl-confirmed-findings-effective Controls \
  sed -i 's|^    if (run\.confirmed > 0) return ?#findingsConfirmed { runId; confirmed = run\.confirmed };$|    if (false) return ?#findingsConfirmed { runId; confirmed = run.confirmed };|' src/CtlFold.mo
try ctl-run-cited-off-screening Controls \
  sed -i 's|^      if (f\.runId != 0) return #err(#runNotEvidence { procedureId = f\.procedureId });$|      if (false) return #err(#runNotEvidence { procedureId = f.procedureId });|' src/CtlFold.mo
try ctl-noteless-procedure-conclusion Controls \
  sed -i 's|^    if (Text\.size(stripped(f\.note)) == 0) return #err(#noteRequired);$|    if (false) return #err(#noteRequired);|' src/CtlFold.mo
try ctl-reviewed-twice Controls \
  sed -i 's|^    if (x\.state != #prepared) return #err(#conclusionReviewed { conclusionId });$|    if (false) return #err(#conclusionReviewed { conclusionId });|' src/CtlFold.mo
try ctl-preparer-reviews Controls \
  sed -i 's|^    if (c\.caller == x\.preparedBy) return #err(#reviewerPrepared { subject = c\.caller });$|    if (false) return #err(#reviewerPrepared { subject = c.caller });|' src/CtlFold.mo
try ctl-conclusion-of-another-company Controls \
  sed -i '/^  public func reviewControlConclusion(c : Ctx/,/^  };$/ s|^    if (x\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x\.companyId });$|    if (false) return #err(#wrongCompany { expected = companyId; found = x.companyId });|' src/CtlFold.mo

# ── voice over IP: calls carrying out the pipeline's activities, recordings in the evidence store (src/VoipFold.mo, src/CrmFold.mo, src/State.mo, src/SmsRows.mo; test/Voip.test.mo) ──
# Every rule the Voip battery states, removed or moved one at a time: who logs a call and attaches its recording, in
# standing; the number in one form and the one 00 of its prefix; the seconds of a call spoken in and of one that was
# not, each bound at its edge; the note's bound; every condition on the activity a call carries out, asked whole
# before anything is written, and the lead of a scheduled one archived since; the call's own figures; every condition
# on a recording and its document; and the lead of a call nobody scheduled, asked by `createActivity`'s own reference
# check, injected here. Not injected: the number's fit to its field, which a plus and at most fifteen digits always
# make.
try voip-no-such-company Voip \
  sed -i 's|^    if (not c\.companyExists(f\.companyId)) return #err(#wrongCompany { expected = f\.companyId; found = 0 });$|    if (false) return #err(#wrongCompany { expected = f.companyId; found = 0 });|' src/VoipFold.mo
# Not injected, and why: voip-stranger-logs - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).
try voip-number-as-written Voip \
  sed -i 's|^    let ?number = SmsRows\.normaliseNumber(f\.number) else return #err(#notANumber { number = f\.number });$|    let ?number = ?f.number else return #err(#notANumber { number = f.number });|' src/VoipFold.mo
try voip-seconds-unbounded Voip \
  sed -i 's|^    if (f\.seconds < lo or f\.seconds > hi) {$|    if (false) {|' src/VoipFold.mo
try voip-seconds-day-excluded Voip \
  sed -i 's|^    if (f\.seconds < lo or f\.seconds > hi) {$|    if (f.seconds < lo or f.seconds >= hi) {|' src/VoipFold.mo
try voip-spoken-of-no-seconds Voip \
  sed -i 's|^    let (lo, hi) = if (E\.callConnected(f\.outcome)) (1, W\.CALL_SECONDS_MAX) else (0, 0);$|    let (lo, hi) = if (E.callConnected(f.outcome)) (0, W.CALL_SECONDS_MAX) else (0, 0);|' src/VoipFold.mo
try voip-unspoken-may-last Voip \
  sed -i 's|^    let (lo, hi) = if (E\.callConnected(f\.outcome)) (1, W\.CALL_SECONDS_MAX) else (0, 0);$|    let (lo, hi) = if (E.callConnected(f.outcome)) (1, W.CALL_SECONDS_MAX) else (0, W.CALL_SECONDS_MAX);|' src/VoipFold.mo
try voip-voicemail-not-spoken Voip \
  sed -i 's|^  public func callConnected(x : CallOutcome) : Bool { x == #answered or x == #voicemail };$|  public func callConnected(x : CallOutcome) : Bool { x == #answered };|' src/Enums.mo
try voip-seconds-max-a-day-less Voip \
  sed -i 's|^  public let CALL_SECONDS_MAX : Nat = 86_400;$|  public let CALL_SECONDS_MAX : Nat = 86_399;|' src/Widths.mo
try voip-note-unbounded Voip \
  sed -i 's|^    if (Text\.size(f\.note) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });$|    if (false) return #err(#textTooLong { max = MAX_TEXT });|' src/VoipFold.mo
try voip-note-bound-excluded Voip \
  sed -i 's|^    if (Text\.size(f\.note) > MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });$|    if (Text.size(f.note) >= MAX_TEXT) return #err(#textTooLong { max = MAX_TEXT });|' src/VoipFold.mo
try voip-pipeline-unasked Voip \
  sed -i 's|^    switch (c\.checkCallActivity(f\.companyId, f\.leadId, f\.activityId)) { case (?reason) return #err(#pipeline { reason }); case null {} };$|    switch (c.checkCallActivity(f.companyId, f.leadId, f.activityId)) { case (?_) {}; case null {} };|' src/VoipFold.mo
try voip-activity-carried-twice Voip \
  sed -i 's|^      switch (callOfActivity(c\.voip, f\.activityId)) { case (?(callId, _)) return #err(#activityCarriedOut { activityId = f\.activityId; callId }); case null {} };$|      switch (callOfActivity(c.voip, f.activityId)) { case (?(_, _)) {}; case null {} };|' src/VoipFold.mo
try voip-call-names-zero-activity Voip \
  sed -i 's|^      companyId = f\.companyId; leadId = f\.leadId; activityId; member = c\.caller; direction = f\.direction; number = numberField;$|      companyId = f.companyId; leadId = f.leadId; activityId = f.activityId; member = c.caller; direction = f.direction; number = numberField;|' src/VoipFold.mo
try voip-call-day-none Voip \
  sed -i 's|^      outcome = f\.outcome; seconds = f\.seconds; day = c\.day; consent = f\.consent; note; recordingId = 0; recordedDay = 0; lastBlock = c\.block });$|      outcome = f.outcome; seconds = f.seconds; day = 0; consent = f.consent; note; recordingId = 0; recordedDay = 0; lastBlock = c.block });|' src/VoipFold.mo
try voip-consent-assumed Voip \
  sed -i 's|^      outcome = f\.outcome; seconds = f\.seconds; day = c\.day; consent = f\.consent; note; recordingId = 0; recordedDay = 0; lastBlock = c\.block });$|      outcome = f.outcome; seconds = f.seconds; day = c.day; consent = true; note; recordingId = 0; recordedDay = 0; lastBlock = c.block });|' src/VoipFold.mo
try voip-counter-stuck Voip \
  sed -i 's|^    c\.voip\.nextCallId += 1;$|    c.voip.nextCallId += 0;|' src/VoipFold.mo
try voip-summary-directions-swapped Voip \
  sed -i 's|^    (switch (direction) { case (#inbound) "Call from "; case (#outbound) "Call to " }) # number$|    (switch (direction) { case (#inbound) "Call to "; case (#outbound) "Call from " }) # number|' src/VoipFold.mo
try voip-feedback-no-seconds Voip \
  sed -i 's|^    let head = E\.callOutcomeText(outcome) # (if (E\.callConnected(outcome)) ", " # Nat\.toText(seconds) # " s" else "");$|    let head = E.callOutcomeText(outcome) # (if (E.callConnected(outcome)) ", " # Nat.toText(seconds) else "");|' src/VoipFold.mo
try voip-attach-wrong-company Voip \
  sed -i 's|^    if (x\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = x\.companyId });$|    if (false) return #err(#wrongCompany { expected = companyId; found = x.companyId });|' src/VoipFold.mo
# Not injected, and why: voip-attach-stranger - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).
try voip-attach-anybody Voip \
  sed -i 's|^    if (x\.member != c\.caller) return #err(#notTheCaller { callId; subject = c\.caller });$|    if (false) return #err(#notTheCaller { callId; subject = c.caller });|' src/VoipFold.mo
try voip-attach-nothing-spoken Voip \
  sed -i 's|^    if (not E\.callConnected(x\.outcome)) return #err(#nothingSpoken { callId; outcome = E\.callOutcomeText(x\.outcome) });$|    if (false) return #err(#nothingSpoken { callId; outcome = E.callOutcomeText(x.outcome) });|' src/VoipFold.mo
try voip-attach-without-consent Voip \
  sed -i 's|^    if (not x\.consent) return #err(#noConsent { callId });$|    if (false) return #err(#noConsent { callId });|' src/VoipFold.mo
try voip-attach-twice Voip \
  sed -i 's|^    if (x\.recordingId != 0) return #err(#alreadyRecorded { callId; documentId = x\.recordingId });$|    if (false) return #err(#alreadyRecorded { callId; documentId = x.recordingId });|' src/VoipFold.mo
try voip-attach-doc-of-another-company Voip \
  sed -i 's|^    if (d\.companyId != companyId) return #err(#wrongCompany { expected = companyId; found = d\.companyId });$|    if (false) return #err(#wrongCompany { expected = companyId; found = d.companyId });|' src/VoipFold.mo
try voip-attach-doc-any-kind Voip \
  sed -i 's|^    if (d\.kind != #company) return #err(#documentNotShared { documentId });$|    if (false) return #err(#documentNotShared { documentId });|' src/VoipFold.mo
try voip-attach-doc-inactive Voip \
  sed -i 's|^    if (d\.state != #active) return #err(#documentNotActive { documentId });$|    if (false) return #err(#documentNotActive { documentId });|' src/VoipFold.mo
try voip-attach-doc-anybody-s Voip \
  sed -i 's|^    if (d\.uploadedBy != c\.caller) return #err(#notTheUploader { documentId; subject = c\.caller });$|    if (false) return #err(#notTheUploader { documentId; subject = c.caller });|' src/VoipFold.mo
try voip-attach-doc-twice Voip \
  sed -i 's|^    switch (callOfRecording(c\.voip, documentId)) { case (?(other, _)) return #err(#documentARecording { documentId; callId = other }); case null {} };$|    switch (callOfRecording(c.voip, documentId)) { case (?(_, _)) {}; case null {} };|' src/VoipFold.mo
try voip-attach-day-none Voip \
  sed -i 's|^    RowStore\.put<VR\.Call>(c\.voip\.calls, VR\.call, callId, { x with recordingId = documentId; recordedDay = c\.day; lastBlock = c\.block });$|    RowStore.put<VR.Call>(c.voip.calls, VR.call, callId, { x with recordingId = documentId; recordedDay = 0; lastBlock = c.block });|' src/VoipFold.mo
try voip-suspended-in-standing Voip \
  sed -i 's|^          case (?(_, m)) { not (m\.status == #Suspended or m\.status == #Terminated) };$|          case (?(_, m)) { true };|' src/State.mo
try voip-recording-state-unread Voip \
  sed -i '/^    let voipCtx : VoipFold\.Ctx = {/,/^    };$/ s|^          case (?d) ?{ companyId = d\.companyId; kind = d\.kind; state = d\.state; uploadedBy = d\.uploadedBy }; case null null } };$|          case (?d) ?{ companyId = d.companyId; kind = d.kind; state = #active; uploadedBy = d.uploadedBy }; case null null } };|' src/State.mo
try voip-encoding-consent Voip \
  sed -i 's|^    w\.text(f\.number); w\.nat8(En\.callOutcomeByte(f\.outcome)); w\.nat(f\.seconds); w\.bool(f\.consent); w\.text(f\.note);$|    w.text(f.number); w.nat8(En.callOutcomeByte(f.outcome)); w.nat(f.seconds); w.bool(true); w.text(f.note);|' src/Encoding.mo
try crm-activity-refs-lead-of-another-company Voip \
  sed -i '/^  func checkActivityRefs/,/^  };$/ s|^    if (l\.companyId != f\.companyId) return ?(#wrongCompany { expected = f\.companyId; found = l\.companyId });$|    if (false) return ?(#wrongCompany { expected = f.companyId; found = l.companyId });|' src/CrmFold.mo
try crm-activity-refs-lead-archived Voip \
  sed -i '/^  func checkActivityRefs/,/^  };$/ s|^    if (l\.isArchived) return ?(#archived { what = "lead"; id = f\.leadId });$|    if (false) return ?(#archived { what = "lead"; id = f.leadId });|' src/CrmFold.mo
try crm-call-lead-archived-since Voip \
  sed -i '/^  public func checkCallActivity/,/^  };$/ s|^      case (?l) { if (l\.isArchived) return ?(#archived { what = "lead"; id = leadId }) };$|      case (?l) { if (false) return ?(#archived { what = "lead"; id = leadId }) };|' src/CrmFold.mo
try crm-call-activity-of-another-company Voip \
  sed -i '/^  public func checkCallActivity/,/^  };$/ s|^    if (a\.companyId != companyId) return ?(#wrongCompany { expected = companyId; found = a\.companyId });$|    if (false) return ?(#wrongCompany { expected = companyId; found = a.companyId });|' src/CrmFold.mo
try crm-call-activity-of-another-lead Voip \
  sed -i 's|^    if (a\.leadId != leadId) return ?(#activityOfAnotherLead { activityId; leadId });$|    if (false) return ?(#activityOfAnotherLead { activityId; leadId });|' src/CrmFold.mo
try crm-call-activity-any-kind Voip \
  sed -i 's|^    if (a\.kind != #phoneCall) return ?(#notAPhoneCall { activityId });$|    if (false) return ?(#notAPhoneCall { activityId });|' src/CrmFold.mo
try crm-call-activity-archived Voip \
  sed -i '/^  public func checkCallActivity/,/^  };$/ s|^    if (a\.isArchived) return ?(#archived { what = "activity"; id = activityId });$|    if (false) return ?(#archived { what = "activity"; id = activityId });|' src/CrmFold.mo
try crm-call-activity-done Voip \
  sed -i '/^  public func checkCallActivity/,/^  };$/ s|^    if (a\.isDone) return ?(#activityDone { activityId });$|    if (false) return ?(#activityDone { activityId });|' src/CrmFold.mo
try crm-call-activity-anybody-s Voip \
  sed -i 's|^    if (a\.assignee != c\.caller) return ?(#notTheAssignee { activityId; subject = c\.caller });$|    if (false) return ?(#notTheAssignee { activityId; subject = c.caller });|' src/CrmFold.mo
try crm-call-activity-feedback-dropped Voip \
  sed -i 's|^    switch (completeActivity(c, companyId, id, feedback)) { case (#ok _) #ok(id); case (#err r) #err(r) }$|    switch (completeActivity(c, companyId, id, "")) { case (#ok _) #ok(id); case (#err r) #err(r) }|' src/CrmFold.mo
try crm-call-activity-due-tomorrow Voip \
  sed -i '/^  public func recordCallActivity/,/^  };$/ s|^      switch (createActivity(c, { companyId; leadId; kind = #phoneCall; summary; note = ""; deadlineDay = c\.day; assignee = c\.caller })) {$|      switch (createActivity(c, { companyId; leadId; kind = #phoneCall; summary; note = ""; deadlineDay = c.day + 1; assignee = c.caller })) {|' src/CrmFold.mo
try crm-call-activity-summary-dropped Voip \
  sed -i '/^  public func recordCallActivity/,/^  };$/ s|^      switch (createActivity(c, { companyId; leadId; kind = #phoneCall; summary; note = ""; deadlineDay = c\.day; assignee = c\.caller })) {$|      switch (createActivity(c, { companyId; leadId; kind = #phoneCall; summary = "Call"; note = ""; deadlineDay = c.day; assignee = c.caller })) {|' src/CrmFold.mo
try sms-number-prefix-four Voip \
  sed -i 's|^      for (ch in digits\.chars()) { if (i >= 2) rest #= Text\.fromChar(ch); i += 1 };$|      for (ch in digits.chars()) { if (i >= 4) rest #= Text.fromChar(ch); i += 1 };|' src/SmsRows.mo

# ── product lifecycle: engineering changes as versions of a bill, pinned productions (src/PlmFold.mo, src/MrpFold.mo; test/Plm.test.mo) ──
# Every rule the Plm battery states, removed or moved one at a time: who proposes, decides and withdraws, in standing,
# and that no member decides a change they proposed; the code, the reason and their bounds; the bill live and the
# company's; the effective day within its field, not before today and strictly after the latest version's; the bill as
# it stands refused; the components asked the bill's own questions when proposed and again when approved; the version
# number, the decider and the closure an approval writes; the version in effect on a day, the pin a plan writes and
# the version a production and an explosion read, with its quantity. Not injected: the 255th version, which would take
# 254 approvals of one bill to reach, and the depth bound, which the components share with a bill's declaration and
# which no version in the battery comes near.
try plm-no-such-company Plm \
  sed -i 's|^    if (not c\.companyExists(f\.companyId)) return #err(#noSuchCompany { companyId = f\.companyId });$|    if (false) return #err(#noSuchCompany { companyId = f.companyId });|' src/PlmFold.mo
# Not injected, and why: plm-stranger-proposes - the company-authority gate's holders (src/Gate.mo) refuse a non-member
# before any fold, so the fold's own member check is never reached; the isolation battery holds every
# family's holders to its own table (test/IsolationHolders.mo).
try plm-no-code Plm \
  sed -i 's|^    if (Text\.size(f\.code) == 0) return #err(#codeDoesNotFit { value = f\.code; max = W\.ACCOUNT_CODE });$|    if (false) return #err(#codeDoesNotFit { value = f.code; max = W.ACCOUNT_CODE });|' src/PlmFold.mo
try plm-code-taken Plm \
  sed -i 's|^      case (?_) return #err(#changeCodeTaken { code = f\.code });$|      case (?_) {};|' src/PlmFold.mo
try plm-no-reason Plm \
  sed -i 's|^    if (Text\.size(f\.reason) == 0) return #err(#reasonEmpty);$|    if (false) return #err(#reasonEmpty);|' src/PlmFold.mo
try plm-reason-bound Plm \
  sed -i 's|^    if (Text\.size(f\.reason) > MAX_TEXT) return #err(#textTooLong { field = "reason"; max = MAX_TEXT });$|    if (Text.size(f.reason) > MAX_TEXT + 1) return #err(#textTooLong { field = "reason"; max = MAX_TEXT });|' src/PlmFold.mo
try plm-bill-of-another-company Plm \
  sed -i 's|^    if (b\.companyId != companyId) return ?#noSuchBom { bomId };$|    if (false) return ?#noSuchBom { bomId };|' src/PlmFold.mo
try plm-retired-bill Plm \
  sed -i 's|^    if (not b\.isActive) return ?#bomRetired { bomId };$|    if (false) return ?#bomRetired { bomId };|' src/PlmFold.mo
try plm-day-past-field Plm \
  sed -i 's|^    if (effectiveDay >= F\.pow256(W\.DAY)) return ?#dayTooLarge { day = effectiveDay };$|    if (false) return ?#dayTooLarge { day = effectiveDay };|' src/PlmFold.mo
try plm-day-past Plm \
  sed -i 's|^    if (effectiveDay < c\.day) return ?#effectiveDayPast { effectiveDay; today = c\.day };$|    if (false) return ?#effectiveDayPast { effectiveDay; today = c.day };|' src/PlmFold.mo
try plm-today-past Plm \
  sed -i 's|^    if (effectiveDay < c\.day) return ?#effectiveDayPast { effectiveDay; today = c\.day };$|    if (effectiveDay <= c.day) return ?#effectiveDayPast { effectiveDay; today = c.day };|' src/PlmFold.mo
try plm-order-unkept Plm \
  sed -i 's|^    if (now\.version > 1 and effectiveDay <= now\.day) {$|    if (false) {|' src/PlmFold.mo
try plm-same-day-follows Plm \
  sed -i 's|^    if (now\.version > 1 and effectiveDay <= now\.day) {$|    if (now.version > 1 and effectiveDay < now.day) {|' src/PlmFold.mo
try plm-components-unasked Plm \
  sed -i 's|^    switch (MrpFold\.checkBomLines(c\.mrp, { companyId; categoryId = b\.categoryId; quantity; lines })) {$|    switch (null : ?MrpFold.Refusal) {|' src/PlmFold.mo
try plm-no-change-accepted Plm \
  sed -i 's|^    if (quantity == now\.made\.quantity and sameLines(lines, now\.made\.lines)) return ?#noChange { bomId; version = now\.version };$|    if (false) return ?#noChange { bomId; version = now.version };|' src/PlmFold.mo
try plm-quantities-unread Plm \
  sed -i 's|^      if (a\[i\]\.categoryId != b\[i\]\.categoryId or a\[i\]\.quantity != b\[i\]\.quantity) return false;$|      if (a[i].categoryId != b[i].categoryId) return false;|' src/PlmFold.mo
try plm-any-role-decides Plm \
  sed -i 's|^        if (not (role == #CompanyAdmin or role == #Director or role == #Manager)) return ?#notAnApprover { subject = c\.caller };$|        if (false) return ?#notAnApprover { subject = c.caller };|' src/PlmFold.mo
try plm-manager-not-decider Plm \
  sed -i 's|^        if (not (role == #CompanyAdmin or role == #Director or role == #Manager)) return ?#notAnApprover { subject = c\.caller };$|        if (not (role == #CompanyAdmin or role == #Director)) return ?#notAnApprover { subject = c.caller };|' src/PlmFold.mo
try plm-proposer-decides Plm \
  sed -i 's|^    if (Principal\.equal(x\.proposer, c\.caller)) return ?#approverIsProposer { ecoId };$|    if (false) return ?#approverIsProposer { ecoId };|' src/PlmFold.mo
try plm-change-of-another-company Plm \
  sed -i 's|^    if (x\.companyId != companyId) return #err(#noSuchChange { ecoId });$|    if (false) return #err(#noSuchChange { ecoId });|' src/PlmFold.mo
try plm-decided-twice Plm \
  sed -i 's|^    if (x\.state != #proposed) return #err(#changeNotProposed { ecoId; state = E\.ecoStateText(x\.state) });$|    if (false) return #err(#changeNotProposed { ecoId; state = E.ecoStateText(x.state) });|' src/PlmFold.mo
try plm-approval-unasked Plm \
  sed -i 's|^    switch (checkVersion(c, companyId, x\.bomId, x\.quantity, made\.lines, x\.effectiveDay)) {$|    switch (null : ?Refusal) {|' src/PlmFold.mo
try plm-version-skips Plm \
  sed -i 's|^    let version = latest(c, x\.bomId, b)\.version + 1;$|    let version = latest(c, x.bomId, b).version + 2;|' src/PlmFold.mo
try plm-decider-unrecorded Plm \
  sed -i 's|^      x with version; state = #approved; decidedBy = c\.caller; decidedDay = c\.day; lastBlock = c\.block$|      x with version; state = #approved; decidedBy = x.proposer; decidedDay = c.day; lastBlock = c.block|' src/PlmFold.mo
try plm-closure-unextended Plm \
  sed -i 's|^    MrpFold\.extendClosure(c\.mrp, { companyId; categoryId = b\.categoryId; lines = made\.lines });$|    ignore b;|' src/PlmFold.mo
try plm-reject-by-anyone Plm \
  sed -i 's|^    switch (decider(c, companyId, ecoId, x)) { case (?why) return #err(why); case null {} };$|    switch (null : ?Refusal) { case (?why) return #err(why); case null {} };|' src/PlmFold.mo
try plm-reject-without-reason Plm \
  sed -i 's|^    if (Text\.size(reason) == 0) return #err(#reasonEmpty);$|    if (false) return #err(#reasonEmpty);|' src/PlmFold.mo
try plm-withdrawn-by-another Plm \
  sed -i 's|^    if (not Principal\.equal(x\.proposer, c\.caller)) return #err(#notTheProposer { ecoId });$|    if (false) return #err(#notTheProposer { ecoId });|' src/PlmFold.mo
try plm-withdrawn-out-of-standing Plm \
  sed -i 's|^    switch (inStanding(c, companyId)) { case (?r) return #err(r); case null {} };$|    switch (null : ?Refusal) { case (?r) return #err(r); case null {} };|' src/PlmFold.mo
try plm-version-from-its-day Plm \
  sed -i 's|^      if (x\.effectiveDay > day) break walk;$|      if (x.effectiveDay >= day) break walk;|' src/PlmFold.mo
try plm-no-lines-accepted Plm \
  sed -i 's|^    if (f\.lines\.size() == 0) return ?#noLines;$|    if (false) return ?#noLines;|' src/MrpFold.mo
try plm-too-many-lines-accepted Plm \
  sed -i 's|^    if (f\.lines\.size() > 255) return ?#tooManyLines { lines = f\.lines\.size() };$|    if (false) return ?#tooManyLines { lines = f.lines.size() };|' src/MrpFold.mo
try plm-nothing-made-accepted Plm \
  sed -i 's|^    if (f\.quantity == 0) return ?#bomQuantityZero;$|    if (false) return ?#bomQuantityZero;|' src/MrpFold.mo
try plm-unpinned Plm \
  sed -i 's|^    switch (version) { case (?v) c\.pinVersion(id, f\.companyId, f\.bomId, v\.ecoId); case null {} };$|    switch (version) { case (?v) ignore v; case null {} };|' src/MrpFold.mo
try plm-pinned-at-genesis Plm \
  sed -i 's|^    let version = c\.versionAt(f\.bomId, f\.businessDay);$|    let version = c.versionAt(f.bomId, 0);|' src/MrpFold.mo
try plm-produce-declared Plm \
  sed -i 's|^    let made = versionOf(c, p\.bomId, b, c\.pinnedVersion(productionId));$|    let made = versionOf(c, p.bomId, b, null);|' src/MrpFold.mo
try plm-version-quantity-unread Plm \
  sed -i 's|^      let q = componentQuantity(l\.quantity, quantity, made\.quantity);$|      let q = componentQuantity(l.quantity, quantity, b.quantity);|' src/MrpFold.mo
try plm-explode-declared Plm \
  sed -i 's|^            let made = versionOf(c, bomId, b, c\.versionAt(bomId, c\.day));$|            let made = versionOf(c, bomId, b, null);|' src/MrpFold.mo

# ── the company-authority gate ──────────────────────────────────────────────────
#
# Who may send each act (src/Gate.mo): the holders of a family, the
# gate asked before every fold, the founder made administrator by the act that founds the company, only an
# administrator granting the administrator's role, the record a command names read as its company's, an upload
# its uploader's, a visitor's act only to a company that exists; and the platform operator claimed once, before
# any company, handed over in two steps. Each line removes one of them; Isolation or Platform must go red.
try gate-holders-widened Isolation \
  sed -i 's|^    ("closePeriod", #roles(\[#CompanyAdmin, #Director, #Manager\])),$|    ("closePeriod", #member),|' src/Gate.mo
try gate-one-family-let-through Isolation \
  sed -i 's|^    if (ok) null else ?{ act; company; held }$|    if (ok or act == "createLead") null else ?{ act; company; held }|' src/Gate.mo
try gate-not-asked Isolation \
  sed -i 's|^    switch (Gate\.authorise(gateView(s), caller, c)) { case (?r) return #err(#notEntitled r); case null {} };$|    ignore gateView(s);|' src/State.mo
try gate-founder-not-administrator Isolation \
  sed -i 's|^      companyId = id; subject = caller; companyRole = #CompanyAdmin; platformRole = #None;$|      companyId = id; subject = caller; companyRole = #Employee; platformRole = #None;|' src/State.mo
try gate-hr-grants-administrator Isolation \
  sed -i 's|^    if (companyRole == #CompanyAdmin and not callerIsAdministrator(c, companyId)) return #err(#onlyAnAdministrator { companyId; subject });$|    if (false) return #err(#onlyAnAdministrator { companyId; subject });|' src/HrFold.mo
try gate-hr-raises-to-administrator Isolation \
  sed -i 's|^    if ((companyRole == #CompanyAdmin or m\.companyRole == #CompanyAdmin) and not callerIsAdministrator(c, companyId)) return #err(#onlyAnAdministrator { companyId; subject });$|    if (false) return #err(#onlyAnAdministrator { companyId; subject });|' src/HrFold.mo
try gate-platform-role-accepted Isolation \
  sed -i 's|^    if (platformRole != #None) return #err(#platformRoleNotNone { platformRole = debug_show(platformRole) });$|    if (false) return #err(#platformRoleNotNone { platformRole = debug_show(platformRole) });|' src/HrFold.mo
try gate-branch-of-no-company Isolation \
  sed -i 's|^          case (#branch id) { switch (RowStore\.get<HrRows\.Branch>(s\.hr\.branches, HrRows\.branch, id)) { case (?r) ?r\.companyId; case null null } };$|          case (#branch id) { ignore id; null };|' src/State.mo
try gate-uploader-anyone Isolation \
  sed -i 's|^        switch (r\.source) { case (#upload blobId) { v\.uploadOwner(blobId) == ?caller }; case _ false }$|        switch (r.source) { case (#upload blobId) { v.uploadOwner(blobId) != null }; case _ false }|' src/Gate.mo
try gate-visitor-to-no-company Isolation \
  sed -i 's|^      case (#visitor) { switch (company) { case (?n) v\.companyExists(n); case null false } };$|      case (#visitor) { switch (company) { case (?n) { ignore n; true }; case null false } };|' src/Gate.mo
try platform-second-claim Platform \
  sed -i 's|^      case (#claim) { not v\.operatorNamed() and not v\.anyCompany() };$|      case (#claim) { not v.anyCompany() };|' src/Gate.mo
try platform-claim-after-a-company Platform \
  sed -i 's|^      case (#claim) { not v\.operatorNamed() and not v\.anyCompany() };$|      case (#claim) { not v.operatorNamed() };|' src/Gate.mo
try platform-acts-by-anyone Platform \
  sed -i 's|^      case (#platform) v\.isOperator(caller);$|      case (#platform) v.operatorNamed();|' src/Gate.mo
try platform-accepted-by-anyone Platform \
  sed -i 's|^      case (#offered) { v\.offered() == ?caller };$|      case (#offered) { v.offered() != null };|' src/Gate.mo
try platform-offer-not-spent Platform \
  sed -i 's|^      operator = c\.caller; sinceBlock = c\.block; offered = null; offeredBlock = c\.block; lastBlock = c\.block;$|      operator = c.caller; sinceBlock = c.block; offered = x.offered; offeredBlock = c.block; lastBlock = c.block;|' src/PlatformFold.mo
try platform-withdrawal-of-nothing Platform \
  sed -i 's|^      case null { if (x\.offered == null) return #err(#noOfferToWithdraw) };$|      case null {};|' src/PlatformFold.mo
try platform-offer-to-itself Platform \
  sed -i 's|^      case (?p) { if (p == x\.operator) return #err(#offerToSelf { operator = x\.operator }) };$|      case (?p) { ignore p };|' src/PlatformFold.mo

# ── the audit index ───────────────────────────────────────────────────────────
#
# Two entries for every accepted block, under its caller and under its company, none for a refused one; read a page
# at a time from a cursor, by the company's administrator and the platform operator, and by each person for their
# own; caught up from the log at an upgrade (src/AuditIndex.mo, src/State.mo, src/Contract.mo).

try audit-write-dropped Audit \
  sed -i 's|^        AuditIndex\.write(s\.audit, index, caller, indexedUnder, route\.tag);$|        ignore indexedUnder;|' src/State.mo
try audit-refused-act-written Audit \
  sed -i 's|^      case (#err _) {};$|      case (#err _) { AuditIndex.write(s.audit, index, caller, company, route.tag) };|' src/State.mo
try audit-every-act-of-no-company Audit \
  sed -i 's|case _ company };$|case _ 0 };|' src/State.mo
try audit-founding-of-no-company Audit \
  sed -i 's|case (#founding) { if (effects\.size() > 0) effects\[0\] else 0 }|case (#founding) { 0 }|' src/State.mo
try audit-company-entry-names-nobody Audit \
  sed -i 's|^    let byCompany : AR\.CompanyEntry = { tag; caller };$|    let byCompany : AR.CompanyEntry = { tag; caller = AR.callerOf(0) };|' src/AuditIndex.mo
try audit-caller-key-without-height Audit \
  sed -i 's|^    natOf(Blob\.toArray(F\.principalField(caller))) \* HEIGHTS + height$|    natOf(Blob.toArray(F.principalField(caller))) * HEIGHTS|' src/AuditRows.mo
try audit-cursor-skips-an-entry Audit \
  sed -i 's|case (?h) h + 1; case null 0 } };$|case (?h) h + 2; case null 0 } };|' src/AuditIndex.mo
try audit-company-entries-to-anyone Audit \
  sed -i 's|^    v\.isOperator(reader) or reviews(v\.standing(company, reader))$|    v.isOperator(reader) or true|' src/Gate.mo
try audit-others-entries-to-any-member Audit \
  sed -i 's|^    reviews(v\.standing(company, reader))$|    v.standing(company, reader) != null|' src/Gate.mo
# THE RAW LOG BY THE SAME RULE
try blockbytes-to-anyone Audit \
  sed -i 's|^    v\.isOperator(reader) or reader == sender or (company != 0 and v\.standing(company, reader) == ?#CompanyAdmin)$|    v.isOperator(reader) or true|' src/Gate.mo
try blockbytes-to-any-member Audit \
  sed -i 's|^    v\.isOperator(reader) or reader == sender or (company != 0 and v\.standing(company, reader) == ?#CompanyAdmin)$|    v.isOperator(reader) or reader == sender or (company != 0 and v.standing(company, reader) != null)|' src/Gate.mo
try blockbytes-company-zero-to-an-admin Audit \
  sed -i 's|^    v\.isOperator(reader) or reader == sender or (company != 0 and v\.standing(company, reader) == ?#CompanyAdmin)$|    v.isOperator(reader) or reader == sender or v.standing(if (company == 0) 1 else company, reader) == ?#CompanyAdmin|' src/Gate.mo
try blockbytes-personal-served Audit \
  sed -i 's|^      case (?k) return ?("block " # Nat\.toText(height) # " holds a person|      case (?k) if (false) return ?("block " # Nat.toText(height) # " holds a person|' src/State.mo
try blockbytes-pay-not-personal Audit \
  sed -i '/^    ("setCompensation", #payroll),$/d' src/Personal.mo
try blockbytes-personal-table-names-no-family Audit \
  sed -i 's|^    ("addFamilyMember", #family),$|    ("addFamilyMembers", #family),|' src/Personal.mo

# THE COMPANY AUDITOR: reads, holds no act, made only by an administrator
try auditor-holds-a-write-family Isolation \
  sed -i 's|^    switch (held) { case null false; case (?r) not E\.holdsNoAct(r) }$|    switch (held) { case null false; case (?r) r != #Drafter }|' src/Gate.mo
try no-act-roles-forget-the-auditor Isolation \
  sed -i 's|^  public func holdsNoAct(r : CompanyRole) : Bool { r == #Auditor or r == #Drafter };$|  public func holdsNoAct(r : CompanyRole) : Bool { r == #Drafter };|' src/Enums.mo
try no-act-roles-forget-the-drafter Draft \
  sed -i 's|^  public func holdsNoAct(r : CompanyRole) : Bool { r == #Auditor or r == #Drafter };$|  public func holdsNoAct(r : CompanyRole) : Bool { r == #Auditor };|' src/Enums.mo
# DRAFTS: an act proposed for a person, made an act only by that person or a holder of it by role, through
# the gate and the act's own fold, once and in time; what is drafted held to its company, its kind and its source;
# a draft of a personal act withheld from every read
try draft-accepted-by-anyone Draft \
  sed -i 's|^    if (c\.caller != d\.forPerson and not c\.holdsByRole(c\.caller, act)) return #err(#notForYou { draftId; subject = c\.caller });$|    if (false) return #err(#notForYou { draftId; subject = c.caller });|' src/DraftFold.mo
try draft-holds-by-role-as-any-member Draft \
  sed -i 's|^    switch (holders) { case (#roles rs) holds(rs, held); case (#self rs) holds(rs, held); case _ false }$|    switch (holders) { case (#roles rs) holds(rs, held); case (#self _) held != null; case _ false }|' src/Gate.mo
try draft-acceptance-skips-the-gate Draft \
  sed -i 's|^            switch (Gate\.authorise(gateView(s), caller, act)) { case (?r) return #err(#notEntitled r); case null {} };$|            ignore Gate.authorise(gateView(s), caller, act);|' src/State.mo
try draft-accepted-after-its-last-day Draft \
  sed -i 's|^    if (c\.day > d\.expiryDay) return #err(#expired { draftId; expiryDay = d\.expiryDay; day = c\.day });$|    if (c.day > d.expiryDay + 1_000) return #err(#expired { draftId; expiryDay = d.expiryDay; day = c.day });|' src/DraftFold.mo
try draft-accepted-twice Draft \
  sed -i '0,/^    if (d\.state != #open) return #err(#notOpen { draftId; state = DR\.stateText(d\.state) });$/s||    if (d.state == #rejected) return #err(#notOpen { draftId; state = DR.stateText(d.state) });|' src/DraftFold.mo
try draft-set-aside-by-anyone Draft \
  sed -i 's|^    if (c\.caller != d\.forPerson and c\.caller != d\.proposer) return #err(#notYours { draftId; subject = c\.caller });$|    if (false) return #err(#notYours { draftId; subject = c.caller });|' src/DraftFold.mo
try draft-of-a-draft-act Draft \
  sed -i 's|^    if (act == "proposeDraft" or act == "acceptDraft" or act == "rejectDraft") return ?"a draft act is not itself drafted";$|    if (act == "proposeDraft") return ?"a draft act is not itself drafted";|' src/Gate.mo
try draft-of-another-company Draft \
  sed -i 's|^    if (actCompany != f\.companyId) return #err(#otherCompany { family; companyId = actCompany; draftCompany = f\.companyId });$|    if (actCompany == 0) return #err(#otherCompany { family; companyId = actCompany; draftCompany = f.companyId });|' src/DraftFold.mo
try draft-for-a-member-who-holds-no-act Draft \
  sed -i 's|^    if (not inStandingToAct(c, f\.companyId, f\.forPerson)) return #err(#notForAMember { subject = f\.forPerson });$|    if (c.standing(f.companyId, f.forPerson) == null) return #err(#notForAMember { subject = f.forPerson });|' src/DraftFold.mo
try draft-template-without-its-hash Draft \
  sed -i 's|^        if (src\.sha256\.size() != 32) return #err(#badSource { why = "a template'"'"'s SHA-256 is 32 bytes" });$|        if (src.sha256.size() > 32) return #err(#badSource { why = "a template'"'"'s SHA-256 is 32 bytes" });|' src/DraftFold.mo
try draft-of-a-personal-act-read Draft \
  sed -i 's|^          let personal = Personal\.kindOfTag(d\.tag) != null;$|          let personal = false;|' src/State.mo
try draft-proposal-block-of-a-personal-act-served Draft \
  sed -i 's|^        switch (Enc\.read(Nat8\.fromNat(facts\.version), facts\.bytes)) { case (?act) kindOfFamily(Cmd\.family(act)); case null null }$|        null|' src/Personal.mo
# THE READ METHOD: every kind read by its class of reader, deny by default; a person's payroll, medical,
# disciplinary or family record served by query to nobody; the books the auditor's; a company's page its own rows,
# walked to its end by its cursor and naming the tip it was read at; the request read under its one spelling
try read-personal-served Read \
  sed -i 's|^      case (#personal why) #err("a person'"'"'s " # why # " record, which is served by query to nobody until the chain checks a query'"'"'s sender by its signature");$|      case (#personal _) #ok(#all);|' src/ReadSurface.mo
try read-books-without-the-auditor Read \
  sed -i 's|^      case (#books) { if (acts or r == #Auditor) #ok(#all) else|      case (#books) { if (acts) #ok(#all) else|' src/ReadSurface.mo
try read-members-to-a-role-with-no-act Read \
  sed -i 's|^      case (#members) { if (acts) #ok(#all) else|      case (#members) { if (true) #ok(#all) else|' src/ReadSurface.mo
try read-person-sees-every-row Read \
  sed -i 's|^        if (holds(rs, r)) #ok(#all) else if (acts) #ok(#about reader)$|        if (holds(rs, r)) #ok(#all) else if (acts) #ok(#all)|' src/ReadSurface.mo
try read-page-carries-other-companies Read \
  sed -i 's|^      let mine = companyOf(r) == companyId and (switch (cut)|      let mine = companyOf(r) >= 0 and (switch (cut)|' src/ReadSurface.mo
try read-request-of-two-spellings Read \
  sed -i -e '/^    if (not r\.atEnd()) return null;$/d' -e '/^    if (requestBytes(out) != b) return null;$/d' src/ReadSurface.mo
try read-cursor-stops-short Read \
  sed -i 's|^    let more = i < p\.rows\.size() or p\.next != null;$|    let more = p.next != null;|' src/ReadSurface.mo
try read-page-names-no-tip Read \
  sed -i 's|^    w\.optBlob(tip);$|    w.optBlob(null);|' src/ReadSurface.mo
try read-without-standing Read \
  sed -i 's|^    let cut = switch (RS\.cutFor(holders, St\.standingRole(s, companyId, reader), reader)) {$|    let cut = switch (RS.cutFor(holders, ?#CompanyAdmin, reader)) {|' src/Contract.mo
try read-payslip-to-members Read \
  sed -i 's|^      case "payslip" ?#personal("payroll");$|      case "payslip" ?#members;|' src/ReadKinds.mo
try read-swap-about-its-requester-only Read \
  sed -i 's|case (#about p) func(_ : Nat, r : AttRows\.SwapRequest) : Bool { r\.requester == p or r\.target == p }|case (#about p) func(_ : Nat, r : AttRows.SwapRequest) : Bool { r.requester == p }|' src/ReadKinds.mo
try read-swap-about-nobody Read \
  sed -i 's|case (#about p) func(_ : Nat, r : AttRows\.SwapRequest) : Bool { r\.requester == p or r\.target == p }|case (#about _) func(_ : Nat, _ : AttRows.SwapRequest) : Bool { true }|' src/ReadKinds.mo
try read-private-channel-to-every-member Read \
  sed -i 's|^    not ch\.isPrivate or DscFold\.isIn(s\.dsc, channelId, reader)$|    true|' src/ReadRules.mo
try read-deleted-message-served Read \
  sed -i 's|^    if (r\.isDeleted) return false;$|    ignore r.isDeleted;|' src/ReadRules.mo
try read-notification-to-its-sender-too Read \
  sed -i 's|^    r\.recipient == reader$|    r.recipient == reader or r.sender == reader|' src/ReadRules.mo
try read-anonymous-response-to-hr Read \
  sed -i 's|^        not sv\.isAnonymous and (r\.respondent == reader|        (r.respondent == reader|' src/ReadRules.mo
try read-named-response-to-every-member Read \
  sed -i 's|^        not sv\.isAnonymous and (r\.respondent == reader or sv\.openedBy == reader or held == #HR or held == #CompanyAdmin)$|        not sv.isAnonymous|' src/ReadRules.mo
try read-answer-not-held-to-its-response Read \
  sed -i 's|^      case (?resp) seesResponse(s, resp, reader, held);$|      case (?_) true;|' src/ReadRules.mo
try read-rule-to-the-auditor Read \
  sed -i 's|^      case (#rule _) { if (acts) #ok(#rule { reader; held = r })|      case (#rule _) { if (true) #ok(#rule { reader; held = r })|' src/ReadSurface.mo
try read-platform-to-a-role-with-no-act Read \
  sed -i 's|^      case (#platform) { if (acts or r == #Auditor) #ok(#all)|      case (#platform) { if (true) #ok(#all)|' src/ReadSurface.mo
try read-platform-rows-held-to-a-company Read \
  sed -i 's|limit, func(_ : PayRows\.StatutoryProfile) : Nat { companyId }, keep,|limit, func(_ : PayRows.StatutoryProfile) : Nat { 1 }, keep,|' src/ReadKinds.mo
try read-operator-reads-every-company Read \
  sed -i 's|^    let cut = if (holders == #platform and St\.gateView(s)\.isOperator(reader)) #all$|    let cut = if (St.gateView(s).isOperator(reader)) #all|' src/Contract.mo
try read-operator-refused-the-platform Read \
  sed -i 's|^    let cut = if (holders == #platform and St\.gateView(s)\.isOperator(reader)) #all$|    let cut = if (false) #all|' src/Contract.mo
try read-line-person-not-through-its-claim Read \
  sed -i '/^  func k_expense_line(/,/^  };$/ s|{ case (?q) q\.claimant == p; case null false }|{ case (?_) true; case null false }|' src/ReadKinds.mo
try read-line-company-not-through-its-claim Read \
  sed -i '/^  func k_expense_line(/,/^  };$/ s|func(r : ExpRows\.ExpenseLine) : Nat { switch (RowStore\.get<ExpRows\.ExpenseClaim>(s\.exp\.claims, ExpRows\.expenseClaim, r\.claimId)) { case (?q) q\.companyId; case null 0 } }|func(_ : ExpRows.ExpenseLine) : Nat { companyId }|' src/ReadKinds.mo
try read-directory-carries-the-email Read \
  sed -i '/^  func k_colleague(/,/^  };$/ s|^        w\.text(t(r\.name));$|        w.text(t(r.name));\n        w.text(t(r.email));|' src/ReadKinds.mo
try read-directory-the-person-s-alone Read \
  sed -i 's|^      case "colleague" ?#members;$|      case "colleague" ?#subjectOr([#CompanyAdmin, #HR, #Manager]);|' src/ReadKinds.mo
try hr-grants-an-auditor Isolation \
  sed -i 's|^  func reserved(r : E\.CompanyRole) : Bool { r == #CompanyAdmin or E\.holdsNoAct(r) };$|  func reserved(r : E.CompanyRole) : Bool { r == #CompanyAdmin or r == #Drafter };|' src/HrFold.mo
try auditor-reads-another-company Audit \
  sed -i 's|^    v\.isOperator(reader) or reviews(v\.standing(company, reader))$|    v.isOperator(reader) or reviews(v.standing(1, reader))|' src/Gate.mo
try suspended-auditor-reads Audit \
  sed -i 's|^      case (?(_, m)) { if (m\.status == #Suspended or m\.status == #Terminated) null else ?m\.companyRole };$|      case (?(_, m)) { if (m.status == #Terminated) null else ?m.companyRole };|' src/State.mo
try auditor-named-a-writer Studio \
  sed -i 's|^    for (w in r\.writers\.vals()) { if (E\.holdsNoAct(w)) return ?#auditorWrites };$|    for (w in r.writers.vals()) { if (w == #Drafter) return ?#auditorWrites };|' src/StudioFold.mo
try auditor-named-a-screener Controls \
  sed -i 's|^      if (E\.holdsNoAct(r)) return #err(#auditorScreens);$|      if (r == #Drafter) return #err(#auditorScreens);|' src/CtlFold.mo
try audit-others-entries-across-companies Audit \
  sed -i 's|^      case null { #err({ act = "entriesByCaller"; company = null; held = null }) };$|      case null { #ok(AuditIndex.pageOfCaller(s.audit, subject, after, limit, func(_) { true })) };|' src/State.mo
try audit-others-entries-of-everyone Audit \
  sed -i 's|func(p) { p == subject }|func(_) { true }|' src/State.mo
try audit-own-entries-company-ignored Audit \
  sed -i 's|func(n) { switch (companyId) { case (?c) n == c; case null true } }|func(_) { true }|' src/State.mo
try audit-digest-not-moved Audit \
  sed -i 's|^    st\.digest := C\.hashWithDomain(DIGEST_DOMAIN, Array\.flatten<Nat8>(\[$|    st.digest := if (true) st.digest else C.hashWithDomain(DIGEST_DOMAIN, Array.flatten<Nat8>([|' src/AuditIndex.mo
try audit-digest-not-fingerprinted Audit \
  sed -i 's|^      w\.blobRaw(s\.audit\.digest);$|      ignore s.audit.digest;|' src/State.mo
try audit-caller-table-size-not-fingerprinted Audit \
  sed -i 's|^      w\.nat(RowStore\.size(s\.audit\.byCaller));$|      ignore RowStore.size(s.audit.byCaller);|' src/State.mo
try audit-company-table-size-not-fingerprinted Audit \
  sed -i 's|^      w\.nat(RowStore\.size(s\.audit\.byCompany));$|      ignore RowStore.size(s.audit.byCompany);|' src/State.mo
try audit-catch-up-from-genesis-twice Migration \
  sed -i 's|^      if (h >= from) {|      if (h + 1 > 0) {|' src/Contract.mo
try audit-catch-up-founding-uncounted Migration \
  sed -i 's|if (Cmd\.family(b\.event\.command) == "bootstrapCompany") founded += 1;|if (false) founded += 1;|' src/Contract.mo

# ── ESG: emissions against the ledger's lines and the activities, runs sealed and disclosed (src/EsgFold.mo; test/Esg.test.mo) ──
# Every rule the Esg battery states, removed one at a time: who records and who approves, the version in force and the
# rule standing before the run, which lines and activities are weighed and by what, the arithmetic, the seal, the
# disclosure's one scope-2 method and its prior period.
try esg-employee-records Esg \
  sed -i 's|^      case (#ok(#Employee)) ?#employeeRecords { subject = c\.caller };$|      case (#ok(#Employee)) null;|' src/EsgFold.mo
try esg-set-recorder-approves Esg \
  sed -i '/^  public func approveGwpSet(/,/^  };$/ s|^    if (c\.caller == x\.recordedBy) return #err(#approverRecorded { subject = c\.caller });$|    if (false) return #err(#approverRecorded { subject = c.caller });|' src/EsgFold.mo
try esg-factor-recorder-approves Esg \
  sed -i '/^  public func approveEsgFactor(/,/^  };$/ s|^    if (c\.caller == x\.recordedBy) return #err(#approverRecorded { subject = c\.caller });$|    if (false) return #err(#approverRecorded { subject = c.caller });|' src/EsgFold.mo
try esg-set-not-approved-weighs Esg \
  sed -i 's|^    if (set\.state != #approved) return #err(#gwpSetNotApproved { setId = f\.gwpSetId });$|    if (false) return #err(#gwpSetNotApproved { setId = f.gwpSetId });|' src/EsgFold.mo
try esg-stale-version-approved Esg \
  sed -i 's|^      case (?(_, a)) { if (a\.version > x\.version) return #err(#versionStale { factorId; approvedVersion = a\.version }) };$|      case (?(_, a)) { if (false) return #err(#versionStale { factorId; approvedVersion = a.version }) };|' src/EsgFold.mo
try esg-version-approved-later-in-force Esg \
  sed -i 's|^      if (x\.state == #approved and x\.approvedBlock < block) return ?(id, x);$|      if (x.state == #approved) return ?(id, x);|' src/EsgFold.mo
try esg-rule-set-later-stands Esg \
  sed -i 's|^      if (x\.createdBlock < block and (x\.retiredBlock == 0 or x\.retiredBlock >= block)) return ?(id, x);$|      if (x.retiredBlock == 0 or x.retiredBlock >= block) return ?(id, x);|' src/EsgFold.mo
try esg-retired-rule-stands Esg \
  sed -i 's|^      if (x\.createdBlock < block and (x\.retiredBlock == 0 or x\.retiredBlock >= block)) return ?(id, x);$|      if (x.createdBlock < block) return ?(id, x);|' src/EsgFold.mo
try esg-product-with-account Esg \
  sed -i 's|^    if (f\.productId != 0 and f\.accountId != 0) return #err(#productWithAccount);$|    if (false) return #err(#productWithAccount);|' src/EsgFold.mo
try esg-rule-taken-twice Esg \
  sed -i 's|^      if (x\.retiredBlock == 0) return #err(#ruleTaken { ruleId = id });$|      if (false) return #err(#ruleTaken { ruleId = id });|' src/EsgFold.mo
try esg-partner-rule-skipped Esg \
  sed -i 's|^      if (expense) { switch (ruleAt(st, companyId, 0, partnerId, 0, block)) { case (?r) return ?r; case null {} } };$|      if (false) { switch (ruleAt(st, companyId, 0, partnerId, 0, block)) { case (?r) return ?r; case null {} } };|' src/EsgFold.mo
try esg-bank-line-weighed-by-supplier Esg \
  sed -i 's|^      if (expense) { switch (ruleAt(st, companyId, 0, partnerId, 0, block)) { case (?r) return ?r; case null {} } };$|      if (true) { switch (ruleAt(st, companyId, 0, partnerId, 0, block)) { case (?r) return ?r; case null {} } };|' src/EsgFold.mo
try esg-every-asset-line-counted Esg \
  sed -i 's|^      if (expense or rule != null) {$|      if (true or rule != null) {|' src/EsgFold.mo
try esg-draft-weighed Esg \
  sed -i 's|^    if (m\.state != #posted or m\.moveType == #closing) return;$|    if (m.moveType == #closing) return;|' src/EsgFold.mo
try esg-spend-in-any-currency Esg \
  sed -i 's|^                if (x\.basis != #monetary or fieldText(x\.unit) != currency) miss(c, w, ER\.MISS_LINE_NOT_SPEND, 0, amount)$|                if (x.basis != #monetary) miss(c, w, ER.MISS_LINE_NOT_SPEND, 0, amount)|' src/EsgFold.mo
try esg-foreign-amount-ignored Esg \
  sed -i 's|^    if (l\.amountCurrency == 0) net else if (net < 0) -l\.amountCurrency else l\.amountCurrency$|    net|' src/EsgFold.mo
try esg-cancelled-activity-weighed Esg \
  sed -i 's|^    if (x\.state != #recorded) return;$|    if (false) return;|' src/EsgFold.mo
try esg-activity-unit-ignored Esg \
  sed -i 's|^            if (fieldText(f\.unit) != fieldText(x\.unit)) miss(c, w, ER\.MISS_ACTIVITY_UNIT, x\.departmentId, q)$|            if (false) miss(c, w, ER.MISS_ACTIVITY_UNIT, x.departmentId, q)|' src/EsgFold.mo
try esg-partner-before-product Esg \
  sed -i '/^  public func activityRule(/,/^  };$/ s|^    if (productId != 0) {$|    if (false) {|' src/EsgFold.mo
try esg-gwp-ignored Esg \
  sed -i 's|^      (g, mass, weigh(mass, g\.gwpMilli, 1000))$|      (g, mass, mass)|' src/EsgFold.mo
try esg-rounding-truncates Esg \
  sed -i 's|^    let m = AcctFold\.roundHalfEven(Int\.abs(q) \* num, den);$|    let m = Int.abs(q) * num / den;|' src/EsgFold.mo
try esg-activity-on-locked-day Esg \
  sed -i 's|^    if (f\.day <= lock) return #err(#dayLocked { day = f\.day; lockedThroughDay = lock });$|    if (false) return #err(#dayLocked { day = f.day; lockedThroughDay = lock });|' src/EsgFold.mo
try esg-cancel-on-locked-day Esg \
  sed -i 's|^    if (x\.day <= lock) return #err(#dayLocked { day = x\.day; lockedThroughDay = lock });$|    if (false) return #err(#dayLocked { day = x.day; lockedThroughDay = lock });|' src/EsgFold.mo
try esg-cancel-by-anyone Esg \
  sed -i 's|^    if (c\.caller != x\.recordedBy and role != #CompanyAdmin and role != #Director) return #err(#notTheRecorder { subject = c\.caller });$|    if (false) return #err(#notTheRecorder { subject = c.caller });|' src/EsgFold.mo
try esg-hazardous-water Esg \
  sed -i 's|^    if (f\.hazardous and not isWaste(f\.measure)) return #err(#hazardousNotWaste);$|    if (false) return #err(#hazardousNotWaste);|' src/EsgFold.mo
try esg-run-over-open-days Esg \
  sed -i 's|^    if (f\.throughDay > lock) return #err(#windowNotLocked { throughDay = f\.throughDay; lockedThroughDay = lock });$|    if (false) return #err(#windowNotLocked { throughDay = f.throughDay; lockedThroughDay = lock });|' src/EsgFold.mo
try esg-two-open-runs Esg \
  sed -i 's|^    switch (openRunOf(c\.esg, f\.companyId)) { case (?(runId, _)) return #err(#runOpen { companyId = f\.companyId; runId }); case null {} };$|    switch (null : ?(Nat, ER.Run)) { case (?(runId, _)) return #err(#runOpen { companyId = f.companyId; runId }); case null {} };|' src/EsgFold.mo
try esg-chain-not-the-figures Esg \
  sed -i 's|^      for ((_, x) in figuresInKeyOrder(c\.esg, runId)\.vals()) chain := chainFigure(chain, x);$|      for ((_, x) in figuresInKeyOrder(c.esg, runId).vals()) chain := chainFigure(chain, { x with entries = 0 });|' src/EsgFold.mo
try esg-sealed-without-tip Esg \
  sed -i 's|^      next := { next with sealedBlock = c\.block; tip = c\.tip; chain };$|      next := { next with sealedBlock = c.block; tip = zero32(); chain };|' src/EsgFold.mo
try esg-energy-by-both-methods Esg \
  sed -i 's|^      if (t\.energyEntries\[1\] > 0) (t\.energyBy\[1\], t\.energyEntries\[1\], "location-based")$|      if (false) (t.energyBy[1], t.energyEntries[1], "location-based")|' src/EsgFold.mo
try esg-prior-run-after-this-one Esg \
  sed -i 's|^          if (pr\.companyId != x\.companyId or pr\.phase != #sealed or pr\.throughDay >= x\.fromDay) {$|          if (pr.companyId != x.companyId or pr.phase != #sealed) {|' src/EsgFold.mo

# ── the pool ──────────────────────────────────────────────────────────────────

running=0
for job in "$TMP"/jobs/*; do
  run_one "$job" &
  running=$((running+1))
  if [ "$running" -ge "$CONTROL_JOBS" ]; then wait -n; running=$((running-1)); fi
done
wait

caught=0
missed=0
for job in "$TMP"/jobs/*; do
  result="$TMP/results/$(basename "$job")"
  if [ ! -s "$result" ]; then echo "CONTROL BROKEN: no verdict for job $(basename "$job")"; missed=$((missed+1)); continue; fi
  cat "$result"
  if head -1 "$result" | grep -q '^caught: '; then caught=$((caught+1)); else missed=$((missed+1)); fi
done

echo "count: battery faults injected = $((caught+missed))"
echo "count: battery faults the battery caught = $caught"
if [ "$missed" -ne 0 ]; then echo "BATTERY CONTROL FAILED: $missed fault(s) passed; the battery is not connected"; exit 1; fi
echo "BATTERY CONTROL GREEN"
