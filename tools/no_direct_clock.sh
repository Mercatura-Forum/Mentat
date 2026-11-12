#!/usr/bin/env bash
# NOTHING IN THIS PRODUCT READS A CLOCK, AND NOTHING TAKES A TIME FROM ITS CALLER.
#
# Two checks, over `src/` and the batteries.
#
# The comparison against the tree this product was ported from is not made here. It belongs with
# the porting inventory, which holds that tree; in this one it could only ever be a count of
# nothing, and a check whose figure can only be zero is not a check.
#
# 1. NO DIRECT CLOCK READ. One module answers every question about time (`src/ClockWiring.mo`,
#    over the kernel's `time/Clock`), and the substrate's readers reach it as a `Source` record the
#    contract supplies at its boundary. The failure this guards is silent: a module that reads the
#    clock directly compiles, passes its own tests, and then refuses every dated act on a substrate
#    whose clock is the block height in seconds - which is exactly what happened to
#    `thebes-banking-core` at `f7e28bb`, where the clock day computed to 0 and a 2026 business date
#    was refused at the first dated act.
#
#    THE BOUNDARY IS THE ONE EXCEPTION, AND IT IS EARNED, NOT NAMED. Somewhere a clock must be
#    read or there is no time at all; that place is the contract, which supplies the `Source`
#    record every other module reads time through. So the exemption is not a filename on a list - 
#    a list is how an exemption spreads, one plausible entry at a time. It is granted to whichever
#    file SUPPLIES THAT RECORD, and only if:
#
#      * exactly one file in `src/` supplies it. Two would be two clocks, and a product with two
#        clocks has the defect this whole check exists to prevent, wearing a second coat.
#      * that file is an actor. A plain module cannot be a substrate boundary, and pasting a
#        `Source` record into one would otherwise be a way to write oneself a permit.
#
#    A module that reads a clock and supplies nothing is the defect. A module that supplies the
#    record and reads the clock is the boundary doing its job.
#
# 2. NO TIME FROM A CALLER. A public method that takes `nowNs`, `nowMs`, `timestamp`, or a `date`
#    or `time` as text is taking the clock from whoever is calling it. The tree this product
#    replaces did exactly that: an attendance punch took the date and the time as text from the
#    person being recorded, beside a clock reading that nothing compared them to.
#
# Comment lines are not code: a module that documents the clock it does not read is doing exactly
# what it should.
#
# Attribution: Thebes Core Team. Licence: Apache 2.0.
set -u
cd "$(dirname "$0")/.."

code_of() { sed -e 's://.*::' -e 's:///.*::' "$1"; }

# ── who, if anyone, is entitled to read a clock ───────────────────────────────
#
# The supplier of the substrate `Source`: the record is RECOGNISED BY ITS FIELDS BEING ASSIGNED
# (`substrateNow =`), not merely named, so `ClockWiring`'s declaration of the type does not make
# `ClockWiring` a supplier of it.

boundary=""
suppliers=0
while IFS= read -r f; do
  if code_of "$f" | grep -qE '\bsubstrateNow[[:space:]]*=' \
  && code_of "$f" | grep -qE '\bsubstrateHeight[[:space:]]*='; then
    suppliers=$((suppliers+1))
    boundary="$f"
    echo "the substrate clock is supplied by: $f"
  fi
done < <(find src -name '*.mo' | sort)

structural=0
if [ "$suppliers" -gt 1 ]; then
  echo "TWO SUBSTRATE CLOCKS: $suppliers files supply the substrate \`Source\`; a product has one clock"
  boundary=""
  structural=1
elif [ "$suppliers" -eq 1 ] && ! grep -qE '^[[:space:]]*persistent actor\b' "$boundary"; then
  echo "NOT A BOUNDARY: $boundary supplies the substrate \`Source\` but is not the contract"
  boundary=""
  structural=1
fi

scanned=0
clockReads=0
callerTimes=0

while IFS= read -r f; do
  scanned=$((scanned+1))
  if code_of "$f" | grep -qE 'mo:base/Time|mo:core/Time|\bTime\.now\b|Prim\.time'; then
    if [ "$f" = "$boundary" ]; then
      echo "the boundary reads the substrate clock, which is what a boundary is for: $f"
    else
      echo "DIRECT CLOCK READ: $f"
      code_of "$f" | grep -nE 'mo:base/Time|mo:core/Time|\bTime\.now\b|Prim\.time'
      clockReads=$((clockReads+1))
    fi
  fi
  if code_of "$f" | grep -qE '\b(nowNs|nowMs|nowSeconds|timestampNs)\s*:'; then
    echo "TIME TAKEN FROM THE CALLER: $f"
    code_of "$f" | grep -nE '\b(nowNs|nowMs|nowSeconds|timestampNs)\s*:'
    callerTimes=$((callerTimes+1))
  fi
done < <(find src test -name '*.mo' | sort)

echo "count: files supplying the substrate clock = $suppliers"
echo "count: re-based source files scanned = $scanned"
echo "count: re-based files free of a direct clock read = $((scanned-clockReads))"
echo "count: re-based files free of a caller-supplied time = $((scanned-callerTimes))"

fail=0
if [ "$clockReads" -ne 0 ]; then echo "FAILED: $clockReads re-based file(s) read a clock directly"; fail=1; fi
if [ "$callerTimes" -ne 0 ]; then echo "FAILED: $callerTimes re-based file(s) take a time from the caller"; fail=1; fi
if [ "$structural" -ne 0 ]; then echo "FAILED: the substrate clock is not supplied by exactly one contract"; fail=1; fi
[ "$fail" -eq 0 ] || exit 1
echo "TIME SURFACE GREEN"
