#!/usr/bin/env bash
# The advantages' negative control: break each one on purpose and require this tree to notice.
#
# An advantage that has only ever been seen to hold is an advantage nobody knows is connected. Each
# claim in `test/Usp.test.mo` has a fault here that would make it false, and
# the battery must go red on every one. A claim with no fault against it is a claim, not a feature.
#
#   the calendar dates    the day frozen so it no longer follows the calendar
#   the act
#   four eyes             the rule that stops a proposer completing their own act, removed
#   both names in         the second signature recorded as the first, so the row names one person
#   the record            twice
#
# THE CORRUPTED-LOG CASES ARE NOT HERE. A byte changed, a stored hash changed, two blocks swapped,
# one dropped, the tip moved: those are `tools/oracle_control.sh`, run by the gate over this tree's
# own exported log. Repeating them under another name would inflate a count without adding a check.
#
# Attribution: Thebes Core Team. Licence: Apache 2.0.
set -u
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# THE COPY MUST BE ABLE TO FIND THE KERNEL. `tools/packages.sh` looks for it beside the tree it is
# in, and a scratch copy under a temporary directory has no such sibling: the flags would come back
# empty and every injection would "fail to compile" for a reason that has nothing to do with the
# fault. The same lesson the battery's control learned, in the same words.
KERNEL_PATH="$(cd "$HERE/../thebes-kernel" && pwd)" || { echo "CONTROL STOPPED: no kernel beside $HERE"; exit 1; }
export KERNEL="$KERNEL_PATH"

caught=0
missed=0

try() {
  local what="$1"; shift
  local broken="$TMP/$what"
  rm -rf "$broken"; mkdir -p "$broken"
  # EVERY FILE THE TREE HAS, not only the committed ones: a fault injected into a file the copy does
  # not contain goes red because the file is missing, which is a catch for the wrong reason.
  ( cd "$HERE" && git ls-files -z --cached --others --exclude-standard | xargs -0 tar -c ) | tar -x -C "$broken"
  cp -r "$HERE/.mops" "$broken/.mops" 2>/dev/null || true

  # AND THE INJECTION ITSELF MUST HAVE HAPPENED. A `sed` whose pattern has moved exits zero and
  # changes nothing, and the battery then stays green for the honest reason.
  ( cd "$broken" && "$@" ) || { echo "CONTROL BROKEN: the $what injection failed to run"; missed=$((missed+1)); return; }
  if diff -rq "$HERE/src" "$broken/src" > /dev/null 2>&1; then
    echo "CONTROL BROKEN: the $what injection changed nothing"
    missed=$((missed+1)); return
  fi

  if ! ( cd "$broken" && "${MOC:-$HOME/.thebes/toolchain/moc}" -wasi-system-api $(./tools/packages.sh) \
        -o "$TMP/$what.wasm" test/Usp.test.mo ) > "$TMP/$what.build" 2>&1; then
    # A fault that will not compile proves nothing about the battery.
    grep -v warning "$TMP/$what.build" | head -5
    echo "CONTROL BROKEN: the $what injection does not compile"
    missed=$((missed+1)); return
  fi

  # A HOST THAT COULD NOT RUN THE BATTERY IS NOT A BATTERY THAT CAUGHT THE FAULT (tools/wasi_run.sh)
  "$HERE/tools/wasi_run.sh" "$TMP/$what.wasm" "$TMP/$what.log"
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "MISSED: the battery stayed green with $what"
    missed=$((missed+1))
  elif [ "$rc" -eq 75 ]; then
    echo "CONTROL BROKEN: the host could not run the battery for $what"
    missed=$((missed+1))
  else
    echo "caught: $what"
    grep -E '^FAIL' "$TMP/$what.log" | head -2
    caught=$((caught+1))
  fi
}

# THE CALENDAR NO LONGER DATES THE ACT. The day is frozen, so two acts on two days are dated the
# same - which is precisely what a system that took its time from the workstation would do.
try date-not-from-the-calendar \
  sed -i 's|    let event = switch (Log.bind(reading.day, command)) {|    let event = switch (Log.bind(20_709, command)) {|' src/Contract.mo

# FOUR EYES REMOVED. The proposer completes their own act.
try four-eyes-removed \
  sed -i 's|    if (m.proposedBy == c.caller) return #err(#selfPosting { maker = m.proposedBy });||' src/AcctFold.mo

# THE RECORD NAMES ONE PERSON TWICE. The act still needs two, but the row no longer says who the
# second was - which is the difference between a control and a record of a control.
try second-name-not-recorded \
  sed -i 's|      m with state = #posted; sequence = next; postedBy = c.caller; lastBlock = c.block|      m with state = #posted; sequence = next; postedBy = m.proposedBy; lastBlock = c.block|' src/AcctFold.mo

echo "count: advantage faults injected = $((caught+missed))"
echo "count: advantage faults this tree caught = $caught"
if [ "$missed" -ne 0 ]; then
  echo "USP CONTROL FAILED: $missed fault(s) passed; an advantage is claimed and not kept"
  exit 1
fi
echo "USP CONTROL GREEN"
