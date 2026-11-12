#!/usr/bin/env bash
# Runs every test/*.test.mo compiled to WASI under wasmtime. A test passes when it exits 0 and
# prints at least one "count: <what> = <n>" line with no zero count.
#
# A count that can be zero is not a count: a battery that examined nothing and a battery that
# examined everything and found nothing wrong both print "0 failures", and only one of them is a
# test. So the runner refuses a run whose counts are absent or zero.
#
# `test/*.export.mo` is not matched and does not run here. An exporter writes the whole log to
# stdout for the independent reader, which is thousands of lines and is not a test result; it is
# compiled and run by name (the README's building and testing section).
#
# Attribution: Thebes Core Team. Licence: Apache 2.0.
set -u
cd "$(dirname "$0")/.."
MOC="${MOC:-$HOME/.cache/mops/moc/1.4.1/moc}"
SOURCES="$(./tools/packages.sh)"
OUT="${TEST_OUT:-$(mktemp -d)}"
mkdir -p "$OUT"
fail=0; total=0
for t in test/${1:-*}.test.mo; do
  [ -e "$t" ] || continue
  name="$(basename "$t" .test.mo)"; total=$((total+1))
  echo "=== $name"
  if ! $MOC -wasi-system-api $SOURCES -o "$OUT/$name.wasm" "$t" 2> "$OUT/$name.compile.log"; then
    echo "COMPILE FAILED: $name"; grep -v "warning" "$OUT/$name.compile.log" | head -12; fail=$((fail+1)); continue
  fi
  # A HOST THAT COULD NOT RUN THE BATTERY IS NOT A BATTERY THAT FAILED (tools/wasi_run.sh): it is
  # red here all the same, but under its own name, so a negative control can tell it from a catch.
  ./tools/wasi_run.sh "$OUT/$name.wasm" "$OUT/$name.log"
  rc=$?
  if [ "$rc" -eq 75 ]; then
    echo "HOST COULD NOT RUN: $name"; tail -3 "$OUT/$name.log"; fail=$((fail+1)); continue
  elif [ "$rc" -ne 0 ]; then
    echo "FAILED: $name"; tail -20 "$OUT/$name.log"; fail=$((fail+1)); continue
  fi
  grep -E '^(count:|FAIL|[A-Z0-9 ]+ GREEN)' "$OUT/$name.log"
  if ! grep -Eq '^count: [^=]+ = [1-9][0-9]*$' "$OUT/$name.log"; then echo "FAILED: $name printed no count line"; fail=$((fail+1)); continue; fi
  if grep -Eq '^count: [^=]+ = 0$' "$OUT/$name.log"; then echo "FAILED: $name examined zero records"; fail=$((fail+1)); continue; fi
done
# A RUN THAT MATCHED NO TEST IS NOT A PASS.
#
# `./test/run.sh Payroll` in a tree where `Payroll.test.mo` is absent used to print "tests: 0,
# failed: 0" and exit 0. The battery's own control found it: seven injected faults were reported as
# MISSED because the copy the control built did not contain the new test file at all, so the battery
# "stayed green" over nothing. A run with no tests in it says nothing about the code, and saying
# nothing must not look like saying yes.
if [ "$total" -eq 0 ]; then
  echo "FAILED: no test matched ${1:-*}"
  exit 1
fi
echo "tests: $total, failed: $fail  (logs in $OUT)"
[ "$fail" -eq 0 ]
