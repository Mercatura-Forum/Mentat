#!/usr/bin/env bash
# The oracle's negative control: corrupt the exported log and require the reader to notice.
#
# The reader's whole value is that it believes nothing the contract says. A reader that accepted a
# corrupted block, a reordered log, or a spliced one would agree with the contract about a state
# neither of them can justify - which is worse than having no reader, because it would be quoted.
#
# Nine faults, one per property the reader claims (the first five over the chain itself):
#   1. a byte of a block's body changed            → the stored hash no longer matches
#   2. a block's stored hash changed               → the same, from the other side
#   3. two blocks swapped                          → an index that is not its position
#   4. a block dropped from the middle             → a parent hash that does not link
#   5. the tip changed                             → the last block is not the tip published
#
# Usage: oracle_control.sh <exported-log>
#
# Attribution: Thebes Core Team. Licence: Apache 2.0.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
LOG="${1:?usage: oracle_control.sh <exported-log>}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

READER="$HERE/integration/oracle/log_reader.py"
caught=0
missed=0

try() {
  local what="$1"; local file="$2"
  if ! diff -q "$LOG" "$file" > /dev/null 2>&1; then
    if python3 "$READER" "$file" > "$TMP/$what.out" 2>&1; then
      echo "MISSED: the oracle accepted $what"
      missed=$((missed+1))
    else
      echo "caught: $what"
      grep -E "^ORACLE: " "$TMP/$what.out" | head -1
      caught=$((caught+1))
    fi
  else
    echo "CONTROL BROKEN: the $what injection changed nothing"
    missed=$((missed+1))
  fi
}

# The mutations are `tools/mutate_log.py`, not inline awk: the first version of this control used
# awk's `strtonum`, which is a GNU extension, and under mawk the three hex-rotating faults silently
# changed nothing while the control reported the ORACLE as having accepted them. A control whose
# own injection fails is worse than no control, because it accuses the thing it checks - which is
# why `try` refuses a file it cannot see a difference in.
MUTATE="$HERE/tools/mutate_log.py"

# 1 - a byte of a block's body: the stored hash no longer matches what it covers
python3 "$MUTATE" "$LOG" "$TMP/body.txt" body    && try body-byte-changed "$TMP/body.txt"
# 2 - the stored hash itself: the same failure approached from the other side
python3 "$MUTATE" "$LOG" "$TMP/hash.txt" hash    && try stored-hash-changed "$TMP/hash.txt"
# 3 - two blocks' bytes swapped: an index that is not its position
python3 "$MUTATE" "$LOG" "$TMP/swap.txt" swap    && try blocks-swapped "$TMP/swap.txt"
# 4 - a block dropped from the middle: the chain no longer links
python3 "$MUTATE" "$LOG" "$TMP/dropped.txt" drop && try block-dropped "$TMP/dropped.txt"
# 5 - the published tip changed: the last block is not what the contract says it is
python3 "$MUTATE" "$LOG" "$TMP/tip.txt" tip      && try tip-changed "$TMP/tip.txt"
# 6 - a reported payslip figure that the recomputation contradicts
python3 "$MUTATE" "$LOG" "$TMP/slip.txt" payslip && try payslip-figure-moved "$TMP/slip.txt"
# 7 - a reported quant that the refold of the pickings contradicts
python3 "$MUTATE" "$LOG" "$TMP/quant.txt" quant && try quant-moved "$TMP/quant.txt"
# 8 - a validated picking's reported value that the decimal recomputation contradicts
python3 "$MUTATE" "$LOG" "$TMP/pval.txt" picking-value && try picking-value-moved "$TMP/pval.txt"
# 9 - a campaign's reported winner flipped: the reader's own application of the recorded rule contradicts it
python3 "$MUTATE" "$LOG" "$TMP/winner.txt" campaign-winner && try campaign-winner-flipped "$TMP/winner.txt"
python3 "$MUTATE" "$LOG" "$TMP/close.txt" close-result && try close-result-moved "$TMP/close.txt"
python3 "$MUTATE" "$LOG" "$TMP/stmt.txt" statement-figure && try statement-figure-moved "$TMP/stmt.txt"
python3 "$MUTATE" "$LOG" "$TMP/defer.txt" deferral-part && try deferral-part-moved "$TMP/defer.txt"
python3 "$MUTATE" "$LOG" "$TMP/reval.txt" revaluation-difference && try revaluation-difference-moved "$TMP/reval.txt"
python3 "$MUTATE" "$LOG" "$TMP/asset.txt" asset-charge && try asset-charge-moved "$TMP/asset.txt"
python3 "$MUTATE" "$LOG" "$TMP/claim.txt" claim-amount && try claim-amount-moved "$TMP/claim.txt"
python3 "$MUTATE" "$LOG" "$TMP/payment.txt" payment-hash && try payment-hash-moved "$TMP/payment.txt"
python3 "$MUTATE" "$LOG" "$TMP/camt.txt" camt-amount && try camt-amount-moved "$TMP/camt.txt"
# 18 - an item's interest moved by a piastre: the reader's own interest arithmetic contradicts it
python3 "$MUTATE" "$LOG" "$TMP/credit.txt" credit-interest && try credit-interest-moved "$TMP/credit.txt"
# 19 - a consolidation's total debits moved by a piastre: the reader's own fold of the member statements and the eliminations contradicts it
python3 "$MUTATE" "$LOG" "$TMP/consolidation.txt" consolidation-figure && try consolidation-figure-moved "$TMP/consolidation.txt"
# 20 - a work order's downtime moved by a day: the reader's own fold of the sign-off contradicts it
python3 "$MUTATE" "$LOG" "$TMP/maintenance.txt" maintenance-downtime && try maintenance-downtime-moved "$TMP/maintenance.txt"
# 21 - a quality check's verdict flipped: the reader's own fold of the check on the log contradicts it
python3 "$MUTATE" "$LOG" "$TMP/quality.txt" quality-verdict && try quality-verdict-flipped "$TMP/quality.txt"
# 22 - a ticket's resolution clock moved by a day: the reader's own walk over the company's calendar contradicts it
python3 "$MUTATE" "$LOG" "$TMP/ticket.txt" ticket-clock && try ticket-clock-moved "$TMP/ticket.txt"
# 23 - an invoiced visit's labour moved by a minute: the reader's own sum of the task's approved time contradicts it
python3 "$MUTATE" "$LOG" "$TMP/visit.txt" visit-labour && try visit-labour-moved "$TMP/visit.txt"
# 24 - a booking's slot moved by a minute: the reader's own fold of the booking on the log contradicts it
python3 "$MUTATE" "$LOG" "$TMP/booking.txt" booking-slot && try booking-slot-moved "$TMP/booking.txt"
# 25 - a proration moved by a minor unit: the reader's own arithmetic over the calendar's days contradicts it
python3 "$MUTATE" "$LOG" "$TMP/proration.txt" proration-amount && try proration-amount-moved "$TMP/proration.txt"
# 26 - a rental's late days moved by one: the reader's own count from the agreed day and the day of return contradicts it
python3 "$MUTATE" "$LOG" "$TMP/rental.txt" rental-late-days && try rental-late-days-moved "$TMP/rental.txt"
# 27 - a till session's cash takings moved by a minor unit: the reader's own sum over the session's sales contradicts it
python3 "$MUTATE" "$LOG" "$TMP/till.txt" till-takings && try till-takings-moved "$TMP/till.txt"
# 28 - a share of a split bill moved by a minor unit: the reader's own split of the sale's total by the rule contradicts it
python3 "$MUTATE" "$LOG" "$TMP/share.txt" bill-share && try bill-share-moved "$TMP/share.txt"
# 29 - a web order's payment moved by a minor unit: the reader's own total of the order it paid for contradicts it
python3 "$MUTATE" "$LOG" "$TMP/webpaid.txt" web-paid && try web-paid-moved "$TMP/webpaid.txt"
# 30 - a page version's fingerprint turned by a digit: the reader's own hash of the chunks on the log contradicts it
python3 "$MUTATE" "$LOG" "$TMP/page.txt" page-fingerprint && try page-fingerprint-turned "$TMP/page.txt"
# 31 - a post's day moved by one: the day of the block it was published at, read from the log, contradicts it
python3 "$MUTATE" "$LOG" "$TMP/post.txt" post-day && try post-day-moved "$TMP/post.txt"
# 32 - a topic's count of replies moved by one: the reader's own count of the replies on the log contradicts it
python3 "$MUTATE" "$LOG" "$TMP/topic.txt" reply-count && try reply-count-moved "$TMP/topic.txt"
# 33 - a conversation's count of words moved by one: the reader's own count of the messages on the log contradicts it
python3 "$MUTATE" "$LOG" "$TMP/chat.txt" chat-words && try chat-words-moved "$TMP/chat.txt"
# 34 - a participant's next step moved by one: the reader's own walk of the enrolment and step runs contradicts it
python3 "$MUTATE" "$LOG" "$TMP/participant.txt" participant-step && try participant-step-moved "$TMP/participant.txt"
# 35 - a text mailing's count of copies sent moved by one: the reader's own recount of the copies by state contradicts it
python3 "$MUTATE" "$LOG" "$TMP/sms.txt" sms-sent && try sms-sent-moved "$TMP/sms.txt"
# 36 - a social post's attempts moved by one: the reader's own queue, from which it re-derives every claim, contradicts it
python3 "$MUTATE" "$LOG" "$TMP/social.txt" post-attempts && try post-attempts-moved "$TMP/social.txt"
# 37 - a ticket's seats moved by one: the reader's own sale through its order fold and its recount of the event's seats contradict it
python3 "$MUTATE" "$LOG" "$TMP/ticket.txt" ticket-seats && try ticket-seats-moved "$TMP/ticket.txt"
# 38 - a question's tally moved by one: the reader's own recount from the answer rows it folded contradicts it
python3 "$MUTATE" "$LOG" "$TMP/survey.txt" survey-tally && try survey-tally-moved "$TMP/survey.txt"
# 39 - a review's final rating moved by one: the reader reads the final rating by the rule, never from the row, and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/review.txt" review-final && try review-final-moved "$TMP/review.txt"
# 40 - a certification's validity flipped: the reader reads it against the calendar on the day the contract names and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/cert.txt" cert-valid && try cert-valid-flipped "$TMP/cert.txt"
# 41 - a grant's vested figure moved by a share: the reader computes the schedule itself, with its own calendar, on the day the contract names and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/grant.txt" vested-shares && try vested-shares-moved "$TMP/grant.txt"
# 42 - a fuelling's amount moved by a minor unit: the reader multiplies the litres by the price itself and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/fuel.txt" fuel-amount && try fuel-amount-moved "$TMP/fuel.txt"
# 43 - an announcement sweep's acted moved by one: the reader recounts it from the notifications the sweep wrote and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/sweep.txt" sweep-acted && try sweep-acted-moved "$TMP/sweep.txt"
# 44 - a swept notification moved onto another member: the reader computes the audience itself from the memberships and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/audience.txt" audience-recipient && try audience-recipient-moved "$TMP/audience.txt"
# 45 - a published article's category moved: the reader re-reads it from the version published and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/kbcat.txt" kb-category && try kb-category-moved "$TMP/kbcat.txt"
# 46 - a run of the figures counting one member more: the reader walks the members itself and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/runmembers.txt" run-members && try run-members-moved "$TMP/runmembers.txt"
# 47 - a step decided under a delegation reported in the delegate's own name: the reader holds the step to the delegation and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/behalf.txt" behalf-moved && try behalf-moved "$TMP/behalf.txt"
# 48 - a studio value reported under a fingerprint one digit off: the reader recomputes it from the command's bytes and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/stfp.txt" studio-fingerprint && try studio-fingerprint-moved "$TMP/stfp.txt"
# 49 - a studio field reported holding one value more: the reader re-adds its values from the rows and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/stvals.txt" studio-values && try studio-values-moved "$TMP/stvals.txt"
# 50 - the values outside the rule in force reported one more: the reader re-derives them and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/stout.txt" studio-outside && try studio-outside-moved "$TMP/stout.txt"
# 51 - a posting recorded generated where a person posted it by hand: the reader records every posting from the act that made it and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/ctlman.txt" ctl-posting-manual && try ctl-posting-manual-moved "$TMP/ctlman.txt"
# 52 - a posting's day moved by one: the reader takes it from the block that posted the move and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/ctlday.txt" ctl-posting-day && try ctl-posting-day-moved "$TMP/ctlday.txt"
# 53 - a finding's criteria with one bit flipped: the reader re-decides every criterion of every move and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/ctlcrit.txt" ctl-finding-criteria && try ctl-finding-criteria-moved "$TMP/ctlcrit.txt"
# 54 - a count a run took moved by one: the reader recounts the population itself and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/ctlcount.txt" ctl-count && try ctl-count-moved "$TMP/ctlcount.txt"
# 55 - a run's digit-test deviation moved by one: the reader recomputes it in exact fractions and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/ctlmad.txt" ctl-run-mad && try ctl-run-mad-moved "$TMP/ctlmad.txt"
# 56 - a run sealed at another tip: the reader takes the tip from the block below the seal and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/ctltip.txt" ctl-run-tip && try ctl-run-tip-moved "$TMP/ctltip.txt"
# 57 - a run's hash one digit off: the reader rehashes the figures it restated and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/ctlhash.txt" ctl-run-hash && try ctl-run-hash-moved "$TMP/ctlhash.txt"
# 58 - an order's confirmation recorded a block late: the reader records it in the block that confirmed it and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/ctlconf.txt" ctl-confirmation-block && try ctl-confirmation-block-moved "$TMP/ctlconf.txt"
# 59 - a conclusion's reviewer moved onto another member: the reader takes the reviewer from the block and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/ctlrev.txt" ctl-conclusion-reviewer && try ctl-conclusion-reviewer-moved "$TMP/ctlrev.txt"
# 60 - a call's number one digit off: the reader brings the number on the log to one form itself and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/vonum.txt" voip-number && try voip-number-moved "$TMP/vonum.txt"
# 61 - a call's seconds moved by one: the reader takes them from the act that logged it and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/vosec.txt" voip-seconds && try voip-seconds-moved "$TMP/vosec.txt"
# 62 - a call's consent flipped: the reader takes it from the act and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/vocon.txt" voip-consent && try voip-consent-moved "$TMP/vocon.txt"
# 63 - a call recorded in another document: the reader holds the recording to the act that attached it and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/vorec.txt" voip-recording && try voip-recording-moved "$TMP/vorec.txt"
# 64 - a call moved onto another member: the reader takes the member from the block's caller and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/vomem.txt" voip-member && try voip-member-moved "$TMP/vomem.txt"
# 65 - the feedback of a call's activity one digit off: the reader composes the call's account itself and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/vofb.txt" voip-feedback && try voip-feedback-moved "$TMP/vofb.txt"
# 66 - a change's version number moved: the reader numbers every bill's versions itself and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/plver.txt" plm-version && try plm-version-moved "$TMP/plver.txt"
# 67 - a change's state moved: the reader takes it from the act that decided it and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/plst.txt" plm-state && try plm-state-moved "$TMP/plst.txt"
# 68 - a change decided by another member: the reader takes the decider from the block's caller and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/pldec.txt" plm-decider && try plm-decider-moved "$TMP/pldec.txt"
# 69 - a change's effective day moved by one: the reader takes it from the act that proposed it and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/pleff.txt" plm-effective && try plm-effective-moved "$TMP/pleff.txt"
# 70 - a change's component quantity moved: the reader takes the lines from the act and contradicts it
python3 "$MUTATE" "$LOG" "$TMP/plline.txt" plm-line-quantity && try plm-line-quantity-moved "$TMP/plline.txt"
# 71 - a production pinned to another change: the reader pins every production to the version in effect on its day itself
python3 "$MUTATE" "$LOG" "$TMP/plpin.txt" plm-pin && try plm-pin-moved "$TMP/plpin.txt"

# 72, 73 - WHO SENT A BLOCK, on a chain made whole again (tools/mutate_log.py recomputes the moved block's hash, every
# later block's parent and hash, and the tip), so the chain cannot be what catches it: an act a company's
# administrator sent recorded as a stranger's, and the platform operator's claim recorded as another principal's.
# The reader must refuse each for its own gate's reason, not for any other.
try_gate() {
  local what="$1"; local file="$2"; local before=$caught
  try "$what" "$file"
  if [ "$caught" -gt "$before" ] && ! grep -q "from a caller the gate refuses" "$TMP/$what.out"; then
    echo "CONTROL BROKEN: the reader refused $what, but not for the gate's reason"
    caught=$((caught-1)); missed=$((missed+1))
  fi
}
python3 "$MUTATE" "$LOG" "$TMP/gsend.txt" gate-sender-moved && try_gate gate-sender-moved "$TMP/gsend.txt"
python3 "$MUTATE" "$LOG" "$TMP/gclaim.txt" gate-claim-moved && try_gate gate-claim-moved "$TMP/gclaim.txt"
# THE COMPANY'S AUDITOR ACTS IN NOTHING: a department the boss created recorded as the auditor's, on a chain made
# whole again. The auditor stands in the company, so the reader must refuse it as the auditor's, not as a stranger's.
python3 "$MUTATE" "$LOG" "$TMP/gaud.txt" gate-auditor-acted && try_gate gate-auditor-acted "$TMP/gaud.txt"
if [ -f "$TMP/gate-auditor-acted.out" ] && grep -q "from a caller the gate refuses" "$TMP/gate-auditor-acted.out" \
   && ! grep -q "the caller holds Auditor" "$TMP/gate-auditor-acted.out"; then
  echo "CONTROL BROKEN: the reader refused gate-auditor-acted, but not as the auditor's act"
  caught=$((caught-1)); missed=$((missed+1))
fi
# 74, 75, 76 - THE AUDIT INDEX: an entry indexed under another company, an entry under a company naming another
# caller, and one entry left out. The reader writes both tables from the blocks it decodes and compares them both
# ways, so each is a fault on its own.
python3 "$MUTATE" "$LOG" "$TMP/aucco.txt" audit-caller-company && try audit-caller-company-moved "$TMP/aucco.txt"
python3 "$MUTATE" "$LOG" "$TMP/aucca.txt" audit-company-caller && try audit-company-caller-moved "$TMP/aucca.txt"
python3 "$MUTATE" "$LOG" "$TMP/audrop.txt" audit-company-dropped && try audit-company-entry-dropped "$TMP/audrop.txt"
# 77, 78 - EVERY FAMILY FROM THE CONTRACT'S OWN BYTES: a family's rich sample with its last byte moved (read back by
# its declared type, value for value), and one family's plain sample left out of the export
python3 "$MUTATE" "$LOG" "$TMP/cdrich.txt" codec-rich-moved && try codec-rich-sample-moved "$TMP/cdrich.txt"
python3 "$MUTATE" "$LOG" "$TMP/cdplain.txt" codec-plain-dropped && try codec-plain-sample-dropped "$TMP/cdplain.txt"
# 79, 80 - THE EXPLOSION AND THE PIPELINE, RECOMPUTED: the deepest requirement row's quantity moved by one, and the
# weighted forecast of the opportunity whose figure truncates moved by one; the reader derives both from the log
python3 "$MUTATE" "$LOG" "$TMP/rqqty.txt" requirement-quantity && try requirement-quantity-moved "$TMP/rqqty.txt"
python3 "$MUTATE" "$LOG" "$TMP/ldplan.txt" lead-planned && try lead-forecast-moved "$TMP/ldplan.txt"
# 81, 82 - THE SWEEP AND THE SCORING RUN, RESTATED: an activity the reminder sweep reminded shown as never reminded,
# and a scored lead's score moved by one; the reader sweeps the same heads and scores every lead itself
python3 "$MUTATE" "$LOG" "$TMP/acrem.txt" activity-unreminded && try activity-reminder-dropped "$TMP/acrem.txt"
python3 "$MUTATE" "$LOG" "$TMP/ldscore.txt" lead-score && try lead-score-moved "$TMP/ldscore.txt"
# 83 to 94 - ESG, RESTATED FROM THE LOG: a figure's CO2e and its amount moved by one, a sealed run's lines assigned, its
# chain and its hash moved, a factor version's approver and its kilojoules, a gas's micrograms, a rule shown retired,
# an activity shown cancelled, a disclosure's scope 1 and an answer of the FRA's form turned; the reader weighs every
# entry, chains and hashes every run and writes every answer itself
for m in esg-figure-co2e esg-figure-amount esg-run-assigned esg-run-chain esg-run-hash esg-factor-approver esg-factor-kilojoules \
         esg-gas-micrograms esg-rule-retired esg-activity-state esg-disclosure-scope1 esg-fra-answer; do
  python3 "$MUTATE" "$LOG" "$TMP/$m.txt" "$m" && try "$m-moved" "$TMP/$m.txt"
done
# 96, 97, 98 - DRAFTS, REFOLDED FROM THE LOG: an acceptance moved onto a member the draft was not made for, who holds
# its act by no role, on a chain made whole again; the first draft's block its act was made in moved by one; and its
# source's kind turned. The reader holds every acceptance to the person and the roles, and compares every draft whole
python3 "$MUTATE" "$LOG" "$TMP/dracc.txt" draft-acceptor-moved && try draft-acceptor-moved "$TMP/dracc.txt"
if [ -f "$TMP/draft-acceptor-moved.out" ] && ! grep -q "for whom it was not made and who holds createDepartment by no role" "$TMP/draft-acceptor-moved.out"; then
  echo "CONTROL BROKEN: the reader refused draft-acceptor-moved, but not as an acceptance by somebody the draft was not made for"
  caught=$((caught-1)); missed=$((missed+1))
fi
for m in draft-accepted-block draft-source-kind; do
  python3 "$MUTATE" "$LOG" "$TMP/$m.txt" "$m" && try "$m-moved" "$TMP/$m.txt"
done
# 99 to 103 - THE READ METHOD'S PAGES, HELD TO THE FOLD: one page re-encoded whole with one thing changed, so the decoder
# accepts it - an account's name, a punch left out of its walk (the export's count of rows lowered with it), a page's
# tip, a walk of two pages cut after the first, a department moved into another company's figures. Each must be caught
# for its own reason.
try_reason() {
  local what="$1"; local file="$2"; local why="$3"; local before=$caught
  try "$what" "$file"
  if [ "$caught" -gt "$before" ] && ! grep -q -- "$why" "$TMP/$what.out"; then
    echo "CONTROL BROKEN: the reader refused $what, but not for its own reason ($why)"
    caught=$((caught-1)); missed=$((missed+1))
  fi
}
python3 "$MUTATE" "$LOG" "$TMP/rpfield.txt" read-page-field && try_reason read-page-field-moved "$TMP/rpfield.txt" "\.name: the page says"
python3 "$MUTATE" "$LOG" "$TMP/rprow.txt" read-page-row-dropped && try_reason read-page-row-dropped "$TMP/rprow.txt" "is in this reader's fold and in no page"
python3 "$MUTATE" "$LOG" "$TMP/rptip.txt" read-page-tip && try_reason read-page-tip-moved "$TMP/rptip.txt" "or a tip that is not the hash it chained"
python3 "$MUTATE" "$LOG" "$TMP/rpwalk.txt" read-page-walk-cut && try_reason read-page-walk-cut "$TMP/rpwalk.txt" "and the walk goes on"
python3 "$MUTATE" "$LOG" "$TMP/rpco.txt" read-page-company && try_reason read-page-company-moved "$TMP/rpco.txt" "names company 2 in a page of company 1"
# 104 - AN IDEA'S VOTE AS ITS AUTHOR'S: the first vote on an idea recorded as sent by the person who opened it, on a
# chain made whole again; the author is a member, so the gate admits the block, and the forum reader must refuse it
# for its own rule
python3 "$MUTATE" "$LOG" "$TMP/ideavote.txt" idea-author-votes && try_reason idea-author-votes "$TMP/ideavote.txt" "VOTED ON IT"
# 105 - A MEMBER'S ANSWER AS ANOTHER'S: the first answer to a members' event recorded as sent by a second member, on a
# chain made whole again; the gate admits it, and the events reader must refuse that member's own answer after it
python3 "$MUTATE" "$LOG" "$TMP/eventanswer.txt" event-answer-moved && try_reason event-answer-moved "$TMP/eventanswer.txt" "GAVE THE SAME ANSWER TWICE"
# 106 - EQUIPMENT HANDED TO ONESELF: the first hand-over of a piece recorded as sent by the employee it was handed to, on
# a chain made whole again; the gate admits a member, and the maintenance reader must refuse it for its own rule
python3 "$MUTATE" "$LOG" "$TMP/selfhanded.txt" equipment-self-handed && try_reason equipment-self-handed "$TMP/selfhanded.txt" "HANDED OUT EQUIPMENT IT COULD NOT"
echo "count: oracle faults injected = $((caught+missed))"
echo "count: oracle faults the reader caught = $caught"
if [ "$missed" -ne 0 ]; then echo "ORACLE CONTROL FAILED: $missed fault(s) accepted"; exit 1; fi
echo "ORACLE CONTROL GREEN"
