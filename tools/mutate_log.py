#!/usr/bin/env python3
"""Corrupt an exported log in one named way, for the oracle's negative control.

Each mutation targets exactly one property the reader claims to check, and each changes as little
as possible - a single hex nibble where it can - so that what the reader catches is the property
and not the shape of the damage.

Usage: mutate_log.py <source|ctl-posting-manual|ctl-posting-day|ctl-finding-criteria|ctl-count|ctl-run-mad|ctl-run-tip|ctl-run-hash|ctl-confirmation-block|ctl-conclusion-reviewer|voip-number|voip-seconds|voip-consent|voip-recording|voip-member|voip-feedback|plm-version|plm-state|plm-decider|plm-effective|plm-line-quantity|plm-pin|esg-figure-co2e|esg-figure-amount|esg-run-assigned|esg-run-chain|esg-run-hash|esg-factor-approver|esg-factor-kilojoules|esg-gas-micrograms|esg-rule-retired|esg-activity-state|esg-disclosure-scope1|esg-fra-answer|draft-accepted-block|draft-source-kind> <destination> <body|hash|swap|drop|tip|payslip|quant|picking-value|campaign-winner|close-result|statement-figure|deferral-part|revaluation-difference|asset-charge|claim-amount|payment-hash|camt-amount|credit-interest|consolidation-figure|maintenance-downtime|quality-verdict|ticket-clock|visit-labour|booking-slot|proration-amount|rental-late-days|till-takings|bill-share|web-paid|page-fingerprint|post-day|reply-count|chat-words|participant-step|sms-sent|post-attempts|ticket-seats|survey-tally|review-final|cert-valid|vested-shares|fuel-amount|sweep-acted|audience-recipient|kb-category|run-members|behalf-moved|studio-fingerprint|studio-values|studio-outside|gate-sender-moved|gate-auditor-acted|gate-claim-moved|draft-acceptor-moved|idea-author-votes|event-answer-moved|equipment-self-handed|audit-caller-company|audit-company-caller|audit-company-dropped|codec-rich-moved|codec-plain-dropped|requirement-quantity|lead-planned|activity-unreminded|lead-score|read-page-field|read-page-row-dropped|read-page-tip|read-page-walk-cut|read-page-company>

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import sys


def rot(h, i):
    """Rotate one hex digit, so the change is a single nibble and no length moves."""
    c = h[i]
    return h[:i] + ("0" if c == "f" else "%x" % (int(c, 16) + 1)) + h[i + 1:]


def _flip(b):
    return "0" if b == "1" else "1"


def _hexoff(h):
    return ("1" if h[0] != "1" else "2") + h[1:]


# what: (row prefix, field index in the printed line, how the field is moved)
CONTROLS_MUTATIONS = {
    "ctl-posting-manual": ("move_posting", 4, _flip),
    "ctl-posting-day": ("move_posting", 3, lambda d: str(int(d) + 1)),
    "ctl-finding-criteria": ("ctl_finding", 6, lambda m: str(int(m) ^ 1)),
    "ctl-count": ("ctl_count", 5, lambda c: str(int(c) + 1)),
    "ctl-run-mad": ("ctl_run", 24, lambda x: str(int(x) + 1)),
    "ctl-run-tip": ("ctl_run", 30, _hexoff),
    "ctl-run-hash": ("ctl_run", 31, _hexoff),
    "ctl-confirmation-block": ("order_confirmation", 4, lambda b: str(int(b) + 1)),
    "ctl-conclusion-reviewer": ("ctl_conclusion", 11, lambda p: p[:-1] + ("1" if p[-1] != "1" else "2")),
}

# the same, for a call and the activity it carried out (voip_call: id company lead activity member direction number
# outcome seconds day consent note recording recordedDay lastBlock; voip_activity: id company lead assignee deadline
# done doneDay summary feedback)
# the same, for an engineering change, its lines and a production's pin (plm_eco: id company bom code quantity
# effectiveDay version state lineCount proposer proposedDay reason decidedBy decidedDay note lastBlock; plm_eco_line: id
# eco company ordinal category quantity lastBlock; plm_pin: production company bom eco lastBlock), split on single spaces
PLM_MUTATIONS = {
    "plm-version": ("plm_eco", 7, lambda x: str(int(x) + 1)),
    "plm-state": ("plm_eco", 8, lambda x: "3" if x != "3" else "2"),
    "plm-decider": ("plm_eco", 13, _hexoff),
    "plm-effective": ("plm_eco", 6, lambda x: str(int(x) + 1)),
    "plm-line-quantity": ("plm_eco_line", 6, lambda x: str(int(x) + 1)),
    "plm-pin": ("plm_pin", 4, lambda x: str(int(x) + 1)),
}

# the same, for ESG (split on single spaces): a figure's CO2e and amount, a sealed run's lines assigned, chain and hash,
# a factor version's approver and kilojoules, a gas's micrograms, a rule's retirement, an activity's state, a
# disclosure's scope 1 and an answer of the FRA's form. esg_figure: id run company kind scope category detail department
# amount co2e entries lastBlock; esg_run: id company from through phase cursorDay cursorId openedBlock openedBy openedDay
# lines linesAssigned activities activitiesAssigned activitiesMeasured figures sealedBlock tip chain hash lastBlock;
# esg_factor: id company code version set sha scope category basis unit per gases source kilojoules state recordedBy
# approvedBy recordedDay approvedDay approvedBlock lastBlock; esg_gas: id company ownerKind owner ordinal gas group
# micrograms gwp lastBlock; esg_rule: id company code product partner account created retired ...; esg_activity: ...
# field 14 its state; esg_disclosure: run prior company from through sealed hash scope1 ...; esg_fra: run prior code
# question answer clarification
ESG_MUTATIONS = {
    "esg-figure-co2e": ("esg_figure", 10, lambda x: str(int(x) + 1)),
    "esg-figure-amount": ("esg_figure", 9, lambda x: str(int(x) + 1)),
    "esg-run-assigned": ("esg_run", 12, lambda x: str(int(x) + 1)),
    "esg-run-chain": ("esg_run", 19, _hexoff),
    "esg-run-hash": ("esg_run", 20, _hexoff),
    "esg-factor-approver": ("esg_factor", 17, _hexoff),
    "esg-factor-kilojoules": ("esg_factor", 14, lambda x: str(int(x) + 1)),
    "esg-gas-micrograms": ("esg_gas", 8, lambda x: str(int(x) + 1)),
    "esg-rule-retired": ("esg_rule", 8, lambda x: str(int(x) + 1)),
    "esg-activity-state": ("esg_activity", 14, lambda x: "2" if x != "2" else "1"),
    "esg-disclosure-scope1": ("esg_disclosure", 8, lambda x: str(int(x) + 1)),
    "esg-fra-answer": ("esg_fra", 5, lambda x: "No" if x != "No" else "Yes"),
}

# the same, for drafts (draft: id company proposer forPerson version tag bytes sourceKind sourceId sha256 name edition
# note proposedDay expiryDay state decidedBy decidedDay reason acceptedBlock lastBlock): the first draft's block its act
# was made in moved by one, and its source's kind turned
DRAFT_MUTATIONS = {
    "draft-accepted-block": ("draft", 20, lambda x: str(int(x) + 1)),
    "draft-source-kind": ("draft", 8, lambda x: "1" if x != "1" else "2"),
}

# the same, for the audit index (audit_caller: height caller family company; audit_company: height company family
# caller), split on single spaces: an entry indexed under another company, an entry naming another caller, and one
# entry left out
AUDIT_MUTATIONS = {
    "audit-caller-company": ("audit_caller", 4, lambda x: str(int(x) + 1)),
    "audit-company-caller": ("audit_company", 4, _hexoff),
    "audit-company-dropped": ("audit_company", None, None),
}

VOIP_MUTATIONS = {
    "voip-number": ("voip_call", 7, lambda n: n[:-1] + ("1" if n[-1] != "1" else "2")),
    "voip-seconds": ("voip_call", 9, lambda x: str(int(x) + 1)),
    "voip-consent": ("voip_call", 11, _flip),
    "voip-recording": ("voip_call", 13, lambda x: str(int(x) + 1)),
    "voip-member": ("voip_call", 5, _hexoff),
    "voip-feedback": ("voip_activity", 9, _hexoff),
}


def _resend(lines, caller_of):
    """THE SENDER OF ONE BLOCK MOVED, AND THE CHAIN MADE WHOLE AGAIN. A corruption the chain catches says nothing
    about whether the reader holds a block's sender to the gate: the hash would refuse it first. So the first block
    for which `caller_of` names a new caller keeps every byte but its caller's; its stored hash is recomputed, every
    later block's parent and stored hash after it, and the tip - a log as consistent as a forger with the chain's
    own hash function could make it, wrong only in who sent the one block. The caller may change length (a
    principal is length-prefixed), so every block from the moved one is written out again in parts of the export's
    own width. Returns the moved block's index, or None if no block was chosen."""
    import os
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "integration", "oracle"))
    from canonical import Reader, hash_with_domain  # noqa: E402
    import log_reader  # noqa: E402
    parts, width = {}, 0
    for n, line in enumerate(lines):
        if line.startswith("block: "):
            _, num, part, hx = line.split(None, 3)
            parts.setdefault(int(num), {})[int(part)] = (n, hx)
            width = max(width, len(hx))
    order = sorted(parts)
    raws = {i: bytearray(bytes.fromhex("".join(parts[i][k][1] for k in sorted(parts[i])))) for i in order}

    def layout(raw):
        r = Reader(bytes(raw))
        r.byte(); r.nat(); r.nat64()
        at_caller = r.pos
        r.principal()
        caller_end = r.pos
        tag = r.byte()
        parent_at = None
        if tag == 1:
            r.blob(); parent_at = r.pos - 32
        r.nat(); version = r.nat8(); body = r.blob()
        return at_caller, caller_end, parent_at, r.pos, log_reader.read_command(version, body)

    target = None
    for i in order:
        at_caller, caller_end, _, _, cmd = layout(raws[i])
        new = caller_of(i, bytes(raws[i][at_caller + 1:caller_end]), cmd)
        if new is not None:
            raws[i][at_caller:caller_end] = bytes([len(new)]) + new
            target = i
            break
    if target is None:
        return None
    prev = None
    for i in order:
        _, _, parent_at, pre, _ = layout(raws[i])
        if i > target and parent_at is not None:
            raws[i][parent_at:parent_at + 32] = prev
        if i >= target:
            raws[i][pre:pre + 32] = hash_with_domain(log_reader.BLOCK_DOMAIN, bytes(raws[i][:pre]))
        prev = bytes(raws[i][pre:pre + 32])
    # every block from the moved one, written again in parts no wider than the export's own
    rewritten = {}
    for i in order:
        if i < target:
            continue
        hx = bytes(raws[i]).hex()
        rewritten[i] = ["block: %d %d %s" % (i, k, hx[at:at + width]) for k, at in enumerate(range(0, len(hx), width))]
    out, emitted = [], set()
    for line in lines:
        if line.startswith("block: "):
            i = int(line.split(None, 2)[1])
            if i in rewritten:
                if i not in emitted:
                    out.extend(rewritten[i]); emitted.add(i)
                continue
        if line.startswith("tip: "):
            line = "tip: " + prev.hex()
        out.append(line)
    lines[:] = out
    return target


# THE READ METHOD'S PAGES: each mutation decodes one page, changes one thing and writes it back as the one spelling of
# what it now holds, in parts as the export prints it, so the decoder accepts it and only the property named can catch it.
READ_PAGE_MUTATIONS = ("read-page-field", "read-page-row-dropped", "read-page-tip", "read-page-walk-cut",
                       "read-page-company")


def _read_pages(lines):
    pages = {}
    for n, line in enumerate(lines):
        if line.startswith("read_page: "):
            _, seq, part, h = line.split(None, 3)
            pages.setdefault(int(seq), []).append((int(part), n, h.strip()))
    return {seq: ([n for _, n, _ in sorted(ps)], "".join(h for _, _, h in sorted(ps))) for seq, ps in pages.items()}


def _mutate_read_page(lines, what):
    sys.path.insert(0, __import__("os").path.join(__import__("os").path.dirname(__import__("os").path.abspath(__file__)), "..", "integration", "oracle"))
    import read_page
    pages = _read_pages(lines)
    decoded = {seq: read_page.decode(bytes.fromhex(h)) for seq, (_, h) in pages.items()}
    target = None
    if what == "read-page-field":
        # an account's name: this reader keeps it under the declaration's name
        target = next(seq for seq, p in sorted(decoded.items()) if p["kind"] == "account" and p["rows"])
        decoded[target]["rows"][0][1]["name"] += "x"
    elif what == "read-page-row-dropped":
        # a punch left out of the last page of its walk, the walk otherwise whole
        target = next(seq for seq, p in sorted(decoded.items()) if p["kind"] == "punch" and len(p["rows"]) > 1 and p["next"] is None)
        decoded[target]["rows"].pop()
    elif what == "read-page-tip":
        target = sorted(decoded)[len(decoded) // 2]
        t = bytearray(decoded[target]["tip"])
        t[0] ^= 1
        decoded[target]["tip"] = bytes(t)
    elif what == "read-page-walk-cut":
        # the first page of a walk of more than one page, made to say the walk ends there
        target = next(seq for seq, p in sorted(decoded.items()) if p["next"] is not None)
        decoded[target]["next"] = None
    elif what == "read-page-company":
        # a department of company 1 shown in the page of company 1 as company 2's
        target = next(seq for seq, p in sorted(decoded.items()) if p["kind"] == "department" and p["companyId"] == 1 and p["rows"])
        decoded[target]["rows"][0][1]["companyId"] = 2
    at, h = pages[target][0], read_page.encode(decoded[target]).hex()
    new = ["read_page: %d %d %s" % (target, k, h[i:i + 256]) for k, i in enumerate(range(0, len(h), 256))]
    keep = set(at)
    out = []
    for n, line in enumerate(lines):
        if n == at[0]:
            out.extend(new)
        elif n not in keep:
            out.append(line)
    if what == "read-page-row-dropped":
        out = [("count: read page rows printed = %d" % (int(l.rsplit("=", 1)[1]) - 1)) if l.startswith("count: read page rows printed = ") else l for l in out]
    return out


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    src, dst, what = sys.argv[1], sys.argv[2], sys.argv[3]
    lines = open(src, encoding="utf-8").read().splitlines()

    # a block is emitted in PARTS (`block: <index> <part> <hex>`), so the map is from a block's
    # index to the line holding its FIRST part - mutating any one part corrupts the block, and
    # taking the first keeps the offsets in `body` meaningful.
    idx = {}
    for n, line in enumerate(lines):
        if line.startswith("block: "):
            _, num, part, _hex = line.split(None, 3)
            if int(part) == 0:
                idx[int(num)] = n

    if not idx:
        print("mutate_log: no blocks in " + src)
        return 2
    target = sorted(idx)[len(idx) // 2]

    if what == "body":
        n = idx[target]
        _, num, part, h = lines[n].split(None, 3)
        lines[n] = "block: %s %s %s" % (num, part, rot(h, 40))
    elif what == "hash":
        # the stored hash is the 32 bytes after the preimage, so it is the last 64 hex characters of
        # the block's LAST part
        last = max(n for n, line in enumerate(lines)
                   if line.startswith("block: %d " % target))
        _, num, part, h = lines[last].split(None, 3)
        lines[last] = "block: %s %s %s" % (num, part, rot(h, len(h) - 12))
    elif what == "swap":
        # swap the first parts of two blocks: each block's bytes then belong to the other index
        a, b = idx[target], idx[target + 1]
        ha = lines[a].split(None, 3)[3]
        hb = lines[b].split(None, 3)[3]
        pa = lines[a].split(None, 3)[2]
        pb = lines[b].split(None, 3)[2]
        lines[a] = "block: %d %s %s" % (target, pa, hb)
        lines[b] = "block: %d %s %s" % (target + 1, pb, ha)
    elif what == "drop":
        lines = [line for line in lines if not line.startswith("block: %d " % target)]
    elif what == "payslip":
        # the contract's own reported figure, moved by one minor unit. Not a corruption of the log - 
        # the log still verifies - but a claim about it that the recomputation contradicts, which is
        # the fault the figure-by-figure comparison exists for.
        done = False
        for n, line in enumerate(lines):
            if line.startswith("payslip: ") and not done:
                parts = line.split()
                parts[2] = str(int(parts[2]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no payslip line to change")
            return 2
    elif what in ("quant", "picking-value"):
        # the contract's own reported stock - a quant's quantity, or a validated picking's value - 
        # moved by one thousandth or one minor unit; the log still verifies, and the refold must
        # contradict the figure
        prefix, field = ("quant: ", 6) if what == "quant" else ("picking: ", 3)
        done = False
        for n, line in enumerate(lines):
            if line.startswith(prefix) and not done and (what == "quant" or line.split()[2] == "done"):
                parts = line.split()
                parts[field] = str(int(parts[field]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no %s line to change" % what)
            return 2
    elif what == "campaign-winner":
        # the contract's own reported winner, flipped. The log still verifies; the reader's own
        # application of the recorded rule must contradict the letter.
        done = False
        for n, line in enumerate(lines):
            if line.startswith("campaign: ") and not done:
                parts = line.split()
                parts[3] = {"a": "b", "b": "a", "none": "a"}[parts[3]]
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no campaign line to change")
            return 2
    elif what == "close-result":
        # the contract's own reported result of the close, moved by one minor unit. The log still
        # verifies; the reader's own refold of the sweep must contradict the figure.
        done = False
        for n, line in enumerate(lines):
            if line.startswith("close: ") and not done:
                parts = line.split()
                parts[8] = str(int(parts[8]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no close line to change")
            return 2
    elif what == "statement-figure":
        # the contract's own reported statement total, moved by one minor unit; the reader's refold
        # of the statement over its window must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("statement: ") and not done:
                parts = line.split()
                parts[10] = str(int(parts[10]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no statement line to change")
            return 2
    elif what == "deferral-part":
        # the contract's own reported first recognition of a deferral, moved by one minor unit; the
        # reader's own schedule arithmetic must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("deferral: ") and not done and len(line.split()) >= 12:
                parts = line.split()
                parts[11] = str(int(parts[11]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no deferral line with a posted part to change")
            return 2
    elif what == "revaluation-difference":
        # the contract's own reported unrealised difference, moved by one minor unit; the reader's
        # own arithmetic under the declared exponents and rounding must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("revaluation: ") and not done:
                parts = line.split()
                parts[9] = str(int(parts[9]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no revaluation line to change")
            return 2
    elif what == "asset-charge":
        # one month's charge on an asset, moved by one minor unit; the reader's own schedule - what
        # is left over the months that are left - must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("asset: ") and not done:
                parts = line.split()
                if len(parts) >= 15:
                    parts[14] = str(int(parts[14]) + 1)
                    lines[n] = " ".join(parts)
                    done = True
        if not done:
            print("mutate_log: there is no asset line with a charge to change")
            return 2
    elif what == "claim-amount":
        # one rate line's amount on a claim, moved by one minor unit; the reader's own pricing from
        # the rate it finds in force on that day must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("claim: ") and not done:
                parts = line.split()
                tail = parts[7:]
                for i in range(0, len(tail), 6):
                    if tail[i + 1] != "receipted" and not done:
                        parts[7 + i + 4] = str(int(parts[7 + i + 4]) + 1)
                        lines[n] = " ".join(parts)
                        done = True
        if not done:
            print("mutate_log: there is no claim line priced by a rate to change")
            return 2
    elif what == "payment-hash":
        # the fingerprint of a payment's pacs.008, one hex nibble moved; the reader's own rebuild of
        # the message from the rows must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("payment: ") and not done:
                parts = line.split()
                h = parts[7]
                parts[7] = ("0" if h[0] != "0" else "1") + h[1:]
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no payment line to change")
            return 2
    elif what == "camt-amount":
        # one line of a statement the bank sent, its amount moved by one minor unit; the reader's own
        # reading of the message must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("camt: ") and not done:
                parts = line.split()
                if len(parts) >= 15:
                    parts[12] = str(int(parts[12]) + 1)
                    lines[n] = " ".join(parts)
                    done = True
        if not done:
            print("mutate_log: there is no camt line with an entry to change")
            return 2
    elif what == "credit-interest":
        # an open item's interest as the contract fixed it, one piastre up; the reader's own interest
        # arithmetic over the same rows and days must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("credit: ") and not done:
                parts = line.split()
                if int(parts[14]) > 0:
                    parts[14] = str(int(parts[14]) + 1)
                    lines[n] = " ".join(parts)
                    done = True
        if not done:
            print("mutate_log: there is no credit line with interest to change")
            return 2
    elif what == "consolidation-figure":
        # a consolidation's total debits as the contract fixed them, one piastre up; the reader's own
        # fold of the member statements and the eliminations must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("consolidation: ") and not done:
                parts = line.split()
                parts[13] = str(int(parts[13]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no consolidation line to change")
            return 2
    elif what == "maintenance-downtime":
        # a work order's downtime as the contract fixed it, one day up; the reader's own fold of the
        # sign-off, and the equipment's total summed from its rows, must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("maintenance: ") and not done:
                parts = line.split()
                if int(parts[10]) > 0:
                    parts[10] = str(int(parts[10]) + 1)
                    lines[n] = " ".join(parts)
                    done = True
        if not done:
            print("mutate_log: there is no maintenance line with downtime to change")
            return 2
    elif what == "quality-verdict":
        # a check's verdict as the contract fixed it, flipped; the reader's own fold of the check
        # recorded on the log must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("quality: ") and not done:
                parts = line.split()
                parts[6] = "0" if parts[6] == "1" else "1"
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no quality line to change")
            return 2
    elif what == "ticket-clock":
        # a ticket's resolution deadline as the contract fixed it, one day later; the reader's own
        # walk over the company's working week and holidays must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("ticket: ") and not done:
                parts = line.split()
                parts[9] = str(int(parts[9]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no ticket line to change")
            return 2
    elif what == "visit-labour":
        # an invoiced visit's labour minutes as the contract fixed them, one more; the reader's own sum of
        # the task's approved time entries must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("visit: ") and not done:
                parts = line.split()
                if parts[5] == "invoiced":
                    parts[11] = str(int(parts[11]) + 1)
                    lines[n] = " ".join(parts)
                    done = True
        if not done:
            print("mutate_log: there is no invoiced visit line to change")
            return 2
    elif what == "booking-slot":
        # a booking's start as the contract fixed it, a minute earlier; the reader's own fold of the
        # booking on the log must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("booking: ") and not done:
                parts = line.split()
                parts[4] = str(int(parts[4]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no booking line to change")
            return 2
    elif what == "proration-amount":
        # a proration's amount as the contract fixed it, one minor unit more; the reader's own
        # arithmetic over the calendar's days must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("subinvoice: ") and not done:
                parts = line.split()
                if parts[4] == "proration":
                    parts[7] = str(int(parts[7]) + 1)
                    lines[n] = " ".join(parts)
                    done = True
        if not done:
            print("mutate_log: there is no proration line to change")
            return 2
    elif what == "rental-late-days":
        # a returned rental's late days as the contract fixed them, one more; the reader's own count
        # from the agreed day and the day of return must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("rental: ") and not done:
                parts = line.split()
                if parts[6] == "returned":
                    parts[9] = str(int(parts[9]) + 1)
                    lines[n] = " ".join(parts)
                    done = True
        if not done:
            print("mutate_log: there is no returned rental line to change")
            return 2
    elif what == "till-takings":
        # a posted till session's cash takings as the contract fixed them, one minor unit more; the
        # reader's own sum over the session's sales must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("pos_session: ") and not done:
                parts = line.split()
                if parts[3] == "posted":
                    parts[8] = str(int(parts[8]) + 1)
                    lines[n] = " ".join(parts)
                    done = True
        if not done:
            print("mutate_log: there is no posted till session line to change")
            return 2
    elif what == "bill-share":
        # a share of a split bill as the contract fixed it, one minor unit more; the reader's own split
        # of the sale's total by the rule must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("rst_share: ") and not done:
                parts = line.split()
                parts[5] = str(int(parts[5]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no bill share line to change")
            return 2
    elif what == "web-paid":
        # a web order's payment as the contract fixed it, one minor unit more; the reader's own total of
        # the order it paid for must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("web_order: ") and not done:
                parts = line.split()
                parts[6] = str(int(parts[6]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no web order line to change")
            return 2
    elif what == "page-fingerprint":
        # a page version's fingerprint as the contract published it, one hex digit turned; the reader's
        # own hash of the chunks on the log must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("site_version: ") and not done:
                parts = line.split()
                h = parts[6]
                parts[6] = ("0" if h[0] != "0" else "1") + h[1:]
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no page version line to change")
            return 2
    elif what == "post-day":
        # a post's day as the contract fixed it, one later; the day of the block it was published at,
        # which the reader reads from the log, must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("blog_post: ") and not done:
                parts = line.split()
                parts[4] = str(int(parts[4]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no post line to change")
            return 2
    elif what == "reply-count":
        # a topic's count of replies as the contract fixed it, one more; the reader's own count of the replies
        # on the log must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("forum_topic: ") and not done:
                parts = line.split()
                parts[8] = str(int(parts[8]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no topic line to change")
            return 2
    elif what == "chat-words":
        # a conversation's count of words as the contract fixed it, one more; the reader's own count of the
        # messages on the log must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("chat_conversation: ") and not done:
                parts = line.split()
                parts[9] = str(int(parts[9]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no conversation line to change")
            return 2
    elif what == "participant-step":
        # a participant's next step as the contract fixed it, one further; the reader's own walk of the runs
        # must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("auto_participant: ") and not done:
                parts = line.split()
                parts[4] = str(int(parts[4]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no participant line to change")
            return 2
    elif what == "sms-sent":
        # a text mailing's count of copies sent as the contract fixed it, one more; the reader's own recount of the
        # copies by state must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("sms_mailing: ") and not done:
                parts = line.split()
                parts[7] = str(int(parts[7]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no text mailing line to change")
            return 2
    elif what == "post-attempts":
        # a social post's count of attempts as the contract fixed it, one more; the reader's own queue, from which
        # it re-derives every claim, must contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("social_post: ") and not done:
                parts = line.split()
                parts[6] = str(int(parts[6]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no social post line to change")
            return 2
    elif what == "ticket-seats":
        # a ticket's seats as the contract fixed them, one more; the reader's own sale through its order fold and the
        # event's seats recounted from its tickets contradict it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("event_ticket: ") and not done:
                parts = line.split()
                parts[4] = str(int(parts[4]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no ticket line to change")
            return 2
    elif what == "survey-tally":
        # a question's tally as the contract counted it, the first count one more; the reader's own recount from the
        # answer rows it folded contradicts it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("survey_tally: ") and not done:
                parts = line.split()
                parts[2] = str(int(parts[2]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no survey tally line to change")
            return 2
    elif what == "review-final":
        # a review's final rating as the contract printed it, one more; the reader reads the final rating by the rule and
        # never from the row, so its own reading contradicts it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("review: ") and not done:
                parts = line.split()
                parts[9] = str(int(parts[9]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no review line to change")
            return 2
    elif what == "cert-valid":
        # a certification's validity as the contract read it on the day it names, flipped; the reader reads the validity
        # against the calendar itself and contradicts it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("certification: ") and not done:
                parts = line.split()
                parts[8] = "0" if parts[8] == "1" else "1"
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no certification line to change")
            return 2
    elif what == "vested-shares":
        # a grant's vested figure as the contract read it from the schedule on the day it names, moved by one share; the
        # reader computes the schedule itself with its own calendar and contradicts it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("equity_grant: ") and not done:
                parts = line.split()
                parts[9] = str(int(parts[9]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no equity grant line to change")
            return 2
    elif what == "fuel-amount":
        # a fuelling's amount moved by a minor unit; the reader multiplies the litres by the price itself and contradicts it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("fuel_log: ") and not done:
                parts = line.split()
                parts[6] = str(int(parts[6]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no fuelling line to change")
            return 2
    elif what == "sweep-acted":
        # an announcement sweep's acted moved by one; the reader recounts it from the notifications the sweep wrote and contradicts it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("announcement_sweep: ") and not done:
                parts = line.split()
                parts[6] = str(int(parts[6]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no announcement sweep line to change")
            return 2
    elif what == "audience-recipient":
        # a notification a sweep wrote moved onto the membership before it; the reader computed the audience itself and
        # wrote that notification to somebody else
        done = False
        for n, line in enumerate(lines):
            if line.startswith("notification: ") and not done:
                parts = line.split()
                if int(parts[8]) != 0 and int(parts[2]) > 1:
                    parts[2] = str(int(parts[2]) - 1)
                    lines[n] = " ".join(parts)
                    done = True
        if not done:
            print("mutate_log: there is no swept notification to move")
            return 2
    elif what == "kb-category":
        # a published article's category moved to the next one; the reader re-reads it from the version the article
        # names as published and contradicts it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("kb_article: ") and not done:
                parts = line.split()
                if int(parts[6]) != 0:
                    parts[3] = str(int(parts[3]) % 7 + 1)
                    lines[n] = " ".join(parts)
                    done = True
        if not done:
            print("mutate_log: there is no published article to change")
            return 2
    elif what == "run-members":
        # a published run of the figures counting one member more; the reader walks the members itself and
        # contradicts it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("gov_run: ") and not done:
                parts = line.split()
                figures = parts[7].split(",")
                figures[5] = str(int(figures[5]) + 1)
                parts[7] = ",".join(figures)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no run of the figures to change")
            return 2
    elif what == "behalf-moved":
        # a step decided under a delegation reported as decided in the delegate's own name; the reader holds every
        # step to the role and the delegations standing on its day and contradicts it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("wf_decision: ") and not done:
                parts = line.split()
                if parts[4] != parts[5]:
                    parts[5] = parts[4]
                    lines[n] = " ".join(parts)
                    done = True
        if not done:
            print("mutate_log: there is no step decided on somebody's behalf")
            return 2
    elif what == "studio-fingerprint":
        # a studio value reported under a fingerprint one hex digit off; the reader recomputes every value's
        # fingerprint from the bytes its command carried and contradicts it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("studio_value: ") and not done:
                parts = line.split()
                h = parts[-1]
                parts[-1] = ("1" if h[0] != "1" else "2") + h[1:]
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no studio value to change")
            return 2
    elif what == "studio-values":
        # a studio field reported holding one value more than it does; the reader re-adds every field's values from
        # the rows it folded and contradicts it
        done = False
        for n, line in enumerate(lines):
            if line.startswith("studio_field: ") and not done:
                parts = line.split()
                parts[12] = str(int(parts[12]) + 1)
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no studio field to change")
            return 2
    elif what == "studio-outside":
        # the contract's count of values outside the rule in force reported as none; the reader re-derives it from
        # the rules and values it folded and contradicts it
        done = False
        prefix = "count: studio values outside the rule in force = "
        for n, line in enumerate(lines):
            if line.startswith(prefix) and not done:
                lines[n] = prefix + str(int(line[len(prefix):]) + 1)
                done = True
        if not done:
            print("mutate_log: there is no count of studio values outside the rule in force")
            return 2
    elif what in PLM_MUTATIONS or what in ESG_MUTATIONS or what in DRAFT_MUTATIONS:
        # one field of one product-lifecycle or ESG row moved. The line is split on single spaces and joined the same way, so
        # an empty text field (a change's note) stays empty and the line differs only in the field moved.
        prefix, field, change = PLM_MUTATIONS[what] if what in PLM_MUTATIONS else ESG_MUTATIONS[what] if what in ESG_MUTATIONS else DRAFT_MUTATIONS[what]
        done = False
        for n, line in enumerate(lines):
            if line.startswith(prefix + ": ") and not done:
                parts = line.rstrip("\n").split(" ")
                parts[field] = change(parts[field])
                lines[n] = " ".join(parts) + ("\n" if line.endswith("\n") else "")
                done = True
        if not done:
            print("mutate_log: there is no %s row to change" % prefix)
            return 2
    elif what in CONTROLS_MUTATIONS or what in VOIP_MUTATIONS:
        # one figure of one controls row moved - the reader restates every row from the log alone and compares it
        # whole, so each of these is a different property it claims: the posting record derived from the act, the
        # criteria re-decided, the count recounted, the digit test recomputed, the seal rehashed, the confirmation's
        # block, the four eyes on a review
        prefix, field, change = CONTROLS_MUTATIONS[what] if what in CONTROLS_MUTATIONS else VOIP_MUTATIONS[what]
        done = False
        for n, line in enumerate(lines):
            if line.startswith(prefix + ": ") and not done:
                parts = line.split()
                parts[field] = change(parts[field])
                lines[n] = " ".join(parts)
                done = True
        if not done:
            print("mutate_log: there is no %s row to change" % prefix)
            return 2
    elif what in AUDIT_MUTATIONS:
        # one entry of the index moved or left out, from the middle of its table - the reader recomputes both tables
        # from the blocks it decodes and compares them both ways, entry by entry
        prefix, field, change = AUDIT_MUTATIONS[what]
        rows = [n for n, line in enumerate(lines) if line.startswith(prefix + ": ")]
        if not rows:
            print("mutate_log: there is no %s row to change" % prefix)
            return 2
        n = rows[len(rows) // 2]
        if field is None:
            del lines[n]
        else:
            parts = lines[n].split(" ")
            parts[field] = change(parts[field])
            lines[n] = " ".join(parts)
    elif what in ("codec-rich-moved", "codec-plain-dropped"):
        # one family's sample as the contract encoded it: the rich sample of a family no hand reader states with its
        # last byte moved (the reader reads it back by its declared type, value for value), or a plain sample left out
        kind = "rich" if what == "codec-rich-moved" else "plain"
        rows = [n for n, line in enumerate(lines) if line.startswith("codec_sample: %s " % kind)]
        if not rows:
            print("mutate_log: there is no %s codec sample" % kind)
            return 2
        n = rows[160] if len(rows) > 160 else rows[len(rows) // 2]
        if what == "codec-plain-dropped":
            del lines[n]
        else:
            head, h = lines[n].rsplit(" ", 1)
            last = (int(h[-2:], 16) + 1) % 256
            lines[n] = head + " " + h[:-2] + "%02x" % last
    elif what in ("requirement-quantity", "lead-planned"):
        # one figure the contract printed and the reader recomputes from the log: the quantity of the explosion's
        # deepest row (a component's quantity per the parent's, on a bill of two levels), or the weighted forecast
        # of the opportunity whose figure truncates (9_999 at 33.33 per cent) - each moved by one
        if what == "requirement-quantity":
            rows = [n for n, line in enumerate(lines) if line.startswith("mrp_requirement: ")]
            field = 7
            rows = sorted(rows, key=lambda n: -int(lines[n].split()[6]))
        else:
            rows = [n for n, line in enumerate(lines) if line.startswith("crm_lead: ") and line.split()[10] == "3333"]
            field = 12
        if not rows:
            print("mutate_log: there is no row for %s" % what)
            return 2
        parts = lines[rows[0]].rstrip("\n").split(" ")
        parts[field] = str(int(parts[field]) + 1)
        lines[rows[0]] = " ".join(parts)
    elif what in ("activity-unreminded", "lead-score"):
        # what the reminder sweep and the scoring run wrote, as the contract printed it: an activity the sweep reminded
        # shown as never reminded, or the score of a lead the run scored moved by one
        if what == "activity-unreminded":
            rows = [n for n, line in enumerate(lines) if line.startswith("crm_activity: ") and line.split()[9] != "0"]
            field, to = 9, lambda v: "0"
        else:
            rows = [n for n, line in enumerate(lines) if line.startswith("crm_lead: ") and line.split()[18] != "0"]
            field, to = 17, lambda v: str(int(v) + 1)
        if not rows:
            print("mutate_log: there is no row for %s" % what)
            return 2
        parts = lines[rows[0]].split(" ")
        parts[field] = to(parts[field])
        lines[rows[0]] = " ".join(parts)
    elif what == "gate-sender-moved":
        # an act a company's administrator sent, recorded as sent by a principal no company has admitted, on a
        # chain made whole again; the reader holds every block's sender to its own holders table and refuses it
        stranger = bytes([0xEE] * 29)
        def caller_of(i, caller, cmd):
            return stranger if cmd["family"] == "createDepartment" and len(caller) == 29 else None
        if _resend(lines, caller_of) is None:
            print("mutate_log: there is no department created by a principal of 29 bytes")
            return 2
    elif what == "gate-auditor-acted":
        # the first department the boss creates after the company's auditor is admitted (test/Export.export.mo,
        # who(202)), recorded as the auditor's on a chain made whole again: the auditor stands in the company and
        # holds no act, so the reader refuses the block for the gate's reason, naming the auditor's role
        auditor = bytes([1, 0, 202] + [0] * 26)
        admitted = [False]
        def caller_of(i, caller, cmd):
            if cmd["family"] == "admitMember" and bytes(cmd["subject"]) == auditor:
                admitted[0] = True
                return None
            return auditor if admitted[0] and cmd["family"] == "createDepartment" else None
        if _resend(lines, caller_of) is None:
            print("mutate_log: there is no department created after the auditor's admission")
            return 2
    elif what == "draft-acceptor-moved":
        # the boss's acceptance of the department drafted for the boss (test/Export.export.mo, the plant's first
        # draft) recorded as the plant's employee's (who(3003)), on a chain made whole again: the employee stands in
        # the company, so the gate lets an acceptance through, but the draft was not made for them and they hold
        # createDepartment by no role, so the draft reader refuses the acceptance
        employee = bytes([1, 3003 // 256, 3003 % 256] + [0] * 26)
        def caller_of(i, caller, cmd):
            return employee if cmd["family"] == "acceptDraft" else None
        if _resend(lines, caller_of) is None:
            print("mutate_log: there is no acceptance of a draft")
            return 2
    elif what == "idea-author-votes":
        # the first vote on an idea (test/Export.export.mo: who(111)'s on who(110)'s idea) recorded as the idea's
        # author's, on a chain made whole again: the author is a member, so the gate lets a vote through, and only the
        # forum reader's rule - nobody votes for their own idea - can refuse it
        author = bytes([1, 0, 110] + [0] * 26)
        def caller_of(i, caller, cmd):
            return author if cmd["family"] == "voteTopic" else None
        if _resend(lines, caller_of) is None:
            print("mutate_log: there is no vote on an idea")
            return 2
    elif what == "event-answer-moved":
        # the first answer to a members' event (test/Export.export.mo: who(121) attending the lunch) recorded as
        # who(122)'s, on a chain made whole again: who(122) is a member, so the gate admits it, and only the events
        # reader's rule - one answer per member, the same answer never twice - refuses who(122)'s own attending after it
        other = bytes([1, 0, 122] + [0] * 26)
        def caller_of(i, caller, cmd):
            return other if cmd["family"] == "respondToEvent" else None
        if _resend(lines, caller_of) is None:
            print("mutate_log: there is no answer to a members' event")
            return 2
    elif what == "equipment-self-handed":
        # the first hand-over of equipment (test/Export.export.mo: the laptop handed by the boss to who(106)) recorded as
        # sent by who(106), on a chain made whole again: who(106) is a member, so the gate admits it, and only the
        # maintenance reader's rule - nobody hands themselves equipment - refuses it
        other = bytes([1, 0, 106] + [0] * 26)
        def caller_of(i, caller, cmd):
            return other if cmd["family"] == "assignEquipment" and bytes(cmd["facts"]["subject"]) == other else None
        if _resend(lines, caller_of) is None:
            print("mutate_log: there is no hand-over of equipment to who(106)")
            return 2
    elif what == "gate-claim-moved":
        # the platform operator's claim recorded as another principal's, on a chain made whole again: the claim is
        # anyone's to make while it is open, so the reader must find the fault later - the first platform act the
        # real claimant sends is now a stranger's
        def caller_of(i, caller, cmd):
            if cmd["family"] != "claimPlatformOperator":
                return None
            # a principal of 29 bytes no company has admitted, whatever the claimant's own length
            return bytes([0xEE] * 29) if caller != bytes([0xEE] * 29) else bytes([0xED] * 29)
        if _resend(lines, caller_of) is None:
            print("mutate_log: there is no claim of the platform operator")
            return 2
    elif what in READ_PAGE_MUTATIONS:
        lines = _mutate_read_page(lines, what)
    elif what == "tip":
        done = False
        for n, line in enumerate(lines):
            if line.startswith("tip: "):
                lines[n] = "tip: " + rot(line.split(None, 1)[1], 0)
                done = True
        if not done:
            print("mutate_log: there is no tip line to change")
            return 2
    else:
        print("mutate_log: unknown mutation " + what)
        return 2

    with open(dst, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
