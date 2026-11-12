#!/usr/bin/env bash
# The gate's cost on one act, pinned.
#
# HOW IT IS MEASURED. `Prim.performanceCounter` does not answer under WASI, so the meter is wasmtime's fuel:
# one unit per instruction, and a module given too little traps. tools/cost/GateCost.mo is compiled four times
# - 1 and 101 rounds of two gate questions, over a company of SMALL and of LARGE members - and for each the
# least fuel it finishes with is found by bisection. The setup is the same in a pair, so the difference over
# 100 rounds is the gate's own cost per round, with the view `State.apply` builds for every act inside it.
#
# THE CLAIMS:
#   per round ≤ CEILING (330,000: the round measured at 240,705 over 2,048 members when the gate landed, and half
#   again), for the small company and for the large one;
#   the large company's round ≤ GROWTH × the small one's: a lookup grows with the depth of an index, a scan
#   with the number of members, and LARGE is SMALL × 64.
#
# Attribution: Thebes Core Team. Licence: Apache 2.0.
set -u
cd "$(dirname "$0")/.."
MOC="${MOC:-$HOME/.cache/mops/moc/1.4.1/moc}"
SOURCES="$(./tools/packages.sh)"
SMALL=32
LARGE=2048
CEILING=${GATE_COST_CEILING:-330000}
GROWTH_PERCENT=200
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/tools/cost"
ln -s "$PWD/src" "$tmp/src"

build() { # calls members -> wasm
  local w="$tmp/cost-$1-$2.wasm"
  sed -e "s/^let CALLS : Nat = 0;/let CALLS : Nat = $1;/" -e "s/^let MEMBERS : Nat = 0;/let MEMBERS : Nat = $2;/" \
    tools/cost/GateCost.mo > "$tmp/tools/cost/GateCost-$1-$2.mo"
  "$MOC" -wasi-system-api $SOURCES -o "$w" "$tmp/tools/cost/GateCost-$1-$2.mo" 2> "$tmp/compile.log" \
    || { cat "$tmp/compile.log" | grep -v warning | head; echo "GATE COST RED: the cost program does not build"; exit 1; }
  echo "$w"
}
# A run either finishes, or traps for want of fuel; anything else - a host that could not start the module's
# threads (tools/wasi_run.sh), a trap of the program itself - is not an answer about fuel, and would skew the
# bisection toward a number nobody measured. A host abort is retried; anything else stops the step.
HOST_REFUSED='failed to spawn thread|Resource temporarily unavailable|ThreadPoolBuildError|fork: retry'
runs() {
  local attempt
  for attempt in 1 2 3 4 5 6; do
    if wasmtime run -W fuel="$2" "$1" > "$tmp/run.log" 2>&1; then return 0; fi
    grep -q 'all fuel consumed' "$tmp/run.log" && return 1
    grep -Eq "$HOST_REFUSED" "$tmp/run.log" || { echo "GATE COST RED: $1 failed for a reason other than fuel:" >&2; head -5 "$tmp/run.log" >&2; exit 2; }
    sleep $((attempt * 5))
  done
  echo "GATE COST: HOST COULD NOT RUN $1" >&2; exit 75
}
least_fuel() { # wasm -> least fuel it finishes with
  local w="$1" hi=1000000 lo=0
  until runs "$w" "$hi"; do lo=$hi; hi=$((hi * 4)); [ "$hi" -gt 400000000000 ] && { echo "GATE COST RED: $w did not finish"; exit 1; }; done
  while [ $((hi - lo)) -gt 1 ]; do
    local mid=$(((lo + hi) / 2))
    if runs "$w" "$mid"; then hi=$mid; else lo=$mid; fi
  done
  echo "$hi"
}
per_round() { # members -> fuel per round
  local one hundred w1 w101
  w1="$(build 1 "$1")" || exit 1; w101="$(build 101 "$1")" || exit 1
  one="$(least_fuel "$w1")" || exit 1; hundred="$(least_fuel "$w101")" || exit 1
  echo $(((hundred - one) / 100))
}
small="$(per_round $SMALL)" || { echo "$small"; exit 1; }
large="$(per_round $LARGE)" || { echo "$large"; exit 1; }
echo "count: fuel per round of two gate questions, $SMALL members = $small"
echo "count: fuel per round of two gate questions, $LARGE members = $large"
red=0
if [ "$CEILING" -gt 0 ]; then
  [ "$small" -le "$CEILING" ] || { echo "GATE COST RED: $small per round over $SMALL members, past the ceiling $CEILING"; red=1; }
  [ "$large" -le "$CEILING" ] || { echo "GATE COST RED: $large per round over $LARGE members, past the ceiling $CEILING"; red=1; }
fi
[ $((large * 100)) -le $((small * GROWTH_PERCENT)) ] || { echo "GATE COST RED: a company of $LARGE members costs $large a round, past ${GROWTH_PERCENT}% of $small: the gate grows with the members"; red=1; }
[ "$red" -eq 0 ] && echo "GATE COST GREEN"
exit "$red"
