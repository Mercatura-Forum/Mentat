#!/usr/bin/env bash
# Emits the --package flags for a build of this tree: the mops dependencies plus the
# Thebes Domain Kernel, which is a checkout rather than a mops package (vendor/thebes-kernel/README.md
# names the commit). The kernel is read from KERNEL when it is set, else from vendor/thebes-kernel when
# the kernel has been placed there, else from a thebes-kernel checkout beside this tree.
# Attribution: Thebes Core Team. Licence: Apache 2.0.
set -u
# THE TREE THIS SCRIPT BELONGS TO, not the directory it was invoked from.
#
# The deploy tool builds in a COPY of the project whose entries are symlinks back here. Resolving
# `$0` relative to the copy put the tree's root at the copy and the kernel nowhere, and the build
# failed with "package core not defined" - a path problem wearing a dependency's clothes.
# `readlink -f` follows the link to the file itself, so this resolves to the checkout in every
# directory it is run from.
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
if [ -z "${KERNEL:-}" ]; then
  if [ -d "$HERE/vendor/thebes-kernel/src/domain" ]; then KERNEL="$HERE/vendor/thebes-kernel"
  else KERNEL="$(cd "$HERE/../thebes-kernel" 2>/dev/null && pwd)"; fi
fi
if [ ! -d "$KERNEL/src/domain" ]; then
  echo "packages.sh: no Thebes kernel at ${KERNEL:-vendor/thebes-kernel or ../thebes-kernel} (vendor/thebes-kernel/README.md names the commit to place there)" >&2
  exit 1
fi
# THE KERNEL IS NAMED BY ITS PHYSICAL PATH. The compiler hashes a package's path into the names of
# the types it declares, so the stable-type signature of this contract depended on how the kernel was
# reached: one checkout naming it through a symlink and another naming the directory the link points
# at built the same kernel, byte for byte, and recorded two different signatures - and the deploy tool
# would refuse an upgrade over a difference that was only spelling. Resolved once, here, every route to the
# same kernel gives the same signature.
KERNEL="$(cd "$KERNEL" && pwd -P)"
# THE MESSAGING HUB, for the payment battery only: the ISO 20022 example's Motoko
# (thebes-example-open-banking-iso20022, public), a sibling checkout whose validator the battery holds
# every pacs.008 to. HUB may point elsewhere. A tree without it builds the contract and fails the
# payment battery, which says so.
if [ -z "${HUB:-}" ]; then
  HUB="$HERE/../thebes-example-open-banking-iso20022"
  [ -d "$HUB/motoko" ] || HUB="$HERE/../thebes-example-iso20022"
fi
[ -d "$HUB/motoko" ] && HUB="$(cd "$HUB" && pwd -P)"
if [ -d "$HUB/motoko" ]; then
  echo "$(cd "$HERE" && mops sources) --package kernel $KERNEL/src --package iso20022hub $HUB/motoko"
else
  echo "$(cd "$HERE" && mops sources) --package kernel $KERNEL/src"
fi
