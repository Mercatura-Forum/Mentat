#!/usr/bin/env bash
# The clock check's negative control: break the property on purpose and require the check to notice.
#
# A check that has only ever been seen green is a check nobody knows is connected. This makes a
# scratch copy of the tree, injects one fault of each class the checker claims to catch, and
# requires the checker to go red on every one.
#
# Attribution: Thebes Core Team. Licence: Apache 2.0.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

caught=0
missed=0

try() {
  local what="$1"; shift
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
  if ! ( cd "$broken" && "$@" ); then
    echo "CONTROL BROKEN: the $what injection command itself failed"
    missed=$((missed+1)); return
  fi
  if diff -rq "$HERE/src" "$broken/src" > /dev/null 2>&1; then
    echo "CONTROL BROKEN: the $what injection changed nothing"
    missed=$((missed+1)); return
  fi
  if ( cd "$broken" && ./tools/no_direct_clock.sh > "$TMP/$what.log" 2>&1 ); then
    echo "MISSED: the check stayed green with $what"
    missed=$((missed+1))
  else
    echo "caught: $what"
    grep -E "^(DIRECT CLOCK READ|TIME TAKEN FROM THE CALLER|FAILED)" "$TMP/$what.log" | head -3
    caught=$((caught+1))
  fi
}

# 1. a module reading the clock directly - the failure that refused every dated act in the
#    banking tree at f7e28bb
try direct-clock-read sed -i 's|^import Nat "mo:core/Nat";|import Nat "mo:core/Nat";\nimport Time "mo:base/Time";\nlet _t = Time.now();|' src/Query.mo

# 2. a command path taking its time from the caller - erp.mo does this in 46 methods and crm.mo
#    in 19, and it is the defect that lets an invoice be dated whatever the caller likes
try caller-supplied-time sed -i 's|    caller : Principal,|    caller : Principal,\n    nowNs : Int,|' src/Contract.mo

# 3. A SECOND FILE SUPPLYING THE SUBSTRATE CLOCK. This is how the exemption spreads: not by
#    somebody disabling the check, but by a second module acquiring a `Source` of its own and
#    therefore a clock of its own, which is the two-clock defect the check is named for.
try second-substrate-clock sed -i 's|^module {|module {\n  let source = { substrateNow = func() : Nat64 { 0 }; substrateHeight = func() : Nat { 0 }; blockTimestamp = func() : ?Nat64 { null } };|' src/Query.mo

# 4. THE BOUNDARY STOPS BEING THE BOUNDARY. If the file that supplies the record is not an actor,
#    nothing in the tree is entitled to the exemption, and the clock read it still performs is an
#    ordinary module reading an ordinary clock. Without this, pasting a `Source` record anywhere
#    would be a way to write oneself a permit.
try boundary-that-is-not-a-contract sed -i 's|^persistent actor {|module {|' src/Mentat.mo

echo "count: clock faults injected = 4"
echo "count: clock faults the check caught = $caught"
if [ "$missed" -ne 0 ]; then echo "CLOCK CONTROL FAILED: $missed fault(s) passed; the check is not connected"; exit 1; fi
echo "CLOCK CONTROL GREEN"
