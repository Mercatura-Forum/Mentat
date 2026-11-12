#!/usr/bin/env bash
# The gate's two tables held to the command type, and its own control.
#
#   1. THE ROUTE IS TOTAL. `Gate.route` has one arm per command family, and a switch that misses a case is
#      only a warning to the compiler; here it is compiled with that warning an error (`-E M0145`), so a family
#      added without saying where its company comes from does not get past this step.
#   2. THE CONTROL: the same compile over a copy of the tree with one arm removed must be refused, or the
#      lint above proves nothing.
#   3. THE SAMPLES ARE CURRENT: test/IsolationSamples.mo is what tools/isolation_samples.py writes from the
#      command type as it stands, so the isolation battery probes every family there is.
#
# Attribution: Thebes Core Team. Licence: Apache 2.0.
set -u
cd "$(dirname "$0")/.."
MOC="${MOC:-$HOME/.cache/mops/moc/1.4.1/moc}"
SOURCES="$(./tools/packages.sh)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

if ! "$MOC" --check -E M0145 $SOURCES src/Gate.mo > "$tmp/lint.log" 2>&1; then
  grep -A4 'M0145\|error' "$tmp/lint.log" | head -20
  echo "GATE LINT RED: the gate's route does not cover every command family"; exit 1
fi
echo "count: route arms compiled with a missed family an error = $(grep -cE '^      case \(#[A-Za-z]+[^)]*\) (co|about|of)\(' src/Gate.mo)"

cp -r src "$tmp/src"
python3 - "$tmp/src/Gate.mo" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
arms = re.findall(r'^      case \(#withdrawBomChange [^\n]*\n', s, re.M)
assert len(arms) == 1, 'the control could not find the one arm it removes'
open(p, 'w').write(s.replace(arms[0], ''))
PY
if "$MOC" --check -E M0145 $SOURCES "$tmp/src/Gate.mo" > "$tmp/control.log" 2>&1; then
  echo "GATE LINT CONTROL BROKEN: a route with a family removed compiled"; exit 1
fi
grep -q 'M0145' "$tmp/control.log" || { echo "GATE LINT CONTROL BROKEN: the copy was refused, but not for the missed family"; exit 1; }
echo "caught: a route with one family removed refused by the compiler"

python3 tools/isolation_samples.py --check || exit 1
echo "GATE LINT GREEN"
