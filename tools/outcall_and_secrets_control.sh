#!/usr/bin/env bash
# The outcall-and-secret check's negative control.
#
# One injection per class the checker claims to catch - a credential in a command, a credential in
# a row, the replicated default, an explicitly replicated request, and the same in the SECOND
# outbound builder - plus the one that matters most: the check going green because there is nothing
# left to check. That last class is here because this
# tree has already had a control that counted compile failures as catches for five extensions.
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
  if ( cd "$broken" && ./tools/outcall_and_secrets.sh > "$TMP/$what.log" 2>&1 ); then
    echo "MISSED: the check stayed green with $what"
    missed=$((missed+1))
  else
    echo "caught: $what"
    grep -E "^(CREDENTIAL IN|REPLICATED OUTBOUND|FAILED)" "$TMP/$what.log" | head -3
    caught=$((caught+1))
  fi
}

# 1. the received defect exactly: the provider key as a field of the command that sends
try credential-in-command \
  sed -i 's|^    mailingId : Nat;$|    mailingId : Nat;\n    sendgridApiKey : Text;|' src/CrmFacts.mo

# 2. the same secret stored in a row, where the log keeps it for ever
try credential-in-row \
  sed -i 's|^    attemptBound : Nat;$|    attemptBound : Nat;\n    apiKey : Blob;|' src/CrmRows.mo

# 3. THE DEVICE CREDENTIAL, PUT BACK ON THE COMMAND. `ingestDevicePunches(companyId, deviceKey :
#    Text, punches)` (`main.mo:5861`) is the received shape, and the landed ingest carries a
#    signature instead. A checker whose field-name list did not cover `deviceKey` would have passed
#    the received method verbatim.
try device-key-in-command \
  sed -i 's|^    counter : Nat;$|    counter : Nat;\n    deviceKey : Text;|' src/AttFacts.mo

# 4. AND STORED IN THE DEVICE'"'"'S ROW, where `registerAttendanceDevice` put it.
try device-key-in-row \
  sed -i 's|^    lastCounter : Nat;$|    lastCounter : Nat;\n    sharedSecret : Blob;|' src/AttRows.mo

# 5. the replicated default - the flag `crm.mo:923` and `erp.mo:1182` actually pass
try replicated-outcall \
  sed -i 's|      is_replicated = ?false;|      is_replicated = null;|' src/MailRequest.mo

# 6. explicitly replicated, which is worse because it reads as deliberate
try explicitly-replicated \
  sed -i 's|      is_replicated = ?false;|      is_replicated = ?true;|' src/MailRequest.mo

# 7. THE SECOND PATH. Two outbound paths exist - the mailing, still in the substrate's
#    shape, and the tax-authority filing through the substrate's own outcall - and a control that
#    only ever broke the first would have said nothing about the second. The filing's rule is a
#    quorum of one; here the login asks the validators to log in.
try quorum-raised-in-the-filing \
  sed -i '0,/      quorum = 1;/s|      quorum = 1;|      quorum = 4;|' src/EtaSubmit.mo

# 7b. and the submission itself, so a control that only broke the login says something about the
#     request that files.
try quorum-raised-in-the-submission \
  sed -i -z 's|      quorum = 1;|      quorum = 2;|2' src/EtaSubmit.mo

# 8. NOTHING LEFT TO CHECK. EVERY builder is deleted, so every check above passes over an empty
#    set. A checker that reports green here is a checker that would have reported green all along.
#
#    This injection used to delete one builder, and the gate caught it when a second one landed:
#    the check stayed green because the other builder was still there, which is the right answer
#    to the wrong question. An anti-vacuity control has to empty the set, not thin it.
try nothing-to-check \
  sh -c 'rm -f src/MailRequest.mo src/EtaSubmit.mo && grep -rl "MailRequest\|EtaSubmit\|quorum = " src test --include=*.mo | xargs -r sed -i "/MailRequest\|EtaSubmit\|quorum = /d"'

echo "count: outcall and secret faults injected = $((caught+missed))"
echo "count: outcall and secret faults the check caught = $caught"
if [ "$missed" -ne 0 ]; then echo "OUTCALL CONTROL FAILED: $missed fault(s) passed; the check is not connected"; exit 1; fi
echo "OUTCALL CONTROL GREEN"
