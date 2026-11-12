#!/usr/bin/env bash
# NO CREDENTIAL TRAVELS IN A COMMAND, AND NO OUTBOUND CALL IS REPLICATED.
#
# Both of these are facts about `crm.mo` and `erp.mo` that compile perfectly well and are wrong on
# a running subnet, which is why they are checked by a script and not by a reading.
#
# 1. NO CREDENTIAL IN A COMMAND OR A ROW. `crm.mo:847` declares
#    `sendMailingBatch(..., sendgridApiKey : Text, ...)` as a public method, so the provider key
#    travels in the clear in every ingress message that sends a batch and is visible to every node
#    of the subnet and in every message log; `erp.mo` does the same with an ETA bearer token. A
#    secret belongs in the key ring, read at the edge at the moment of the call. It is not a
#    command's payload - a command is written to the log, and a log is for ever - and it is not a
#    row.
#
# 2. EVERY OUTBOUND REQUEST IS UNREPLICATED. `crm.mo:923` passes `is_replicated = null` to the
#    substrate's `http_request`, which is the REPLICATED default: every validator of the
#    subnet issues the request independently. For a `GET` of a price that is merely paid for
#    once per validator; for a `POST` that SENDS MAIL it means the campaign is delivered once per
#    validator. A request that is not idempotent at the provider must set `is_replicated = ?false`.
#
# 3. AND THERE MUST BE SOMETHING TO CHECK. A checker that runs over no call sites is green for the
#    reason that proves nothing. If the tree declares no outbound request at all, this fails.
#
# Attribution: Thebes Core Team. Licence: Apache 2.0.
set -u
cd "$(dirname "$0")/.."

code_of() { sed -e 's://.*::' -e 's:///.*::' "$1"; }

SECRETS='apiKey|api_key|sendgridApiKey|authToken|bearerToken|accessToken|secretKey|privateKey|password|passphrase|credentials|deviceKey|deviceSecret|sharedSecret|pairingCode'

credentialsInCommands=0
credentialsInRows=0
replicatedSites=0
unreplicatedSites=0
scanned=0

# ── 1. the command and payload surface ──────────────────────────────────────
for f in src/Command.mo src/*Facts.mo; do
  [ -f "$f" ] || continue
  scanned=$((scanned+1))
  if code_of "$f" | grep -qE "\b($SECRETS)\s*:"; then
    echo "CREDENTIAL IN A COMMAND PAYLOAD: $f"
    code_of "$f" | grep -nE "\b($SECRETS)\s*:" | head -3
    credentialsInCommands=$((credentialsInCommands+1))
  fi
done

# ── 2. the rows ─────────────────────────────────────────────────────────────
for f in src/*Rows.mo src/Rows.mo; do
  [ -f "$f" ] || continue
  scanned=$((scanned+1))
  if code_of "$f" | grep -qE "\b($SECRETS)\s*:"; then
    echo "CREDENTIAL IN A ROW: $f"
    code_of "$f" | grep -nE "\b($SECRETS)\s*:" | head -3
    credentialsInRows=$((credentialsInRows+1))
  fi
done

# ── 3. every outbound request ───────────────────────────────────────────────
#
# A `:` is the type declaration and a `=` is a site that decides. Only the sites that decide are
# checked, and every one of them must decide `?false`.
while IFS= read -r f; do
  while IFS= read -r line; do
    value="$(printf '%s' "$line" | sed -e 's/.*is_replicated[[:space:]]*=[[:space:]]*//' -e 's/[;,].*//' -e 's/[[:space:]]*$//')"
    if [ "$value" = "?false" ]; then
      unreplicatedSites=$((unreplicatedSites+1))
    else
      echo "REPLICATED OUTBOUND REQUEST: $f sets is_replicated = $value"
      replicatedSites=$((replicatedSites+1))
    fi
  done < <(code_of "$f" | grep -E 'is_replicated[[:space:]]*=')
done < <(find src -name '*.mo' | sort)

# ── 4. every outbound call on this substrate is at quorum one ────────────────
#
# The requests that reach a host here become the kernel's `Http.Request`s, and the number of
# validators that fetch one is the `quorum` the builder decides. A filing is not idempotent at the
# authority, so exactly one validator makes it: every site that decides a quorum must say 1.
quorumOneSites=0
quorumOtherSites=0
while IFS= read -r f; do
  while IFS= read -r line; do
    q="$(printf '%s' "$line" | sed -e 's/.*quorum[[:space:]]*=[[:space:]]*//' -e 's/[;,].*//' -e 's/[[:space:]]*$//')"
    if [ "$q" = "1" ]; then
      quorumOneSites=$((quorumOneSites+1))
    else
      echo "OUTBOUND CALL NOT AT QUORUM ONE: $f asks for quorum $q"
      quorumOtherSites=$((quorumOtherSites+1))
    fi
  done < <(code_of "$f" | grep -E '[^A-Za-z]quorum[[:space:]]*=[[:space:]]*[0-9]')
done < <(find src -name '*.mo' | sort)
echo "count: command and row files scanned for a credential = $scanned"
echo "count: outbound calls that name a quorum = $((quorumOneSites+quorumOtherSites))"
echo "count: outbound calls at quorum one = $quorumOneSites"
echo "count: outbound requests that set is_replicated = $((unreplicatedSites+replicatedSites))"
echo "count: outbound requests that are unreplicated = $unreplicatedSites"

fail=0
if [ "$credentialsInCommands" -ne 0 ]; then echo "FAILED: $credentialsInCommands command payload file(s) carry a credential"; fail=1; fi
if [ "$credentialsInRows" -ne 0 ]; then echo "FAILED: $credentialsInRows row file(s) carry a credential"; fail=1; fi
if [ "$replicatedSites" -ne 0 ]; then echo "FAILED: $replicatedSites outbound request(s) are replicated"; fail=1; fi
# THE ANTI-VACUITY RULE. Green over nothing is the shape that made this tree's battery control
# count compile failures as catches for five extensions.
if [ "$unreplicatedSites" -eq 0 ]; then echo "FAILED: no outbound request is declared anywhere, so this check proved nothing"; fail=1; fi
if [ "$quorumOtherSites" -ne 0 ]; then echo "FAILED: $quorumOtherSites outbound call(s) are not at quorum one"; fail=1; fi
if [ "$quorumOneSites" -eq 0 ]; then echo "FAILED: no outbound call names a quorum anywhere, so the quorum check proved nothing"; fail=1; fi
[ "$fail" -eq 0 ] || exit 1
echo "OUTCALL AND SECRET SURFACE GREEN"
