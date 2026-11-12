#!/usr/bin/env bash
# THE STABLE-TYPE SIGNATURE IS AN ARTEFACT, NOT A BY-PRODUCT.
#
# Under this platform's persistence model a persistent variable whose TYPE changed is discarded and
# re-initialised on upgrade - silently, with the upgrade reporting success. The deploy tool refuses
# an upgrade it cannot show to be safe, and what it wants is a record of the signature currently
# installed. That record is a property of the SOURCE, so it belongs beside the source, committed,
# and not left to whoever happens to run a deploy.
#
# This regenerates the signature from `src/Mentat.mo` and compares it with the committed
# `src/Mentat.most`. A difference is not a failure of this script: it is a change to the shape of
# everything this contract keeps, and it has to be a deliberate act with the migration thought
# through, which is why it stops the build and prints the diff rather than quietly writing the file.
#
#   --write   accept the new signature (the deliberate act)
#
# Attribution: Thebes Core Team. Licence: Apache 2.0.
set -u
cd "$(dirname "$(readlink -f "$0")")/.."

MOC="${MOC_THEBES:-$HOME/.thebes/toolchain/moc}"
[ -x "$MOC" ] || { echo "stable_signature: no compiler at $MOC"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! "$MOC" --legacy-persistence --stable-types $(./tools/packages.sh) -o "$TMP/sig.wasm" src/Mentat.mo 2> "$TMP/err"; then
  grep -v warning "$TMP/err" | head -10
  echo "stable_signature: the contract does not compile"
  exit 1
fi
[ -f "$TMP/sig.most" ] || { echo "stable_signature: the compiler produced no signature"; exit 1; }

lines=$(grep -c '' "$TMP/sig.most")
if [ "$lines" -lt 10 ]; then
  echo "stable_signature: a signature of $lines lines is not this contract's; refusing to compare"
  exit 1
fi

if [ "${1:-}" = "--write" ]; then
  cp "$TMP/sig.most" src/Mentat.most
  echo "stable_signature: recorded $lines lines"
  exit 0
fi

if [ ! -f src/Mentat.most ]; then
  echo "stable_signature: no committed signature; run with --write once and commit the file"
  exit 1
fi

if ! diff -u src/Mentat.most "$TMP/sig.most" > "$TMP/diff"; then
  head -40 "$TMP/diff"
  echo "count: signature lines committed = $(grep -c '' src/Mentat.most)"
  echo "count: signature lines now = $lines"
  echo "STABLE SIGNATURE CHANGED: the shape of what this contract keeps is not what is recorded."
  echo "  An upgrade across this change discards every persistent variable whose type moved."
  echo "  If it is deliberate, re-run with --write and land the new signature with the migration."
  exit 1
fi

echo "count: stable signature lines = $lines"
echo "STABLE SIGNATURE GREEN"
