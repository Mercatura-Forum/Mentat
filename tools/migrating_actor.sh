#!/usr/bin/env bash
# Writes a copy of this tree whose actor carries the migration expression for one retired layout,
# for the one upgrade that needs it:
#   tools/migrating_actor.sh <dest-dir> <layout>      layout: v1, v2, … (tools/layouts/mentat-<layout>.most)
#
# The actor in the tree has no migration expression. The compiler applies one on EVERY upgrade and
# checks the retired actor's stable signature against its domain, so a tree that kept it could not
# be upgraded to itself. The copy is what a deployment that migrates from the retired layout
# installs; the next deployment installs the plain tree. `tools/stable_compat.sh` proves both steps.
#
# Attribution: Thebes Core Team. Licence: Apache 2.0.
set -euo pipefail
dest="$1"
layout="${2:?which retired layout: v1, v2, …}"
root="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
[ -f "$root/tools/layouts/mentat-$layout.most" ] || { echo "migrating_actor: no retired layout $layout under tools/layouts" >&2; exit 1; }
fn="from$(printf '%s' "$layout" | tr 'v' 'V')"
mkdir -p "$dest"
rsync -a --delete --exclude .git "$root/src" "$root/tools" "$root/mops.toml" "$root/mops.lock" "$root/thebes.toml" "$dest/"
if [ -d "$root/.mops" ]; then rsync -a "$root/.mops" "$dest/"; fi
actor="$dest/src/Mentat.mo"
grep -q '^persistent actor {' "$actor" || { echo "migrating_actor: the actor's header is not where this script expects it" >&2; exit 1; }
grep -q '^import Migration ' "$actor" || sed -i 's|^import St "State";|import St "State";\nimport Migration "Migration";|' "$actor"
sed -i "s|^persistent actor {|(with migration = Migration.$fn)\npersistent actor {|" "$actor"
grep -q "with migration = Migration.$fn" "$actor"
echo "$actor carries the migration expression for layout $layout ($fn)"
