#!/usr/bin/env bash
# THE UPGRADE PATH OF THE LAYOUT, CHECKED BY THE COMPILER.
#
# Three upgrades must be compatible, and `moc --stable-compatible` is the judge of each:
#
#   retired -> migrating   the frozen signature of the retired layout (`tools/layouts/*-v1.most`)
#                          upgrades to the actor that carries the migration expression;
#   migrating -> plain     that actor upgrades to the tree's plain actor, which is the next
#                          deployment after the one that migrated;
#   plain -> plain         the plain actor upgrades to itself, which is every ordinary deployment.
#
# A migration written but never checked against the signature it claims to carry is a migration
# that traps at the far end of a deployment. This runs in the gate and takes seconds.
#
#   tools/stable_compat.sh [out-dir]
#
# Attribution: Thebes Core Team. Licence: Apache 2.0.
set -uo pipefail
root="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
out="${1:-$(mktemp -d)}"
MOC="${MOC_THEBES:-$HOME/.thebes/toolchain/moc}"
mkdir -p "$out"
PKGS="$("$root/tools/packages.sh")"
echo "== the plain actor's stable signature"
"$MOC" --legacy-persistence $PKGS --stable-types -o "$out/plain.wasm" "$root/src/Mentat.mo" 2> "$out/plain.log" \
  || { echo "the plain actor does not build"; grep -v warning "$out/plain.log" | head; exit 1; }
echo "== plain -> plain"
fail=0; checked=0
if "$MOC" --stable-compatible "$out/plain.most" "$out/plain.most"; then echo "compatible"; else fail=$((fail+1)); fi
checked=$((checked+1))

# EVERY RETIRED LAYOUT, EACH WITH ITS OWN MIGRATING ACTOR: the retired signature upgrades to the
# actor carrying that layout's migration, that actor upgrades to the plain one, and the retired
# signature is REFUSED a direct upgrade to the plain actor, so the migration carries something.
for retired in "$root"/tools/layouts/mentat-*.most; do
  name="$(basename "$retired" .most)"
  layout="${name#mentat-}"
  "$root/tools/migrating_actor.sh" "$out/migrating-$layout" "$layout" > /dev/null
  MPKGS="$(KERNEL="${KERNEL:-$(cd "$root/../thebes-kernel" && pwd)}" "$out/migrating-$layout/tools/packages.sh")"
  echo "== the migrating actor for $name"
  ( cd "$out/migrating-$layout" && "$MOC" --legacy-persistence $MPKGS --stable-types -o "$out/migrating-$layout.wasm" src/Mentat.mo 2> "$out/migrating-$layout.log" ) \
    || { echo "the migrating actor for $name does not build"; grep -v warning "$out/migrating-$layout.log" | head; exit 1; }
  grep -q '^// Version: 3.0.0' "$out/migrating-$layout.most" || { echo "the migrating actor's signature for $name is not a pre/post signature; the expression was not applied"; exit 1; }
  echo "== $name -> migrating"
  if "$MOC" --stable-compatible "$retired" "$out/migrating-$layout.most"; then echo "compatible"; else fail=$((fail+1)); fi
  checked=$((checked+1))
  echo "== migrating ($name) -> plain"
  if "$MOC" --stable-compatible "$out/migrating-$layout.most" "$out/plain.most"; then echo "compatible"; else fail=$((fail+1)); fi
  checked=$((checked+1))
  echo "== $name -> plain, which must be refused"
  if "$MOC" --stable-compatible "$retired" "$out/plain.most" > /dev/null 2>&1; then
    echo "NOT REFUSED: $name upgrades to the plain actor without its migration, so the migration carries nothing"
    fail=$((fail+1))
  else
    echo "refused, as it must be"
  fi
  checked=$((checked+1))
done
echo "count: retired layouts = $(ls "$root"/tools/layouts/*.most | wc -l)"
echo "count: upgrade paths checked = $checked"
[ "$fail" = 0 ] && echo "STABLE COMPAT GREEN" || { echo "STABLE COMPAT FAILED: $fail path(s)"; exit 1; }
