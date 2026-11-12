#!/usr/bin/env bash
# Every check of this tree that needs no chain, in one run. Each check that could be green by accident
# carries a control that breaks it on purpose and requires it to go red.
#
#   the battery              test/run.sh: every scenario, with an upgrade inside it
#   the battery's control    each rule the domain claims, removed on purpose
#   the filing and signing   the e-invoice seals and the signature flow, verified again in Python
#   the layout's upgrade     every retired layout upgraded to this one (tools/stable_compat.sh)
#   the log export           the log, on stdout, in full
#   the independent oracle   the store rebuilt from those bytes by code that shares nothing with it
#   the oracle's control     corruptions of the log, each refused
#   the time surface         nothing reads a clock and nothing takes a time from its caller
#   the tombstone walk, the record kinds, the read surface, the ESG sources, the company-authority gate
#   the outcall and secret   no credential in a command or a row; every outbound call unreplicated
#   the advantages' control  each advantage test/Usp.test.mo asserts, broken on purpose
#   the compile bound        no function in the contract's module past what a validator compiles
#   the published interface  docs/landed/mentat.did is the contract's Candid
#
# Usage: tools/check.sh [--quick]     --quick: every check but the controls
#
# Attribution: Thebes Core Team. Licence: Apache 2.0.
set -u
cd "$(dirname "$0")/.."

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

OUT="${CHECK_OUT:-$(mktemp -d)}"
mkdir -p "$OUT"
MOC="${MOC:-$HOME/.cache/mops/moc/1.4.1/moc}"

fail=0
step() { echo; echo "── $1 ──────────────────────────────────────────────"; }
red()  { echo "CHECK: $1"; fail=$((fail+1)); }

# ── 1 & 2. the battery ───────────────────────────────────────────────────────
step "the battery"
if TEST_OUT="$OUT/battery" ./test/run.sh > "$OUT/battery.log" 2>&1; then
  grep -E '^(count:|=== |[A-Z ]+GREEN)' "$OUT/battery.log"
else
  cat "$OUT/battery.log"
  red "the battery is red"
fi

if [ "$QUICK" -eq 0 ]; then
  step "the battery's control"
  if ./tools/battery_control.sh > "$OUT/battery_control.log" 2>&1; then
    grep -E '^(count:|caught:|BATTERY CONTROL GREEN)' "$OUT/battery_control.log"
  else
    cat "$OUT/battery_control.log"; red "the battery did not notice a rule being removed"
  fi
fi

# ── the filing oracle ──────────────────────────────────────────────────────────
#
# The tax authority's document, re-derived: the Python twin serialises the submission bodies the
# filing battery printed by the authority's own rule (held first to the authority's published
# example), requires its digests to be the contract's, hands each seal to OpenSSL with the canonical
# bytes and the anchor, and requires OpenSSL to accept it and to refuse it once perturbed.
step "the filing oracle"
if [ ! -s "$OUT/battery/Eta.log" ]; then
  red "the filing battery left no log, so nothing independent checked the documents"
elif python3 integration/oracle/eta.py "$OUT/battery/Eta.log" test/fixtures/eta/root-cert.pem > "$OUT/eta_oracle.log" 2>&1; then
  grep -E '^(PASS|count:|ETA ORACLE GREEN)' "$OUT/eta_oracle.log"
else
  cat "$OUT/eta_oracle.log"; red "the twin or OpenSSL disagrees with the filing"
fi

# ── the signing oracle ─────────────────────────────────────────────────────────
#
# The signing battery prints its log; the Python twin decodes every block with the enterprise
# reader's envelope, folds the signing rules, verifies every ES256 assertion with a P-256
# implementation this tree did not write over the challenge it recomputed, and recomputes both
# seals from the content and the signatures in order - and is shown to refuse a tampered signature.
step "the signing oracle"
if [ ! -s "$OUT/battery/Sign.log" ]; then
  red "the signing battery left no log, so nothing independent checked a signature"
elif python3 integration/oracle/sign.py "$OUT/battery/Sign.log" > "$OUT/sign_oracle.log" 2>&1; then
  grep -E '^(PASS|count:|SIGN ORACLE GREEN)' "$OUT/sign_oracle.log"
else
  cat "$OUT/sign_oracle.log"; red "the twin disagrees with the contract on a signature or a seal"
fi

# ── the layout's upgrade path ─────────────────────────────────────────────────
#
# The shape of what the contract keeps has changed with each extension that added a table, and the
# migration that carries each retired layout forward is checked here by the compiler: retired -> migrating -> plain
# -> plain compatible, and retired -> plain REFUSED, so the migration is load-bearing.
step "the layout's upgrade path"
if ./tools/stable_compat.sh "$OUT/compat" > "$OUT/compat.log" 2>&1; then
  grep -E '^(count:|STABLE COMPAT GREEN)' "$OUT/compat.log"
else
  cat "$OUT/compat.log"; red "a retired layout does not upgrade through the migration"
fi

# ── the camt.053 fixtures ─────────────────────────────────────────────────────
#
# The batteries carry the fixture files as a generated Motoko module; the two must agree, or the
# battery proves something about bytes nobody can read in a file.
step "the camt.053 fixtures"
if python3 tools/camt_fixtures.py --check > "$OUT/camt_fixtures.log" 2>&1; then
  grep -E '^count:' "$OUT/camt_fixtures.log"
else
  cat "$OUT/camt_fixtures.log"; red "test/Camt053Fixtures.mo is not what test/fixtures/camt053/ says"
fi

# ── 3. the log export ────────────────────────────────────────────────────────
step "the log export"
# the two samples of every family the export prints are the ones tools/codec_samples.py writes from the command type
if CODEC_SAMPLES="$(python3 tools/codec_samples.py --check)"; then
  echo "$CODEC_SAMPLES"
  FAMILIES="$(echo "$CODEC_SAMPLES" | grep -oE '[0-9]+ families' | grep -oE '[0-9]+')"
else
  echo "$CODEC_SAMPLES"; red "the codec samples are not the ones the command type gives"; FAMILIES=0
fi
# the command type published as data, which a client's forms and encoder are generated from (tools/command_schema.py)
if COMMAND_SCHEMA="$(python3 tools/command_schema.py)"; then
  echo "$COMMAND_SCHEMA"
else
  echo "$COMMAND_SCHEMA"; red "docs/landed/commands.json is not what the command type gives"
fi
if $MOC -wasi-system-api $(./tools/packages.sh) -o "$OUT/Export.wasm" test/Export.export.mo 2> "$OUT/export.compile.log"; then
  if ./tools/wasi_run.sh "$OUT/Export.wasm" "$OUT/export.txt"; then
    echo "exported $(grep -c '^block: ' "$OUT/export.txt") block(s)"
    grep -E '^count:' "$OUT/export.txt"
  else
    tail -10 "$OUT/export.txt"; red "the export did not run"
  fi
else
  grep -v warning "$OUT/export.compile.log" | head -10; red "the export did not compile"
fi

# ── 4. the independent oracle ────────────────────────────────────────────────
step "the independent oracle"
# The figures the CONTRACT reported. The oracle is given them and must arrive at the same ones
# from the log's bytes alone - printing two numbers side by side and leaving a reader to compare
# them is not a check.
count_of() { grep -oE "^count: $1 = [0-9]+" "$OUT/export.txt" 2>/dev/null | grep -oE '[0-9]+$' | head -1; }
EXPECTED="$(count_of 'companies on the log')"; EXPECTED="${EXPECTED:-0}"
BALANCES="$(count_of 'hr leave balances in the store')"; BALANCES="${BALANCES:-0}"
PUNCHES="$(count_of 'hr punches in the store')"; PUNCHES="${PUNCHES:-0}"
SLIPS="$(count_of 'payslip figures printed')"; SLIPS="${SLIPS:-0}"
QUANTS="$(count_of 'stock quants in the store')"; QUANTS="${QUANTS:-0}"
MOVES="$(count_of 'moves in the store')"; MOVES="${MOVES:-0}"
CAMPAIGNS="$(count_of 'campaigns in the store')"; CAMPAIGNS="${CAMPAIGNS:-0}"
CLOSES="$(count_of 'close runs in the store')"; CLOSES="${CLOSES:-0}"
STATEMENTS="$(count_of 'statements in the store')"; STATEMENTS="${STATEMENTS:-0}"
DEFERRALS="$(count_of 'deferrals in the store')"; DEFERRALS="${DEFERRALS:-0}"
REVALUATIONS="$(count_of 'revaluations in the store')"; REVALUATIONS="${REVALUATIONS:-0}"
ASSETS="$(count_of 'assets in the store')"; ASSETS="${ASSETS:-0}"
CLAIMS="$(count_of 'claims in the store')"; CLAIMS="${CLAIMS:-0}"
PAYMENTS="$(count_of 'payments in the store')"; PAYMENTS="${PAYMENTS:-0}"
CAMT="$(count_of 'statements from camt.053 in the store')"; CAMT="${CAMT:-0}"
ITEMS="$(count_of 'open items in the store')"; ITEMS="${ITEMS:-0}"
CONSOLIDATIONS="$(count_of 'consolidations in the store')"; CONSOLIDATIONS="${CONSOLIDATIONS:-0}"
WORKORDERS="$(count_of 'work orders in the store')"; WORKORDERS="${WORKORDERS:-0}"
QCHECKS="$(count_of 'quality checks in the store')"; QCHECKS="${QCHECKS:-0}"
TICKETS="$(count_of 'tickets in the store')"; TICKETS="${TICKETS:-0}"
VISITS="$(count_of 'visits in the store')"; VISITS="${VISITS:-0}"
BOOKINGS="$(count_of 'bookings in the store')"; BOOKINGS="${BOOKINGS:-0}"
SUBINV="$(count_of 'subscription invoices in the store')"; SUBINV="${SUBINV:-0}"
RENTALS="$(count_of 'rentals in the store')"; RENTALS="${RENTALS:-0}"
TILLS="$(count_of 'till sessions in the store')"; TILLS="${TILLS:-0}"
TABS="$(count_of 'tabs in the store')"; TABS="${TABS:-0}"
WEBS="$(count_of 'web orders in the store')"; WEBS="${WEBS:-0}"
PAGES="$(count_of 'pages in the store')"; PAGES="${PAGES:-0}"
POSTS="$(count_of 'posts in the store')"; POSTS="${POSTS:-0}"
TOPICS="$(count_of 'forum topics in the store')"; TOPICS="${TOPICS:-0}"
CONVERSATIONS="$(count_of 'chat conversations in the store')"; CONVERSATIONS="${CONVERSATIONS:-0}"
WORKFLOWS="$(count_of 'workflows in the store')"; WORKFLOWS="${WORKFLOWS:-0}"
TEXTM="$(count_of 'text mailings in the store')"; TEXTM="${TEXTM:-0}"
SOCIALP="$(count_of 'social posts in the store')"; SOCIALP="${SOCIALP:-0}"
EVENTS="$(count_of 'events in the store')"; EVENTS="${EVENTS:-0}"
SURVEYS="$(count_of 'surveys in the store')"; SURVEYS="${SURVEYS:-0}"
CYCLES="$(count_of 'review cycles in the store')"; CYCLES="${CYCLES:-0}"
COURSES="$(count_of 'courses in the store')"; COURSES="${COURSES:-0}"
BANDS="$(count_of 'pay bands in the store')"; BANDS="${BANDS:-0}"
VEHICLES="$(count_of 'vehicles in the store')"; VEHICLES="${VEHICLES:-0}"
NOTIFICATIONS="$(count_of 'announcement notifications in the store')"; NOTIFICATIONS="${NOTIFICATIONS:-0}"
KB_ARTICLES="$(count_of 'knowledge articles in the store')"; KB_ARTICLES="${KB_ARTICLES:-0}"
GOV_POLICIES="$(count_of 'governance policies in the store')"; GOV_POLICIES="${GOV_POLICIES:-0}"
WF_REQUESTS="$(count_of 'approval requests in the store')"; WF_REQUESTS="${WF_REQUESTS:-0}"
STUDIO_FIELDS="$(count_of 'studio fields in the store')"; STUDIO_FIELDS="${STUDIO_FIELDS:-0}"
if [ "$EXPECTED" -eq 0 ] || [ "$BALANCES" -eq 0 ] || [ "$PUNCHES" -eq 0 ] || [ "$SLIPS" -eq 0 ] || [ "$QUANTS" -eq 0 ] || [ "$CAMPAIGNS" -eq 0 ] || [ "$CLOSES" -eq 0 ] || [ "$STATEMENTS" -eq 0 ] || [ "$DEFERRALS" -eq 0 ] || [ "$REVALUATIONS" -eq 0 ] || [ "$ASSETS" -eq 0 ] || [ "$CLAIMS" -eq 0 ] || [ "$PAYMENTS" -eq 0 ] || [ "$CAMT" -eq 0 ] || [ "$ITEMS" -eq 0 ] || [ "$CONSOLIDATIONS" -eq 0 ] || [ "$WORKORDERS" -eq 0 ] || [ "$QCHECKS" -eq 0 ] || [ "$TICKETS" -eq 0 ] || [ "$VISITS" -eq 0 ] || [ "$BOOKINGS" -eq 0 ] || [ "$SUBINV" -eq 0 ] || [ "$RENTALS" -eq 0 ] || [ "$TILLS" -eq 0 ] || [ "$TABS" -eq 0 ] || [ "$WEBS" -eq 0 ] || [ "$PAGES" -eq 0 ] || [ "$POSTS" -eq 0 ] || [ "$TOPICS" -eq 0 ] || [ "$CONVERSATIONS" -eq 0 ] || [ "$WORKFLOWS" -eq 0 ] || [ "$TEXTM" -eq 0 ] || [ "$SOCIALP" -eq 0 ] || [ "$EVENTS" -eq 0 ] || [ "$SURVEYS" -eq 0 ] || [ "$CYCLES" -eq 0 ] || [ "$COURSES" -eq 0 ] || [ "$BANDS" -eq 0 ] || [ "$VEHICLES" -eq 0 ] || [ "$NOTIFICATIONS" -eq 0 ] || [ "$KB_ARTICLES" -eq 0 ] || [ "$GOV_POLICIES" -eq 0 ] || [ "$WF_REQUESTS" -eq 0 ] || [ "$STUDIO_FIELDS" -eq 0 ]; then
  red "the export reported a zero count, so the oracle has nothing to check"
elif python3 integration/oracle/log_reader.py "$OUT/export.txt" \
       --expect-companies "$EXPECTED" --expect-balances "$BALANCES" --expect-punches "$PUNCHES" \
       --expect-payslips "$SLIPS" --expect-quants "$QUANTS" --expect-moves "$MOVES" --expect-campaigns "$CAMPAIGNS" \
       --expect-closes "$CLOSES" --expect-statements "$STATEMENTS" --expect-deferrals "$DEFERRALS" --expect-revaluations "$REVALUATIONS" --expect-assets "$ASSETS" --expect-claims "$CLAIMS" --expect-payments "$PAYMENTS" --expect-camt "$CAMT" --expect-items "$ITEMS" --expect-consolidations "$CONSOLIDATIONS" --expect-work-orders "$WORKORDERS" --expect-quality-checks "$QCHECKS" --expect-tickets "$TICKETS" --expect-visits "$VISITS" --expect-bookings "$BOOKINGS" --expect-subscription-invoices "$SUBINV" --expect-rentals "$RENTALS" --expect-till-sessions "$TILLS" --expect-tabs "$TABS" --expect-web-orders "$WEBS" --expect-pages "$PAGES" --expect-posts "$POSTS" --expect-topics "$TOPICS" --expect-conversations "$CONVERSATIONS" --expect-workflows "$WORKFLOWS" --expect-text-mailings "$TEXTM" --expect-social-posts "$SOCIALP" --expect-events "$EVENTS" --expect-surveys "$SURVEYS" --expect-review-cycles "$CYCLES" --expect-courses "$COURSES" --expect-pay-bands "$BANDS" --expect-vehicles "$VEHICLES" --expect-notifications "$NOTIFICATIONS" --expect-kb-articles "$KB_ARTICLES" --expect-gov-policies "$GOV_POLICIES" --expect-wf-requests "$WF_REQUESTS" --expect-studio-fields "$STUDIO_FIELDS" \
       > "$OUT/oracle.log" 2>&1; then
  grep -E '^(count:|ORACLE GREEN)' "$OUT/oracle.log"
  # every block's sender held to the reader's own holders table, every company's founder admitted by it, the operator named
  # A BLOCK IS NOT A LINE: the export prints a block's bytes 256 hex characters to a line, so a block of more than 128
  # bytes is several `block:` lines under one index. The blocks are the distinct indices, and they must be the number
  # the export itself counted - two counts of the same thing, made two ways.
  EXPORTED_BLOCKS="$(grep '^block: ' "$OUT/export.txt" | awk '{print $2}' | sort -u | wc -l)"
  if ! grep -Eq "^count: blocks exported = $EXPORTED_BLOCKS\$" "$OUT/export.txt"; then red "the export's blocks are not the blocks it counted"; fi
  if ! grep -Eq "^count: blocks whose sender the reader held to its own holders table = $EXPORTED_BLOCKS\$" "$OUT/oracle.log"; then red "the oracle did not hold every block's sender to its holders table"; fi
  if ! grep -Eq "^count: founders the reader admitted as administrator at their company's bootstrap = $EXPECTED\$" "$OUT/oracle.log"; then red "the oracle did not admit every company's founder"; fi
  if ! grep -Eq '^count: platform operators the log names = 1$' "$OUT/oracle.log"; then red "the oracle found no platform operator on the log"; fi
  # every family read back from the contract's own bytes by its declared type, both samples, and every block written
  # back by its declared type - a count short of either is a family or a block the reader did not hold
  if ! grep -Eq "^count: families the reader holds to their declared type = $FAMILIES\$" "$OUT/oracle.log"; then red "the oracle does not hold every family to its declared type"; fi
  if ! grep -Eq "^count: plain samples read back byte for byte and value for value = $FAMILIES\$" "$OUT/oracle.log"; then red "the oracle did not read back every family's plain sample"; fi
  if ! grep -Eq "^count: rich samples read back byte for byte and value for value = $FAMILIES\$" "$OUT/oracle.log"; then red "the oracle did not read back every family's rich sample"; fi
  if ! grep -Eq "^count: blocks written back by their declared type = $EXPORTED_BLOCKS\$" "$OUT/oracle.log"; then red "the oracle did not write every block back by its declared type"; fi
  # the audit index: the reader wrote one entry under the caller and one under the company for every block, and held
  # the contract's two tables to them both ways - a comparison over fewer entries than that is not the comparison
  if ! grep -Eq "^count: audit entries the reader wrote under their caller = $EXPORTED_BLOCKS\$" "$OUT/oracle.log"; then red "the oracle did not index every block under its caller"; fi
  if ! grep -Eq "^count: audit entries the reader wrote under their company = $EXPORTED_BLOCKS\$" "$OUT/oracle.log"; then red "the oracle did not index every block under its company"; fi
  if ! grep -Eq "^count: audit entries compared both ways = $((EXPORTED_BLOCKS * 2))\$" "$OUT/oracle.log"; then red "the oracle did not compare both audit tables entry by entry"; fi
  # the stock comparison over an empty set is not a comparison
  if ! grep -Eq '^count: quants compared = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no quant"; fi
  # and the campaign comparison over nothing is not a comparison either
  if ! grep -Eq '^count: campaigns compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no campaign"; fi
  # the close over nothing is not a close, and its property must have been checked over accounts
  if ! grep -Eq '^count: closes compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no close"; fi
  if ! grep -Eq '^count: accounts the close swept to zero, by the reader = [1-9]' "$OUT/oracle.log"; then red "the oracle checked no swept account"; fi
  # every statement compared and anchored to the block before its own
  if ! grep -Eq '^count: statements compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no statement"; fi
  if ! grep -Eq '^count: statements anchored to the block before theirs = [1-9]' "$OUT/oracle.log"; then red "the oracle anchored no statement"; fi
  # every deferral's parts recomputed to the minor unit
  if ! grep -Eq '^count: deferral parts compared to the minor unit = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no deferral part"; fi
  if ! grep -Eq '^count: revaluations compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no revaluation"; fi
  if ! grep -Eq '^count: depreciation charges compared to the minor unit = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no depreciation charge"; fi
  if ! grep -Eq '^count: claim lines repriced to the minor unit = [1-9]' "$OUT/oracle.log"; then red "the oracle repriced no claim line"; fi
  if ! grep -Eq '^count: pacs.008 messages rebuilt under the same fingerprint = [1-9]' "$OUT/oracle.log"; then red "the oracle rebuilt no payment message"; fi
  if ! grep -Eq '^count: camt.053 lines compared to the minor unit = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no statement line from a camt.053"; fi
  if ! grep -Eq '^count: camt.053 messages that are their fixture file byte for byte = [1-9]' "$OUT/oracle.log"; then red "the oracle found no camt.053 that is its fixture file"; fi
  if ! grep -Eq '^count: open items compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no open item"; fi
  if ! grep -Eq '^count: interest charges recomputed to the minor unit = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no interest charge"; fi
  # every consolidation refolded from the member statements it names and the members' moves, the eliminations recomputed
  if ! grep -Eq '^count: consolidations compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no consolidation"; fi
  if ! grep -Eq '^count: elimination entries recomputed to the minor unit = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no elimination entry"; fi
  if ! grep -Eq '^count: consolidations anchored to the block before theirs = [1-9]' "$OUT/oracle.log"; then red "the oracle anchored no consolidation"; fi
  # every work order compared, and the parts a sign-off consumed refolded through the reader's own stock fold
  if ! grep -Eq '^count: work orders compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no work order"; fi
  if ! grep -Eq "^count: parts pickings refolded through the reader's stock fold = [1-9]" "$OUT/oracle.log"; then red "the oracle refolded no parts picking"; fi
  # every check and every non-conformance compared, the scrapped delivery refolded through the reader's stock fold, the production's pickings too
  if ! grep -Eq '^count: quality checks compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no quality check"; fi
  if ! grep -Eq '^count: non-conformances compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no non-conformance"; fi
  if ! grep -Eq "^count: scrap pickings refolded through the reader's stock fold = [1-9]" "$OUT/oracle.log"; then red "the oracle refolded no scrap picking"; fi
  if ! grep -Eq "^count: productions whose pickings the reader refolded through its stock fold = [1-9]" "$OUT/oracle.log"; then red "the oracle refolded no production"; fi
  # every ticket compared, its two clocks walked again over the company's calendar, the escalations re-derived by the reader's own sweep
  if ! grep -Eq '^count: tickets compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no ticket"; fi
  if ! grep -Eq '^count: service-level clocks recomputed by the calendar = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no service-level clock"; fi
  if ! grep -Eq '^count: escalations the reader re-derived by running the sweep = [1-9]' "$OUT/oracle.log"; then red "the oracle re-derived no escalation"; fi
  # every visit compared, its labour summed again from the task's approved time, its invoice recomputed from the order the reader placed itself
  if ! grep -Eq '^count: visits compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no visit"; fi
  if ! grep -Eq '^count: labour minutes recomputed from the timesheet = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no labour from a timesheet"; fi
  if ! grep -Eq '^count: visit invoices recomputed to the minor unit = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no visit invoice"; fi
  # every booking compared, and every slot checked again against the ones that held the day
  if ! grep -Eq '^count: bookings compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no booking"; fi
  if ! grep -Eq "^count: slots checked again against the day's bookings = [1-9]" "$OUT/oracle.log"; then red "the oracle checked no slot"; fi
  # every subscription invoice compared to the minor unit, the proration recomputed over the calendar's days
  if ! grep -Eq '^count: subscription invoices compared to the minor unit = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no subscription invoice"; fi
  if ! grep -Eq "^count: prorations recomputed over the calendar's days = [1-9]" "$OUT/oracle.log"; then red "the oracle recomputed no proration"; fi
  # every rental compared, its late days and its charge recomputed by the rule
  if ! grep -Eq '^count: rentals compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no rental"; fi
  if ! grep -Eq '^count: rental charges recomputed to the minor unit = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no rental charge"; fi
  # every till session compared, its totals recomputed from the sales the reader folded
  if ! grep -Eq '^count: till sessions compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no till session"; fi
  if ! grep -Eq "^count: till sessions' totals recomputed from their sales = [1-9]" "$OUT/oracle.log"; then red "the oracle recomputed no till session's totals"; fi
  # every tab compared, every share of a split bill recomputed by the rule
  if ! grep -Eq '^count: tabs compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no tab"; fi
  if ! grep -Eq '^count: bill shares recomputed by the rule = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no bill share"; fi
  # every web order compared, every payment held to its order's total
  if ! grep -Eq '^count: web orders compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no web order"; fi
  if ! grep -Eq "^count: web payments held to their orders' totals = [1-9]" "$OUT/oracle.log"; then red "the oracle held no web payment to its order"; fi
  # every page compared, every version's fingerprint recomputed from the chunks on the log
  if ! grep -Eq '^count: pages compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no page"; fi
  if ! grep -Eq '^count: page fingerprints recomputed from the chunks on the log = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no page fingerprint"; fi
  # every post compared, its day held to the block's
  if ! grep -Eq '^count: posts compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no post"; fi
  if ! grep -Eq '^count: post dates held to the day of their block = [1-9]' "$OUT/oracle.log"; then red "the oracle held no post to its day"; fi
  # every forum topic compared, its replies recounted from the log, every moderation a second person's
  if ! grep -Eq '^count: topics compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no topic"; fi
  if ! grep -Eq '^count: reply counts recomputed from the replies on the log = [1-9]' "$OUT/oracle.log"; then red "the oracle recounted no topic's replies"; fi
  if ! grep -Eq '^count: moderations held to a second person = [1-9]' "$OUT/oracle.log"; then red "the oracle held no moderation to a second person"; fi
  # every conversation compared, its words recounted from the log, every assignment re-derived from the reader's own queue
  if ! grep -Eq '^count: conversations compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no conversation"; fi
  if ! grep -Eq '^count: message counts recounted from the messages on the log = [1-9]' "$OUT/oracle.log"; then red "the oracle recounted no conversation's words"; fi
  if ! grep -Eq '^count: assignments re-derived from the queue = [1-9]' "$OUT/oracle.log"; then red "the oracle re-derived no assignment"; fi
  # every workflow compared, its participants re-derived by the reader's own runs, every wave refolded through its mailing fold
  if ! grep -Eq '^count: workflows compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no workflow"; fi
  if ! grep -Eq "^count: participants re-derived from the reader's own runs = [1-9]" "$OUT/oracle.log"; then red "the oracle re-derived no participant"; fi
  if ! grep -Eq "^count: waves refolded through the reader's mailing fold = [1-9]" "$OUT/oracle.log"; then red "the oracle refolded no wave"; fi
  # every text mailing compared, its list re-chained from the numbers the reader brought to one form, every copy recounted
  if ! grep -Eq '^count: text mailings compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no text mailing"; fi
  if ! grep -Eq '^count: lists re-chained from the numbers on the log = [1-9]' "$OUT/oracle.log"; then red "the oracle re-chained no list"; fi
  if ! grep -Eq '^count: copies recounted by state = [1-9]' "$OUT/oracle.log"; then red "the oracle recounted no copy"; fi
  # every social post compared, every claim re-derived from the reader's own queue, every image's fingerprint recomputed
  if ! grep -Eq '^count: social posts compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no social post"; fi
  if ! grep -Eq '^count: claims re-derived from the queue = [1-9]' "$OUT/oracle.log"; then red "the oracle re-derived no claim"; fi
  if ! grep -Eq '^count: image fingerprints recomputed from the chunks on the log = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no image fingerprint"; fi
  # every event compared, every ticket raised through the reader's own order fold, attendance held to the seats
  if ! grep -Eq '^count: events compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no event"; fi
  if ! grep -Eq "^count: tickets raised through the reader's order fold = [1-9]" "$OUT/oracle.log"; then red "the oracle raised no ticket"; fi
  if ! grep -Eq '^count: attendance held to the seats = [1-9]' "$OUT/oracle.log"; then red "the oracle held no attendance to its seats"; fi
  # every survey compared, every tally recomputed from the answers, every response held to one per respondent
  if ! grep -Eq '^count: surveys compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no survey"; fi
  if ! grep -Eq '^count: tallies recomputed from the answers on the log = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no tally"; fi
  if ! grep -Eq '^count: responses held to one per respondent = [1-9]' "$OUT/oracle.log"; then red "the oracle held no response to its respondent"; fi
  # every review cycle compared, every reviewer re-derived from the reader's own employees, every final rating read by the rule
  if ! grep -Eq '^count: review cycles compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no review cycle"; fi
  if ! grep -Eq "^count: reviewers re-derived from the reader's own employees = [1-9]" "$OUT/oracle.log"; then red "the oracle re-derived no reviewer"; fi
  if ! grep -Eq '^count: final ratings read by the rule = [1-9]' "$OUT/oracle.log"; then red "the oracle read no final rating"; fi
  if ! grep -Eq '^count: goal progress recomputed = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no goal's progress"; fi
  # every course compared, every progress held forward, every certification read against the calendar, every mentor's room counted
  if ! grep -Eq '^count: courses compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no course"; fi
  if ! grep -Eq '^count: enrolment progress held forward = [1-9]' "$OUT/oracle.log"; then red "the oracle held no progress forward"; fi
  if ! grep -Eq '^count: certification validity read against the calendar = [1-9]' "$OUT/oracle.log"; then red "the oracle read no certification against the calendar"; fi
  if ! grep -Eq '^count: mentor room counted from the mentorships that stand = [1-9]' "$OUT/oracle.log"; then red "the oracle counted no mentor's room"; fi
  # every pay band compared, every vested figure recomputed from the schedule, every incentive final and loan schedule recomputed, every period read, every benefit cost re-added
  if ! grep -Eq '^count: pay bands compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no pay band"; fi
  if ! grep -Eq '^count: vested figures recomputed from the schedule = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no vesting"; fi
  if ! grep -Eq '^count: incentive finals recomputed = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no incentive"; fi
  if ! grep -Eq '^count: loan schedules recomputed = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no loan schedule"; fi
  if ! grep -Eq '^count: enrolment periods read against the calendar = [1-9]' "$OUT/oracle.log"; then red "the oracle read no enrolment period"; fi
  if ! grep -Eq '^count: benefit costs re-added = [1-9]' "$OUT/oracle.log"; then red "the oracle re-added no benefit cost"; fi
  # every vehicle compared, every odometer and fuel amount and consumption recomputed, every contract's force read
  if ! grep -Eq '^count: vehicles compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no vehicle"; fi
  if ! grep -Eq '^count: odometers recomputed from the readings = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no odometer"; fi
  if ! grep -Eq '^count: fuel amounts recomputed = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no fuel amount"; fi
  if ! grep -Eq '^count: consumption recomputed from the fuellings = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no consumption"; fi
  if ! grep -Eq '^count: contract force read against the calendar = [1-9]' "$OUT/oracle.log"; then red "the oracle read no contract against the calendar"; fi
  # every notification compared, every audience computed by the reader, every channel's counts and every announcement's
  # reactions recomputed, every standing read
  if ! grep -Eq '^count: notifications compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no notification"; fi
  if ! grep -Eq '^count: discussion audiences computed from the memberships = [1-9]' "$OUT/oracle.log"; then red "the oracle computed no audience"; fi
  if ! grep -Eq '^count: channel counts recomputed from the rows = [1-9]' "$OUT/oracle.log"; then red "the oracle recounted no channel"; fi
  if ! grep -Eq '^count: announcement reactions re-added = [1-9]' "$OUT/oracle.log"; then red "the oracle re-added no reaction"; fi
  if ! grep -Eq '^count: announcement standing read against the calendar = [1-9]' "$OUT/oracle.log"; then red "the oracle read no announcement against the calendar"; fi
  if ! grep -Eq '^count: knowledge articles compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no knowledge article"; fi
  if ! grep -Eq '^count: knowledge counts re-added from the rows = [1-9]' "$OUT/oracle.log"; then red "the oracle re-added no article's views and votes"; fi
  if ! grep -Eq '^count: knowledge published versions re-read = [1-9]' "$OUT/oracle.log"; then red "the oracle re-read no published version"; fi
  if ! grep -Eq '^count: governance rows compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no governance row"; fi
  if ! grep -Eq '^count: acknowledgement fingerprints compared with the words registered = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no acknowledgement's fingerprint"; fi
  if ! grep -Eq '^count: policy acknowledgements re-added from the rows = [1-9]' "$OUT/oracle.log"; then red "the oracle re-added no policy's acknowledgements"; fi
  if ! grep -Eq '^count: figures runs whose members this reader recounted = [1-9]' "$OUT/oracle.log"; then red "the oracle recounted no run's members"; fi
  if ! grep -Eq '^count: compliance standings read against the calendar = [1-9]' "$OUT/oracle.log"; then red "the oracle read no standing against the calendar"; fi
  if ! grep -Eq '^count: workflow rows compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no workflow row"; fi
  if ! grep -Eq '^count: domain decisions held to the chain = [1-9]' "$OUT/oracle.log"; then red "the oracle held no domain decision to the chain"; fi
  if ! grep -Eq '^count: requests held to their domain.s record = [1-9]' "$OUT/oracle.log"; then red "the oracle held no request to its record"; fi
  # every studio row compared, every field's count re-added, every value's fingerprint recomputed and its record held
  # to a reader that watched it, and the values outside the rule in force re-derived - one of them at least
  if ! grep -Eq '^count: studio rows compared figure by figure = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no studio row"; fi
  if ! grep -Eq '^count: studio value counts re-added from the rows = [1-9]' "$OUT/oracle.log"; then red "the oracle re-added no field's values"; fi
  if ! grep -Eq '^count: studio value fingerprints recomputed from the log = [1-9]' "$OUT/oracle.log"; then red "the oracle recomputed no value's fingerprint"; fi
  if ! grep -Eq '^count: studio values held to a record a reader here watched = [1-9]' "$OUT/oracle.log"; then red "the oracle held no value to its record"; fi
  if ! grep -Eq '^count: studio values outside the rule in force, by the reader = [1-9]' "$OUT/oracle.log"; then red "the oracle re-derived no value outside the rule in force"; fi
  # every controls row compared whole, every criterion of every move of a run re-decided, every slice walked over the
  # reader's own rows, a run sealed and every posting recorded by the reader from the act that made it
  if ! grep -Eq '^count: controls rows compared whole = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no controls row"; fi
  if ! grep -Eq '^count: controls criteria re-decided for a move = [1-9]' "$OUT/oracle.log"; then red "the oracle re-decided no move's criteria"; fi
  if ! grep -Eq '^count: controls slices walked over the reader.s own rows = [1-9]' "$OUT/oracle.log"; then red "the oracle walked no screening slice"; fi
  if ! grep -Eq '^count: controls sealed = [1-9]' "$OUT/oracle.log"; then red "the oracle sealed no screening run"; fi
  if ! grep -Eq '^count: controls postings = [1-9]' "$OUT/oracle.log"; then red "the oracle recorded no posting"; fi
  # every call and the activity it carried out compared whole, a recording among them
  if ! grep -Eq '^count: voip rows compared whole = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no call"; fi
  if ! grep -Eq '^count: voip recorded = [1-9]' "$OUT/oracle.log"; then red "the oracle held no recording to its document"; fi
  # every engineering change, its lines and a production's pin compared whole, a version among them
  if ! grep -Eq '^count: plm rows compared whole = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no engineering change"; fi
  if ! grep -Eq '^count: plm versions = [1-9]' "$OUT/oracle.log"; then red "the oracle folded no version of a bill"; fi
  if ! grep -Eq '^count: plm pins = [1-9]' "$OUT/oracle.log"; then red "the oracle pinned no production to a version"; fi
  # ESG: every row of the seven tables compared whole, every run walked and sealed by the reader, and the FRA's answers
  # restated text for text from the reader's own figures
  if ! grep -Eq '^count: esg rows compared whole = [1-9]' "$OUT/oracle.log"; then red "the oracle compared no ESG row"; fi
  if ! grep -Eq '^count: esg runs sealed = [1-9]' "$OUT/oracle.log"; then red "the oracle sealed no ESG run"; fi
  if ! grep -Eq '^count: esg FRA answers restated text for text = [1-9]' "$OUT/oracle.log"; then red "the oracle restated no answer of the FRA's form"; fi
  # where the hub's copy of the official schema is present (the hub fetches it from ISO 20022 and does
  # not redistribute it), it must have accepted every message
  hub_dir="${HUB:-../thebes-example-open-banking-iso20022}"
  [ -n "${HUB:-}" ] || [ -d "$hub_dir" ] || hub_dir=../thebes-example-iso20022
  if [ -f "$hub_dir/integration-kit/profile-runner/official-schemas/iso-base/camt.053.001.08.xsd" ]; then
    if ! grep -Eq '^count: camt.053 messages valid against the official schema = [1-9]' "$OUT/oracle.log"; then red "the official camt.053 schema is beside this tree and no camt.053 was held to it"; fi
  else
    echo "note: the hub's official camt.053 schema is not fetched (its integration-kit/scripts/iso-xsd-fetch.py fetches it); the camt.053 messages were not held to the official schema"
  fi
  # where hledger is installed it must have read the journal and agreed; where it is not, the gate says so
  if command -v hledger > /dev/null 2>&1; then
    if ! grep -Eq '^count: hledger accounts agreed = [1-9]' "$OUT/oracle.log"; then red "hledger is installed and did not agree with the ledger"; fi
  else
    echo "note: hledger is not installed on this machine; the journal was checked by the reader's own parser and by beancount"
  fi
else
  cat "$OUT/oracle.log"; red "the oracle disagrees with the contract"
fi

# ── 5. the oracle's control ──────────────────────────────────────────────────
if [ "$QUICK" -eq 0 ]; then
  step "the oracle's control"
  if ./tools/oracle_control.sh "$OUT/export.txt" > "$OUT/oracle_control.log" 2>&1; then
    grep -E '^(count:|caught:|ORACLE CONTROL GREEN)' "$OUT/oracle_control.log"
  else
    cat "$OUT/oracle_control.log"; red "the oracle did not catch every corruption"
  fi
fi

# ── 6. the time surface ──────────────────────────────────────────────────────
step "the time surface"
if ./tools/no_direct_clock.sh > "$OUT/clock.log" 2>&1; then
  grep -E '^(count:|received:|the substrate clock is supplied by|TIME SURFACE GREEN)' "$OUT/clock.log"
else
  cat "$OUT/clock.log"; red "something reads a clock or takes a time from its caller"
fi
if [ "$QUICK" -eq 0 ]; then
  if ./tools/no_direct_clock_control.sh > "$OUT/clock_control.log" 2>&1; then
    grep -E '^(count:|caught:|CLOCK CONTROL GREEN)' "$OUT/clock_control.log"
  else
    cat "$OUT/clock_control.log"; red "the time check did not catch its own faults"
  fi
fi

# ── the tombstone walk ─────────────────────────────────────────────────────────
#
# No fold reads an index range from its head in one page and takes the page for the whole range
# (tools/tombstone_lint.py, src/Lookup.mo); the lint carries its own control.
step "the tombstone walk"
if python3 tools/tombstone_lint.py src > "$OUT/tombstone_lint.txt" 2>&1; then
  grep -E '^(count:|TOMBSTONE LINT GREEN)' "$OUT/tombstone_lint.txt"
else
  grep -E '^(FROM THE HEAD|CONTROL BROKEN|TOMBSTONE LINT FAILED)' "$OUT/tombstone_lint.txt" | head -20
  red "a fold reads a range from its head in one page"
fi

# ── the record kinds ───────────────────────────────────────────────────────────
#
# Every table whose rows carry a company is a kind of record a Studio field may be defined on, read
# from its own store, and every table that is not one is named for why - a part of a record, a
# platform table, Studio's own (tools/studio_lint.py, the generated block in src/State.mo); the lint
# carries its own control.
step "the record kinds"
if python3 tools/studio_lint.py src > "$OUT/studio_lint.txt" 2>&1; then
  grep -E '^(count:|STUDIO LINT GREEN)' "$OUT/studio_lint.txt"
else
  grep -vE '^count:' "$OUT/studio_lint.txt" | head -20
  red "a table is not held to the record kinds"
fi

# ── the read surface ───────────────────────────────────────────────────────────
#
# Every kind of record read by the class of reader written for it, deny by default, a person's record about them
# never opened to every member without the reason recorded, and src/ReadKinds.mo the text the tool writes from the
# declarations (tools/read_surface.py); the tool carries its control.
step "the read surface"
if python3 tools/read_surface.py src > "$OUT/read_surface.txt" 2>&1; then
  grep -E '^(count:|READ SURFACE GREEN)' "$OUT/read_surface.txt"
else
  grep -vE '^count:' "$OUT/read_surface.txt" | head -20
  red "a kind of record is not held to its readers"
fi

# ── the ESG sources ───────────────────────────────────────────────────────────
#
# Every seeded factor re-derived from the published files it names (tools/esg_sources.py): the files held to the
# SHA-256 integration/esg/SOURCES.md records, the derivation to integration/esg/factors.json, and every derived
# figure to the one the ESG battery weighs by - so the battery's arithmetic is the published factor's, not a number
# written beside it. Its control breaks the files, the derivation, the battery and the pin, with the controls.
step "the ESG sources"
if python3 tools/esg_sources.py > "$OUT/esg_sources.txt" 2>&1; then
  grep -E '^(count:|ESG SOURCES GREEN)' "$OUT/esg_sources.txt"
else
  grep -vE '^count:' "$OUT/esg_sources.txt" | head -10
  red "the ESG factors are not the published files'"
fi
if [ "$QUICK" -eq 0 ]; then
  if ./tools/esg_sources_control.sh > "$OUT/esg_sources_control.txt" 2>&1; then
    grep -E '^(count:|ESG SOURCES CONTROL GREEN)' "$OUT/esg_sources_control.txt"
  else
    grep -E '^(MISSED|CONTROL BROKEN|ESG)' "$OUT/esg_sources_control.txt"; red "the ESG sources check accepted a broken source"
  fi
fi

# ── the company-authority gate ───────────────────────────────────────────────
#
# Every act is held, before its fold runs, to the holders its family names (src/Gate.mo): the route compiled
# with a missed family an error, the lint's own control, the isolation samples current with the command type
# (tools/gate_lint.sh); and the gate's cost on one act under its pinned ceiling, at 32 members and at 2,048
# (tools/gate_cost.sh). What the gate refuses is proved by the Isolation and Platform batteries above, and the
# battery control removes the gate's rules one at a time.
step "the company-authority gate"
if ./tools/gate_lint.sh > "$OUT/gate_lint.log" 2>&1; then
  grep -E '^(count:|caught:|GATE LINT GREEN)' "$OUT/gate_lint.log"
else
  tail -20 "$OUT/gate_lint.log"; red "a command family is not routed by the gate, or the samples are stale"
fi
if ./tools/gate_cost.sh > "$OUT/gate_cost.log" 2>&1; then
  grep -E '^(count:|GATE COST GREEN)' "$OUT/gate_cost.log"
else
  tail -10 "$OUT/gate_cost.log"; red "the gate's cost on one act is past its ceiling, or grows with the company"
fi
# the audit index's company held to the route: no arm names a constant company, and only the platform's and the
# uploader's families are of no company (tools/audit_lint.py, with its own control first)
if python3 tools/audit_lint.py > "$OUT/audit_lint.log" 2>&1; then
  grep -E '^(count:|caught:|AUDIT LINT GREEN)' "$OUT/audit_lint.log"
else
  tail -10 "$OUT/audit_lint.log"; red "an act is indexed under a company its route does not find"
fi

# ── 8. the outcall and secret surface ────────────────────────────────────────
step "the outcall and secret surface"
if ./tools/outcall_and_secrets.sh > "$OUT/outcall.log" 2>&1; then
  grep -E '^(count:|OUTCALL AND SECRET SURFACE GREEN)' "$OUT/outcall.log"
else
  cat "$OUT/outcall.log"; red "a credential travels in a command, or an outbound call is replicated"
fi
if [ "$QUICK" -eq 0 ]; then
  if ./tools/outcall_and_secrets_control.sh > "$OUT/outcall_control.log" 2>&1; then
    grep -E '^(count:|caught:|OUTCALL CONTROL GREEN)' "$OUT/outcall_control.log"
  else
    cat "$OUT/outcall_control.log"; red "the outcall check did not catch its own faults"
  fi
fi


# ── 9. the advantages' control ───────────────────────────────────────────────
#
# `test/Usp.test.mo` asserts what a buyer is asked to believe, as far as code can carry it. An advantage seen only to hold is an advantage nobody knows is connected.
if [ "$QUICK" -eq 0 ]; then
  step "the advantages' control"
  if ./tools/usp_control.sh > "$OUT/usp_control.log" 2>&1; then
    grep -E '^(count:|caught:|USP CONTROL GREEN)' "$OUT/usp_control.log"
  else
    cat "$OUT/usp_control.log"; red "an advantage this system states is not kept by its code"
  fi
fi

# ── the module's compile bound ─────────────────────────────────────────────────
#
# What compiling the contract costs a node, bounded in every bar and not only where a chain is
# started (tools/wasm_bound.py): the module the chain installs, built by the chain's compiler.
step "the module's compile bound"
if ${MOC_THEBES:-$HOME/.thebes/toolchain/moc} --legacy-persistence $(./tools/packages.sh) -o "$OUT/mentat-bound.wasm" src/Mentat.mo 2> "$OUT/bound-build.log" \
   && python3 tools/wasm_bound.py "$OUT/mentat-bound.wasm" > "$OUT/wasm_bound.txt" 2>&1; then
  grep -E '^(count:|the largest|WASM BOUND GREEN)' "$OUT/wasm_bound.txt"
else
  grep -v warning "$OUT/bound-build.log" | head -5; cat "$OUT/wasm_bound.txt" 2>/dev/null
  red "the contract's module does not build, or a function in it is past the compile bound"
fi
rm -f "$OUT/mentat-bound.wasm"


# ── the published interface ───────────────────────────────────────────────────
#
# docs/landed/mentat.did is the contract's Candid, built by the deploy compiler from the source; a change to
# the source that changes the interface changes this file in the same commit.
step "the published interface"
if ! ${MOC_THEBES:-$HOME/.thebes/toolchain/moc} --idl $(./tools/packages.sh) -o "$OUT/mentat.did" src/Mentat.mo 2> "$OUT/idl-build.log"; then
  grep -v warning "$OUT/idl-build.log" | head -10; red "the contract's Candid did not build"
elif ! cmp -s "$OUT/mentat.did" docs/landed/mentat.did; then
  diff docs/landed/mentat.did "$OUT/mentat.did" | head -10; red "docs/landed/mentat.did is not the contract's Candid"
else
  echo "docs/landed/mentat.did is the contract's Candid"
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "CHECK FAILED: $fail check(s) red  (logs in $OUT)"
  exit 1
fi
if [ "$QUICK" -eq 1 ]; then echo "CHECK GREEN, QUICK: no controls  (logs in $OUT)"; else echo "CHECK GREEN  (logs in $OUT)"; fi
