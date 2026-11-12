#!/usr/bin/env bash
# The ESG sources check's negative control. Each fault is made in a COPY of the published files, of the derivation
# and of the battery - never in the tree - and tools/esg_sources.py must refuse every one. The unbroken copy must
# pass first, so a fault that "fails" because the copy itself is broken counts for nothing.
#
#   hash         one byte of the supply-chain file flipped: it is no longer the file its URL served
#   derivation   a derived figure in factors.json moved by one microgram
#   battery      the battery weighing natural gas by a CO2 figure one microgram off the published one
#   pin          SOURCES.md recording another hash for the hub
#
# Attribution: Thebes Core Team. Licence: Apache 2.0.
set -uo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
caught=0
missed=0

fresh() {
  rm -rf "$TMP/esg" "$TMP/Esg.test.mo"
  cp -r integration/esg "$TMP/esg"
  cp test/Esg.test.mo "$TMP/Esg.test.mo"
}
check() { ESG_DIR="$TMP/esg" ESG_BATTERY="$TMP/Esg.test.mo" python3 tools/esg_sources.py > "$TMP/out.txt" 2>&1; }

# try <name> <what the refusal says>
try() {
  if check; then
    echo "MISSED: $1 - the check passed"; missed=$((missed + 1))
  elif grep -q "$2" "$TMP/out.txt"; then
    echo "caught: $1"; caught=$((caught + 1))
  else
    echo "MISSED: $1 - the check failed, but not for it:"; head -3 "$TMP/out.txt"; missed=$((missed + 1))
  fi
}
# edit <file> <python expression over s> - the expression must change the file
edit() {
  python3 - "$1" "$2" <<'PY'
import sys
p, expr = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
t = eval(expr, {"s": s})
if t == s:
    sys.exit("esg_sources_control: the edit changed nothing: " + expr)
open(p, "w", encoding="utf-8").write(t)
PY
}

fresh
if ! check; then echo "CONTROL BROKEN: the unbroken copy does not pass"; tail -5 "$TMP/out.txt"; exit 1; fi
echo "the unbroken copy passes"

fresh
python3 -c "
import sys; p = sys.argv[1]; b = bytearray(open(p, 'rb').read()); b[len(b) // 2] ^= 1; open(p, 'wb').write(bytes(b))
" "$TMP/esg/SupplyChainGHGEmissionFactors_v1.3.0_NAICS_byGHG_USD2022.csv"
try "a byte of the supply-chain file flipped" "SupplyChainGHGEmissionFactors_v1.3.0_NAICS_byGHG_USD2022.csv: SHA-256"

fresh
edit "$TMP/esg/factors.json" "s.replace('\"micrograms\": 54440000000000', '\"micrograms\": 54440000000001', 1)" || exit 1
try "a derived figure moved by one microgram" "factors.json is not what the files derive"

fresh
edit "$TMP/Esg.test.mo" "s.replace('micrograms = 54_440_000_000_000 }', 'micrograms = 54_440_000_000_001 }', 1)" || exit 1
try "the battery weighing by a figure the file does not publish" "the battery does not weigh by ng CO2"

fresh
edit "$TMP/esg/SOURCES.md" "s.replace('43afb91d79b2ae765b3a447549d9e1021a144a407cec5eb804be9fcf69a668a7 |', '43afb91d79b2ae765b3a447549d9e1021a144a407cec5eb804be9fcf69a668a8 |', 1)" || exit 1
try "SOURCES.md pinning another hash for the hub" "ghg-emission-factors-hub-2025.xlsx: SHA-256"

echo "count: ESG source faults injected = $((caught + missed))"
echo "count: ESG source faults the check caught = $caught"
if [ "$missed" -ne 0 ]; then echo "ESG SOURCES CONTROL FAILED: $missed fault(s) accepted"; exit 1; fi
echo "ESG SOURCES CONTROL GREEN"
