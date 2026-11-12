#!/usr/bin/env python3
"""The log reader: reconstruct the store from the log's bytes, independently of the contract.

This is the check that makes "the state is a pure function of the log" verifiable by someone who
does not run the contract. It reads the raw blocks, verifies every hash and every link, decodes
every command with an independently written codec, folds them with independently written rules, and
prints the store it arrives at. The contract's battery prints the same figures, and the gate
compares them.

WHAT IT VERIFIES, in order:

  1. every block's stored hash equals SHA-256( text(domain) || preimage ) - so a corrupted block is
     never folded;
  2. every block's index is its position, and its parent hash is the previous block's hash - so a
     reordered or spliced log is caught rather than folded into a plausible state;
  3. the last block's hash equals the tip the contract published;
  4. every command decodes under the version the BLOCK recorded, never under a current version - a
     reader that assumed the current version would silently misread every older block;
  5. the fold's own rules refuse what the contract refuses: a duplicate slug, an over-long slug, an
     empty name. A log should never contain a command the fold refuses - it was accepted once - so
     any refusal here is reported as a fault, not skipped.

Input: lines of `block: <index> <part> <hex>` on stdin or in a file, and `tip: <hex>`. A block is
emitted in parts because the contract's `Debug.print` writes at most 512 characters per call and
truncates silently; the parts of one block are joined in order before anything is decoded.

Usage:  log_reader.py [FILE] [--expect-companies N] [--expect-fingerprint HEX] [--json]

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from canonical import Reader, hash_with_domain, write_nat, write_text  # noqa: E402
import hr  # noqa: E402
import orders  # noqa: E402
import stock  # noqa: E402
import crm  # noqa: E402
import finance  # noqa: E402
import evidence  # noqa: E402
import expenses  # noqa: E402
import payments  # noqa: E402
import statements  # noqa: E402
import credit  # noqa: E402
import consolidation  # noqa: E402
import manufacturing  # noqa: E402
import maintenance  # noqa: E402
import quality  # noqa: E402
import helpdesk  # noqa: E402
import projects  # noqa: E402
import fieldservice  # noqa: E402
import appointments  # noqa: E402
import subscriptions  # noqa: E402
import rental  # noqa: E402
import pos  # noqa: E402
import rst  # noqa: E402
import web  # noqa: E402
import website  # noqa: E402
import blog  # noqa: E402
import forum  # noqa: E402
import chat  # noqa: E402
import automation  # noqa: E402
import sms  # noqa: E402
import social  # noqa: E402
import events  # noqa: E402
import survey  # noqa: E402
import appraisals  # noqa: E402
import learning  # noqa: E402
import compensation  # noqa: E402
import read_compare  # noqa: E402
import fleet  # noqa: E402
import discuss  # noqa: E402
import knowledge  # noqa: E402
import governance  # noqa: E402
import workflow  # noqa: E402
import studio  # noqa: E402
import controls  # noqa: E402
import voip  # noqa: E402
import plm  # noqa: E402
import esg  # noqa: E402
import draft  # noqa: E402
import gate  # noqa: E402
import audit  # noqa: E402
import typed_codec  # noqa: E402

# EVERY FAMILY BY ITS DECLARED TYPE: the reader's own statement of the wire format, read from the command type and
# not from the contract's encoder; every block is held to it, and the families no hand reader states are read by it
CODEC = typed_codec.Codec()
import accounting  # noqa: E402
import payroll  # noqa: E402

BLOCK_DOMAIN = "QORZA-BLOCK-v1"
CMD_DOMAIN_PREFIX = "QORZA-CMD"

FAMILY_BY_TAG = {0: "bootstrapCompany"}
SLUG_BYTES = 32


def zag(n: int) -> int:
    """Un-zigzag: even encodes a non-negative, odd encodes a negative."""
    return n // 2 if n % 2 == 0 else -((n + 1) // 2)


def read_facts(r: Reader) -> dict:
    """CompanyFacts, version 1:  text name, text slug, text orgCode,
       opt zigzag-nat geoLat, opt zigzag-nat geoLon, nat radius, bool requireLocation."""
    name = r.text()
    slug = r.text()
    org = r.text()
    lat = r.opt_nat()
    lon = r.opt_nat()
    radius = r.nat()
    require = r.bool()
    return {
        "name": name, "slug": slug, "orgCode": org,
        "geoLat": None if lat is None else zag(lat),
        "geoLon": None if lon is None else zag(lon),
        "geoRadiusMetres": radius, "geoRequireLocation": require,
    }


def read_command(version: int, body: bytes) -> dict:
    """A command under a NAMED version. Version 1's body is a family tag byte then the payload, and
    the body must be consumed to the end - a body with bytes left over is not this version's
    command, and accepting the prefix would return a command nobody wrote."""
    if version != 1:
        raise ValueError("no decoder for command version %d" % version)
    r = Reader(body)
    tag = r.byte()
    # A TAG AT OR PAST 255 IS ESCAPED: 0xFF then the offset past 255; at or past 510 it is 0xFF 0xFF
    # then the offset past 510 in two bytes, as `Encoding.putTag` writes it.
    if tag == 255:
        second = r.byte()
        tag = 255 + second if second < 255 else 510 + int.from_bytes(r.take(2), "big")
    if tag == 0:
        cmd = {"family": "bootstrapCompany", "facts": read_facts(r)}
    elif tag in hr.READERS:
        cmd = hr.read_hr_command(tag, r)
    elif tag in orders.READERS:
        cmd = orders.read_order_command(tag, r)
    elif tag in stock.READERS:
        cmd = stock.read_stock_command(tag, r)
    elif tag in finance.READERS:
        cmd = finance.read_finance_command(tag, r)
    elif tag in evidence.READERS:
        cmd = evidence.read_evidence_command(tag, r)
    elif tag in crm.READERS:
        cmd = crm.read_crm_command(tag, r)
    elif tag in expenses.READERS:
        cmd = expenses.read_expense_command(tag, r)
    elif tag in payments.READERS:
        cmd = payments.read_payment_command(tag, r)
    elif tag in statements.READERS:
        cmd = statements.read_statement_command(tag, r)
    elif tag in credit.READERS:
        cmd = credit.read_credit_command(tag, r)
    elif tag in consolidation.READERS:
        cmd = consolidation.read_consolidation_command(tag, r)
    elif tag in manufacturing.READERS:
        cmd = manufacturing.read_manufacturing_command(tag, r)
    elif tag in maintenance.READERS:
        cmd = maintenance.read_maintenance_command(tag, r)
    elif tag in quality.READERS:
        cmd = quality.read_quality_command(tag, r)
    elif tag in helpdesk.READERS:
        cmd = helpdesk.read_helpdesk_command(tag, r)
    elif tag in projects.READERS:
        cmd = projects.read_project_command(tag, r)
    elif tag in fieldservice.READERS:
        cmd = fieldservice.read_fieldservice_command(tag, r)
    elif tag in appointments.READERS:
        cmd = appointments.read_appointment_command(tag, r)
    elif tag in subscriptions.READERS:
        cmd = subscriptions.read_subscription_command(tag, r)
    elif tag in rental.READERS:
        cmd = rental.read_rental_command(tag, r)
    elif tag in pos.READERS:
        cmd = pos.read_pos_command(tag, r)
    elif tag in rst.READERS:
        cmd = rst.read_rst_command(tag, r)
    elif tag in web.READERS:
        cmd = web.read_web_command(tag, r)
    elif tag in website.READERS:
        cmd = website.read_site_command(tag, r)
    elif tag in blog.READERS:
        cmd = blog.read_blog_command(tag, r)
    elif tag in forum.READERS:
        cmd = forum.read_forum_command(tag, r)
    elif tag in chat.READERS:
        cmd = chat.read_chat_command(tag, r)
    elif tag in automation.READERS:
        cmd = automation.read_automation_command(tag, r)
    elif tag in sms.READERS:
        cmd = sms.read_sms_command(tag, r)
    elif tag in social.READERS:
        cmd = social.read_social_command(tag, r)
    elif tag in events.READERS:
        cmd = events.read_events_command(tag, r)
    elif tag in survey.READERS:
        cmd = survey.read_survey_command(tag, r)
    elif tag in appraisals.READERS:
        cmd = appraisals.read_appraisal_command(tag, r)
    elif tag in learning.READERS:
        cmd = learning.read_learning_command(tag, r)
    elif tag in compensation.READERS:
        cmd = compensation.read_compensation_command(tag, r)
    elif tag in fleet.READERS:
        cmd = fleet.read_fleet_command(tag, r)
    elif tag in discuss.READERS:
        cmd = discuss.read_discuss_command(tag, r)
    elif tag in knowledge.READERS:
        cmd = knowledge.read_knowledge_command(tag, r)
    elif tag in governance.READERS:
        cmd = governance.read_governance_command(tag, r)
    elif tag in workflow.READERS:
        cmd = workflow.read_workflow_command(tag, r)
    elif tag in studio.READERS:
        cmd = studio.read_studio_command(tag, r)
    elif tag in controls.READERS:
        cmd = controls.read_controls_command(tag, r)
    elif tag in voip.READERS:
        cmd = voip.read_voip_command(tag, r)
    elif tag in plm.READERS:
        cmd = plm.read_plm_command(tag, r)
    elif tag in esg.READERS:
        cmd = esg.read_esg_command(tag, r)
    elif tag in gate.READERS:
        cmd = gate.read_gate_command(tag, r)
    else:
        # A FAMILY NO HAND READER STATES is read by its declared type (typed_codec.py), whole: the fields the type
        # declares, in its order, each in its canonical form - and it must consume the body to the end
        fam, value = CODEC.decode(body)
        return {"family": fam, "byType": True, **(value if isinstance(value, dict) else {"value": value})}
    if not r.at_end():
        raise ValueError("%d byte(s) left after %s: this is not a version %d command"
                         % (r.remaining(), cmd["family"], version))
    return cmd


def command_bytes(version: int, cmd: dict) -> bytes:
    """Re-encode, so the command hash can be re-derived. A reader that can only decode cannot check
    that the bytes it read are the bytes the contract hashed."""
    if version != 1:
        raise ValueError("no encoder at version %d" % version)
    if cmd["family"] in orders.ENCODERS:
        return orders.order_command_bytes(cmd)
    if cmd["family"] in stock.ENCODERS:
        return stock.stock_command_bytes(cmd)
    if cmd["family"] in finance.ENCODERS:
        return finance.finance_command_bytes(cmd)
    if cmd["family"] in evidence.ENCODERS:
        return evidence.evidence_command_bytes(cmd)
    if cmd["family"] in crm.ENCODERS:
        return crm.crm_command_bytes(cmd)
    if cmd["family"] in expenses.ENCODERS:
        return expenses.expense_command_bytes(cmd)
    if cmd["family"] in payments.ENCODERS:
        return payments.payment_command_bytes(cmd)
    if cmd["family"] in statements.ENCODERS:
        return statements.statement_command_bytes(cmd)
    if cmd["family"] in credit.ENCODERS:
        return credit.credit_command_bytes(cmd)
    if cmd["family"] in consolidation.ENCODERS:
        return consolidation.consolidation_command_bytes(cmd)
    if cmd["family"] in manufacturing.ENCODERS:
        return manufacturing.manufacturing_command_bytes(cmd)
    if cmd["family"] in maintenance.ENCODERS:
        return maintenance.maintenance_command_bytes(cmd)
    if cmd["family"] in quality.ENCODERS:
        return quality.quality_command_bytes(cmd)
    if cmd["family"] in helpdesk.ENCODERS:
        return helpdesk.helpdesk_command_bytes(cmd)
    if cmd["family"] in projects.ENCODERS:
        return projects.project_command_bytes(cmd)
    if cmd["family"] in fieldservice.ENCODERS:
        return fieldservice.fieldservice_command_bytes(cmd)
    if cmd["family"] in appointments.ENCODERS:
        return appointments.appointment_command_bytes(cmd)
    if cmd["family"] in subscriptions.ENCODERS:
        return subscriptions.subscription_command_bytes(cmd)
    if cmd["family"] in rental.ENCODERS:
        return rental.rental_command_bytes(cmd)
    if cmd["family"] in pos.ENCODERS:
        return pos.pos_command_bytes(cmd)
    if cmd["family"] in rst.ENCODERS:
        return rst.rst_command_bytes(cmd)
    if cmd["family"] in web.ENCODERS:
        return web.web_command_bytes(cmd)
    if cmd["family"] in website.ENCODERS:
        return website.site_command_bytes(cmd)
    if cmd["family"] in blog.ENCODERS:
        return blog.blog_command_bytes(cmd)
    if cmd["family"] in forum.ENCODERS:
        return forum.forum_command_bytes(cmd)
    if cmd["family"] in chat.ENCODERS:
        return chat.chat_command_bytes(cmd)
    if cmd["family"] in automation.ENCODERS:
        return automation.automation_command_bytes(cmd)
    if cmd["family"] in sms.ENCODERS:
        return sms.sms_command_bytes(cmd)
    if cmd["family"] in social.ENCODERS:
        return social.social_command_bytes(cmd)
    if cmd["family"] in events.ENCODERS:
        return events.events_command_bytes(cmd)
    if cmd["family"] in survey.ENCODERS:
        return survey.survey_command_bytes(cmd)
    if cmd["family"] in appraisals.ENCODERS:
        return appraisals.appraisal_command_bytes(cmd)
    if cmd["family"] in learning.ENCODERS:
        return learning.learning_command_bytes(cmd)
    if cmd["family"] in compensation.ENCODERS:
        return compensation.compensation_command_bytes(cmd)
    if cmd["family"] in fleet.ENCODERS:
        return fleet.fleet_command_bytes(cmd)
    if cmd["family"] in discuss.ENCODERS:
        return discuss.discuss_command_bytes(cmd)
    if cmd["family"] in knowledge.ENCODERS:
        return knowledge.knowledge_command_bytes(cmd)
    if cmd["family"] in governance.ENCODERS:
        return governance.governance_command_bytes(cmd)
    if cmd["family"] in workflow.ENCODERS:
        return workflow.workflow_command_bytes(cmd)
    if cmd["family"] in studio.ENCODERS:
        return studio.studio_command_bytes(cmd)
    if cmd["family"] in controls.ENCODERS:
        return controls.controls_command_bytes(cmd)
    if cmd["family"] in voip.ENCODERS:
        return voip.voip_command_bytes(cmd)
    if cmd["family"] in plm.ENCODERS:
        return plm.plm_command_bytes(cmd)
    if cmd["family"] in esg.ENCODERS:
        return esg.esg_command_bytes(cmd)
    if cmd["family"] in gate.ENCODERS:
        return gate.gate_command_bytes(cmd)
    if cmd["family"] in hr.ACCOUNTING_ENCODERS:
        return hr.accounting_command_bytes(cmd)
    if cmd["family"] != "bootstrapCompany":
        raise ValueError("no encoder for %s at version %d" % (cmd["family"], version))
    f = cmd["facts"]
    out = bytearray([0])
    out += write_text(f["name"])
    out += write_text(f["slug"])
    out += write_text(f["orgCode"])
    for k in ("geoLat", "geoLon"):
        v = f[k]
        if v is None:
            out += b"\x00"
        else:
            out += b"\x01" + write_nat(v * 2 if v >= 0 else -v * 2 - 1)
    out += write_nat(f["geoRadiusMetres"])
    out += bytes([1 if f["geoRequireLocation"] else 0])
    return bytes(out)


def has_encoder(family: str) -> bool:
    return (family == "bootstrapCompany" or family in orders.ENCODERS or family in stock.ENCODERS
            or family in finance.ENCODERS or family in evidence.ENCODERS or family in hr.ACCOUNTING_ENCODERS
            or family in crm.ENCODERS or family in expenses.ENCODERS or family in payments.ENCODERS
            or family in statements.ENCODERS or family in credit.ENCODERS or family in consolidation.ENCODERS
            or family in manufacturing.ENCODERS or family in maintenance.ENCODERS or family in quality.ENCODERS
            or family in helpdesk.ENCODERS or family in projects.ENCODERS or family in fieldservice.ENCODERS
            or family in appointments.ENCODERS or family in subscriptions.ENCODERS or family in rental.ENCODERS
            or family in pos.ENCODERS or family in rst.ENCODERS or family in web.ENCODERS or family in website.ENCODERS or family in blog.ENCODERS or family in forum.ENCODERS or family in chat.ENCODERS or family in automation.ENCODERS or family in sms.ENCODERS or family in social.ENCODERS or family in events.ENCODERS or family in survey.ENCODERS or family in appraisals.ENCODERS or family in learning.ENCODERS or family in compensation.ENCODERS or family in fleet.ENCODERS or family in discuss.ENCODERS or family in knowledge.ENCODERS
            or family in governance.ENCODERS or family in workflow.ENCODERS or family in studio.ENCODERS
            or family in controls.ENCODERS or family in voip.ENCODERS or family in plm.ENCODERS or family in esg.ENCODERS
            or family in gate.ENCODERS)


def command_hash(version: int, cmd: dict) -> bytes:
    return hash_with_domain("%s-v%d" % (CMD_DOMAIN_PREFIX, version), command_bytes(version, cmd))


REENCODED = {"by hand": 0, "by type": 0}


def decode_block(index: int, raw: bytes) -> dict:
    """One stored block. The layout is codec version, index, timestamp, caller, opt parent hash,
    the event, then the 32-byte stored hash, then anything left is the trailer."""
    r = Reader(raw)
    codec_version = r.byte()
    if codec_version != 1:
        raise ValueError("block %d: codec version %d" % (index, codec_version))
    idx = r.nat()
    timestamp = r.nat64()
    caller = r.principal()
    parent = r.opt_blob()
    # the event: day, command version, command body
    day = r.nat()
    cmd_version = r.nat8()
    body = r.blob()
    cmd = read_command(cmd_version, body)
    # RE-ENCODED, AND REQUIRED TO BE THE BYTES THE CONTRACT HASHED. A reader that can only decode
    # cannot make that claim; one that re-encodes every family it knows an encoder for makes it on
    # every block.
    if has_encoder(cmd["family"]):
        again = command_bytes(cmd_version, cmd)
        if again != body:
            raise ValueError("block %d: %s re-encodes to different bytes (%d read, %d written)"
                             % (index, cmd["family"], len(body), len(again)))
        REENCODED["by hand"] += 1
    # AND EVERY BLOCK BY ITS DECLARED TYPE, whether or not a hand reader states its family: the two readings are
    # written apart and must both read the body whole and write it back as the same bytes
    try:
        typed_family, _ = CODEC.round_trip(body)
    except ValueError as e:
        raise ValueError("block %d: %s does not read back by its declared type: %s" % (index, cmd["family"], e))
    if typed_family != cmd["family"]:
        raise ValueError("block %d: read as %s by hand and %s by its type" % (index, cmd["family"], typed_family))
    REENCODED["by type"] += 1
    preimage_len = r.pos
    stored = r.take(32)
    recomputed = hash_with_domain(BLOCK_DOMAIN, raw[:preimage_len])
    if recomputed != stored:
        raise ValueError("block %d: stored hash %s, recomputed %s"
                         % (index, stored.hex(), recomputed.hex()))
    trailer = r.take(r.remaining()) if r.remaining() else None
    return {"index": idx, "timestamp": timestamp, "caller": caller, "parent": parent,
            "hash": stored, "day": day, "version": cmd_version, "command": cmd,
            "trailer": trailer}


class Store:
    """The fold, written independently. The rules are the ones stated in the design, not read off
    the Motoko: a name is required, a slug must fit in 32 bytes, a slug is unique, a coordinate is
    an E7 microdegree, a radius fits its field."""

    MAX_E7 = 1_800_000_000
    MAX_RADIUS = 256 ** 4 - 1

    def __init__(self):
        self.companies = {}
        self.by_slug = {}
        self.next_id = 1
        self.blocks_applied = 0
        self.hr = hr.Hr()
        self.pay = payroll.Payroll()
        self.ledger = accounting.Ledger()
        self.stock = stock.Stock()
        self.crm = crm.Crm()
        self.expenses = expenses.Expenses()
        self.payments = payments.Payments()
        self.payments.companies = self.companies
        self.statements = statements.Statements()
        self.credit = credit.Credit()
        self.consolidation = consolidation.Consolidation()
        self.manufacturing = manufacturing.Manufacturing()
        self.maintenance = maintenance.Maintenance()
        self.quality = quality.Quality()
        self.helpdesk = helpdesk.Helpdesk()
        self.projects = projects.Projects()
        self.fieldservice = fieldservice.FieldService()
        self.appointments = appointments.Appointments()
        self.subscriptions = subscriptions.Subscriptions()
        self.rental = rental.Rental()
        self.pos = pos.Pos()
        self.rst = rst.Rst()
        self.web = web.Web()
        self.site = website.Site()
        self.blog = blog.Blog()
        self.forum = forum.Forum()
        self.chat = chat.Chat()
        self.auto = automation.Auto()
        self.sms = sms.Sms()
        self.social = social.Social()
        self.events = events.Events()
        self.surveys = survey.Surveys()
        self.appraisals = appraisals.Appraisals()
        self.learning = learning.Learning()
        self.compensation = compensation.Compensation()
        self.fleet = fleet.Fleet()
        self.discuss = discuss.Discuss()
        self.knowledge = knowledge.Knowledge()
        self.governance = governance.Governance()
        self.workflow = workflow.Workflow()
        self.studio = studio.Studio()
        self.controls = controls.Controls()
        self.voip = voip.Voip()
        # the product-lifecycle reader, which the manufacturing reader asks for the version a production is made to
        self.plm = plm.Plm(self.manufacturing)
        # ESG: the GWP sets, factor versions, rules and activities, and every run walked over this reader's own ledger
        self.esg = esg.Esg()
        # DRAFTS: every act proposed for a person, and every acceptance folded as the acceptor's act through this
        # reader's own gate and readers
        self.draft = draft.Draft(read_command)
        # THE GATE: who may send each act, asked of every block before any reader folds it
        self.gate = gate.Gate()
        # THE AUDIT INDEX: one entry under the caller and one under the company for every block
        self.audit = audit.Audit()
        self.manufacturing.plm = self.plm
        # the mailing twin asks the automation twin whether a mailing is an activated workflow's template
        self.crm.is_template = self.auto.is_template
        self.crm.activities = self.voip.activities
        # the credit reader's own line pricing, lent to the subscription reader for the period invoices
        self.credit.line_amounts_fn = credit.line_amounts

    def apply(self, block: dict):
        """One block asked the gate's question, folded, then the controls reader's records of what it posted and
        confirmed: a move posted and an order confirmed are recorded in the block that did it, whichever reader folded
        the act. A company brought into existence admits its founder as its administrator in the same block, and that
        admission is folded by every reader as the contract writes it."""
        self.gate.check(block, self)
        where = self.audit.company_before(block, self)
        before = self.next_id
        self._fold(block)
        self.gate.after(block, self)
        if block["command"]["family"] == "bootstrapCompany" and self.next_id == before + 1:
            founder = self.gate.founder(block, before)
            self._fold(founder)
            self.gate.after(founder, self)
            where = before
        if where is None:
            raise ValueError("block %d: a founding that brought no company into existence" % block["index"])
        self.audit.write(block, where)
        self.controls.after_block(block, self)

    def _fold(self, block: dict):
        cmd = block["command"]
        # the platform operator's acts are the gate's own, and it folds them
        if cmd["family"] in gate.FAMILIES:
            return
        # a draft's acts are the draft reader's, and an acceptance folds its act through this same fold
        if cmd["family"] in draft.FAMILIES:
            self.draft.apply(block, self)
            return
        # the learning reader watches the document families on their way to the evidence reader
        if cmd["family"] in learning.WATCHED:
            self.learning.observe(block)
        # and the knowledge reader watches them too: a version is held to the document it names
        if cmd["family"] in knowledge.WATCHED:
            self.knowledge.observe(block)
        # and the voice-over-IP reader watches them, and every activity of the pipeline, which the CRM reader does not
        # fold: a call carries out an activity, and its recording is a document
        if cmd["family"] in voip.WATCHED:
            self.voip.observe(block)
        # and the governance reader too: a policy's version is held to the document it names, an acknowledgement to
        # the fingerprint its words were registered with
        if cmd["family"] in governance.WATCHED:
            self.governance.observe(block)
        # THE GATE: a domain's decision about a record of a chained kind is held to the request in flight about it,
        # or to the company having no cycle for the kind, before the domain's own reader folds it
        if cmd["family"] in workflow.GATED:
            self.workflow.gate(block, self)
        # THE CREDIT ACCOUNT is made of other families' acts - an order confirmed, an invoice, a bill
        # matched, a bank line reconciled, a payment accepted - which the credit reader watches AFTER
        # the reader that owns each has folded it, and of its own three families.
        if cmd["family"] in credit.FAMILIES:
            self.credit.apply(block, self.ledger)
            return
        # THE GROUP AND ITS CONSOLIDATIONS read the ledger reader's statements, accounts and moves and
        # write nothing into it.
        if cmd["family"] in consolidation.FAMILIES:
            self.consolidation.apply(block, self.ledger)
            return
        # A PRODUCTION: its state, which a failure and a check are raised against, and its two
        # pickings, which this reader hands to its own stock fold - AFTER asking the quality reader
        # whether the output is held, which a block that produced through a hold is a fault for.
        if cmd["family"] in manufacturing.FAMILIES:
            if cmd["family"] == "produce":
                self._hold_production(block)
            self.manufacturing.apply(block, self._consume)
            return
        # THE CONTROL POINTS, THE CHECKS AND THE NON-CONFORMANCES. A scrapped delivery's goods are a
        # picking this reader hands to its own stock fold; a held picking is cancelled there.
        if cmd["family"] in quality.FAMILIES:
            self.quality.apply(block, self.stock, self.manufacturing, self._consume, self._cancel_picking)
            return
        # THE HELPDESK, and the calendar its clocks read - the working week and the holidays, which
        # no other reader folds. Membership is the HR reader's, the partners the payment reader's note.
        if cmd["family"] in helpdesk.FAMILIES:
            self.helpdesk.apply(block, self.hr, self.payments.partners)
            return
        # THE PROJECTS, TASKS, TIME AND TIMESHEETS: an approval's cost move goes through the ledger reader.
        if cmd["family"] in projects.FAMILIES:
            self.projects.apply(block, self.hr, self.pay, self.ledger)
            return
        # FIELD SERVICE: the visit's task through the project reader, its parts through the stock reader,
        # its sale through the credit reader's order fold.
        if cmd["family"] in fieldservice.FAMILIES:
            self.fieldservice.apply(block, self.hr, self.projects, self.stock, self.payments.partners, self.payments.categories, self.helpdesk, self._consume, self._sale)
            return
        # APPOINTMENTS: a resource's availability by the calendar the helpdesk reader keeps, the slot checked again.
        if cmd["family"] in appointments.FAMILIES:
            self.appointments.apply(block, self.hr, self.helpdesk)
            return
        # SUBSCRIPTIONS: every period and every proration a sale through the credit reader's order fold.
        if cmd["family"] in subscriptions.FAMILIES:
            self.subscriptions.apply(block, self.payments.partners, self.payments.categories, self.ledger, self._sale)
            return
        # POINT OF SALE: every sale an order through the credit reader's order fold; the Z report's receipts
        # posted through the ledger reader, its goods through the stock reader, its takings move generated.
        if cmd["family"] in pos.FAMILIES:
            self.pos.apply(block, self)
            return
        # THE RESTAURANT: tables and courses over the till session, the bill split by the rule and rung
        # up through this reader's own till fold.
        if cmd["family"] in rst.FAMILIES:
            self.rst.apply(block, self)
            return
        # THE WEB SHOP: a cart as a draft order through the credit reader's order fold, the checkout holding
        # the goods, the fulfilment through the stock reader with the payment generated under four eyes.
        if cmd["family"] in web.FAMILIES:
            self.web.apply(block, self)
            return
        # THE WEBSITE: pages published from documents whose chunks this reader reassembles and hashes itself.
        if cmd["family"] in website.WATCHED:
            self.site.note(block)
        if cmd["family"] in website.FAMILIES:
            self.site.apply(block, self)
            return
        # THE BLOG: posts over the website's documents, their author and day written from the block.
        if cmd["family"] in blog.FAMILIES:
            self.blog.apply(block, self)
            return
        # THE FORUM: every author and day from the block, every moderation a second person's.
        if cmd["family"] in forum.FAMILIES:
            self.forum.apply(block, self)
            return
        # LIVE CHAT: the operator given the longest waiting conversation by the reader's own queue, every word a party's.
        if cmd["family"] in chat.FAMILIES:
            self.chat.apply(block, self)
            return
        # MARKETING AUTOMATION: enrolment from the reader's own segment and leads, every wave through its mailing fold.
        if cmd["family"] in automation.FAMILIES:
            self.auto.apply(block, self)
            return
        # SMS MARKETING: every mobile brought to one form here, every list re-chained, every copy recounted.
        if cmd["family"] in sms.FAMILIES:
            self.sms.apply(block, self)
            return
        # SOCIAL MARKETING: every claim re-derived from the reader's own queue, every image hashed from the chunks.
        if cmd["family"] in social.FAMILIES:
            self.social.apply(block, self)
            return
        # EVENTS: every ticket a sale through the credit reader's order fold, attendance held to the seats.
        if cmd["family"] in events.FAMILIES:
            self.events.apply(block, self)
            return
        # SURVEYS: every response under the reader's own key, one per respondent, every tally recounted from the answers.
        if cmd["family"] in survey.FAMILIES:
            self.surveys.apply(block, self)
            return
        # APPRAISALS: every reviewer re-derived from the reader's own employee table, every final rating read by the rule.
        if cmd["family"] in appraisals.FAMILIES:
            self.appraisals.apply(block, self)
            return
        # LEARNING: progress held forward, validity read against the calendar, room counted from what stands.
        if cmd["family"] in learning.FAMILIES:
            self.learning.apply(block, self)
            return
        # COMPENSATION AND BENEFITS: the schedule, the final figure, the net, the instalments and the costs recomputed;
        # the postings through this reader's own ledger; the new base written onto its own payroll
        if cmd["family"] in compensation.FAMILIES:
            self.compensation.apply(block, self)
            return
        # THE FLEET: the odometer, the fuel amounts, the consumption and the posted totals recomputed; the postings
        # through this reader's own ledger
        if cmd["family"] in fleet.FAMILIES:
            self.fleet.apply(block, self)
            return
        # DISCUSSION: every audience computed by this reader from what it watched of HR, every notification that
        # reports a record held to the record this reader folded
        if cmd["family"] in discuss.FAMILIES:
            self.discuss.apply(block, self)
            return
        # KNOWLEDGE: every version held to the document this reader watched, every count re-added from the rows
        if cmd["family"] in knowledge.FAMILIES:
            self.knowledge.apply(block, self)
            return
        # GOVERNANCE: every acknowledgement held to the fingerprint of the words published, every run's members walked
        if cmd["family"] in governance.FAMILIES:
            self.governance.apply(block, self)
            return
        # APPROVAL WORKFLOWS: every step held to its role and to the delegations standing on its day
        if cmd["family"] in workflow.FAMILIES:
            self.workflow.apply(block, self)
            return
        # STUDIO: every field's shape and rule restated, every value held to the rule in force, to its writer's role in
        # standing and to a record the readers here watched
        if cmd["family"] in studio.FAMILIES:
            self.studio.apply(block, self)
            return
        # CONTROLS: every profile restated, every slice of every run walked over this reader's own rows, every criterion
        # of every move re-decided, every finding and its conclusion held to four eyes
        if cmd["family"] in controls.FAMILIES:
            self.controls.apply(block, self)
            return
        # VOICE OVER IP: every call held to the lead, the standing of its caller and the activity it carries out, every
        # number brought to one form, every recording to the document this reader watched
        if cmd["family"] in voip.FAMILIES:
            self.voip.apply(block, self)
            return
        # PRODUCT LIFECYCLE: every change held to its proposer's standing, its decider's role and its bill, and asked
        # again whole when it is approved, against this reader's own walk of every version's graph
        if cmd["family"] in plm.FAMILIES:
            self.plm.apply(block, self)
            return
        # ESG: every set and version held to its recorder and its approver, every rule and activity to the company, and
        # every slice walked over the accounting reader's moves and this reader's activities, the run sealed by its own
        # chain and hash
        if cmd["family"] in esg.FAMILIES:
            self.esg.apply(block, self)
            return
        # the discussion reader watches the memberships, the standings, the departments, the titles and the leave
        # decisions on their way to the HR reader
        if cmd["family"] in discuss.WATCHED:
            self.discuss.observe(block)
        # the appraisal reader watches the employee families on their way to the HR reader
        if cmd["family"] in appraisals.WATCHED:
            self.appraisals.observe(block)
        # RENTAL: the unit out and back through the stock reader, the charge through the credit reader's order fold.
        if cmd["family"] in rental.FAMILIES:
            self.rental.apply(block, self.stock, self.payments.partners, self.payments.categories, self.ledger, self._consume, self._sale)
            return
        # THE QUALITY HOLD on a receipt or a delivery: asked before the stock reader validates it.
        if cmd["family"] == "validatePicking":
            self._hold_picking(block)
        # THE WORK ORDERS. A sign-off's parts are a picking this reader hands to its own stock fold.
        if cmd["family"] in maintenance.FAMILIES:
            self.maintenance.apply(block, self.ledger, self.stock, self.manufacturing, self._consume, self.appraisals)
            return
        self._apply(block)
        if cmd["family"] in credit.WATCHED_FAMILIES:
            self.credit.watch(block, self.ledger, self.payments)

    def _post_valuation(self, block, picking_id, journal_id):
        """THE VALUATION ENTRY. The contract proposes it through its ledger fold inside the same
        block, so it is on no block of its own; the reader hands the ledger the entry its own
        refold of the picking produced, and the ledger's rules judge it like any proposed move."""
        p = self.stock.pickings.get(picking_id)
        if p is not None and p["state"] == "done" and p.get("posts"):
            costing = self.stock.costings[(p["companyId"], self.stock.first_category(picking_id))]
            inv, cogs = costing["inventoryAccountId"], costing["cogsAccountId"]
            lines = ([{"accountId": inv, "partnerId": p["partnerId"], "name": "stock in", "debit": p["value"], "credit": 0, "amountCurrency": 0, "taxId": 0},
                      {"accountId": cogs, "partnerId": p["partnerId"], "name": "stock in counterpart", "debit": 0, "credit": p["value"], "amountCurrency": 0, "taxId": 0}]
                     if p["direction"] == "in" else
                     [{"accountId": cogs, "partnerId": p["partnerId"], "name": "cost of sales", "debit": p["value"], "credit": 0, "amountCurrency": 0, "taxId": 0},
                      {"accountId": inv, "partnerId": p["partnerId"], "name": "stock out", "debit": 0, "credit": p["value"], "amountCurrency": 0, "taxId": 0}])
            facts = {"companyId": p["companyId"], "journalId": journal_id, "businessDay": p["businessDay"], "moveType": "entry",
                     "currency": "EGP", "partnerId": p["partnerId"], "ref": "picking %d" % picking_id, "lines": lines}
            self.ledger.apply({"command": {"family": "proposeMove", "facts": facts}, "index": block["index"], "caller": block["caller"], "day": block["day"]})
            p["valuationMoveId"] = self.ledger.next_move - 1

    def _hold_picking(self, block):
        """A receipt is a picking out of a supplier location, a delivery one into a customer location;
        a standing control point that watches its goods and has not passed them holds it, and a block
        that validated it anyway is a fault - the contract's refusal is this reader's rule too."""
        c = block["command"]
        p = self.stock.pickings.get(c["pickingId"])
        if p is None or p["state"] != "ready":
            return
        src, dst = self.stock.locations.get(p["fromLocationId"]), self.stock.locations.get(p["toLocationId"])
        if src is None or dst is None:
            return
        cats = [m["categoryId"] for m in self.stock.moves.values() if m["pickingId"] == c["pickingId"]]
        for trigger, meets in (("receipt", src["usage"] == "supplier"), ("delivery", dst["usage"] == "customer")):
            if meets:
                held = self.quality.hold_on(p["companyId"], trigger, c["pickingId"], cats)
                if held is not None:
                    self.quality.faults.append("block %d validated picking %d held at control point %d: %s" % (block["index"], c["pickingId"], held[0], held[1]))
                    self.quality.held_broken = getattr(self.quality, "held_broken", 0) + 1

    def _hold_production(self, block):
        c = block["command"]
        p = self.manufacturing.productions.get(c["productionId"])
        if p is None or p["state"] not in quality.RUNNING:
            return
        held = self.quality.hold_on(p["companyId"], "production", c["productionId"], [p["categoryId"]])
        if held is not None:
            self.quality.faults.append("block %d produced on production %d held at control point %d: %s" % (block["index"], c["productionId"], held[0], held[1]))

    def _cancel_picking(self, picking_id):
        """A held picking cancelled by a disposition, in the stock reader: the picking and its moves."""
        p = self.stock.pickings.get(picking_id)
        if p is None or p["state"] != "ready":
            self.quality.faults.append("a disposition cancelled picking %d, which was not ready" % picking_id)
            return
        p["state"] = "cancelled"
        for m in self.stock.moves.values():
            if m["pickingId"] == picking_id:
                m["state"] = "cancelled"

    def _sale(self, block, facts, journal_id):
        """A sale another fold raised inside its own block - a visit's invoice: placed, confirmed and
        invoiced through the credit reader's order fold, exactly as three blocks of the order families
        would be, with the entry through the ledger reader. Answers (orderId, moveId)."""
        def synth(cmd):
            return {"command": cmd, "index": block["index"], "caller": block["caller"], "day": block["day"]}
        place = synth({"family": "placeOrder", "facts": facts})
        self.payments.note(place)
        self.credit.watch(place, self.ledger, self.payments)
        order_id = self.credit.next_order - 1
        confirm = synth({"family": "confirmOrder", "companyId": facts["companyId"], "orderId": order_id, "reason": ""})
        self.payments.note(confirm)
        self.credit.watch(confirm, self.ledger, self.payments)
        self.credit.watch(synth({"family": "issueInvoice", "companyId": facts["companyId"], "orderId": order_id, "journalId": journal_id}), self.ledger, self.payments)
        o = self.credit.orders.get(order_id)
        if o is None or o["state"] != "invoiced":
            return None
        return order_id, o["moveId"]

    def _consume(self, block, facts, journal_id):
        """A work order's parts, a production's components and output, a scrapped delivery's goods:
        the picking made and validated by the stock reader inside the act's block, as the contract
        does it through its stock fold, and posted."""
        self.stock.create_picking(block, facts)
        pid = self.stock.next["picking"] - 1
        if pid not in self.stock.pickings:
            return 0
        self.stock.validate_picking(block, {"companyId": facts["companyId"], "pickingId": pid, "journalId": journal_id})
        self._post_valuation(block, pid, journal_id)
        return pid

    def _apply(self, block: dict):
        cmd = block["command"]
        # THE PARTNERS, CATEGORIES AND ORDERS a bill and a payment read are noted before any other
        # reader sees the block; the three-way match and the payment families are the payment
        # reader's own, and the match's move and the acceptance's go THROUGH the ledger reader.
        if cmd["family"] in payments.NOTED_FAMILIES:
            self.payments.note(block)
        if cmd["family"] in payments.FAMILIES:
            self.payments.apply(block, self.ledger)
            return
        # THE BANK'S STATEMENTS, typed or from a camt.053 message the reader parses again itself.
        if cmd["family"] in statements.FAMILIES:
            self.statements.apply(block, self.ledger, self.payments)
            return
        if cmd["family"] in stock.FAMILIES or cmd["family"] == "createCategory":
            self.stock.apply(block)
            if cmd["family"] == "validatePicking":
                self._post_valuation(block, cmd["pickingId"], cmd["journalId"])
            if cmd["family"] != "createCategory":
                return
        # THE RECEIPTS. The evidence families register, archive and erase the documents a claim names;
        # the expense reader notes them and the HR reader below sees them as it always did.
        if cmd["family"] in expenses.DOCUMENT_FAMILIES:
            self.expenses.note_document(block)
        if cmd["family"] in expenses.FAMILIES:
            # a claim's approval and settlement post THROUGH the ledger reader, so the moves they
            # generate stand in the trial balance, the close and the hledger journal like any other
            self.expenses.apply(block, self.ledger, self.hr)
            return
        if cmd["family"] in crm.FAMILIES:
            self.crm.apply(block)
            return
        if cmd["family"] in hr.ACCOUNTING_FAMILIES:
            self.ledger.apply(block)
            return
        if cmd["family"] in hr.PAYROLL_FAMILIES:
            self.pay.apply(block)
            return
        if cmd["family"] != "bootstrapCompany":
            self.hr.apply(block)
            return
        f = cmd["facts"]
        if not f["name"]:
            raise ValueError("block %d: a company with no name was accepted" % block["index"])
        slug = f["slug"].encode("utf-8")
        if len(slug) > SLUG_BYTES:
            raise ValueError("block %d: a slug of %d bytes was accepted" % (block["index"], len(slug)))
        if slug in self.by_slug:
            raise ValueError("block %d: slug %r was accepted twice (already company %d)"
                             % (block["index"], f["slug"], self.by_slug[slug]))
        for k in ("geoLat", "geoLon"):
            v = f[k]
            if v is not None and abs(v) > self.MAX_E7:
                raise ValueError("block %d: %s = %d is not an E7 coordinate" % (block["index"], k, v))
        if f["geoRadiusMetres"] > self.MAX_RADIUS:
            raise ValueError("block %d: a radius of %d was accepted" % (block["index"], f["geoRadiusMetres"]))
        cid = self.next_id
        self.companies[cid] = {
            "name": f["name"], "orgCode": f["orgCode"], "slug": f["slug"],
            "createdBy": block["caller"], "createdDay": block["day"], "isActive": True,
            "geoLat": f["geoLat"], "geoLon": f["geoLon"],
            "geoRadiusMetres": f["geoRadiusMetres"],
            "geoRequireLocation": f["geoRequireLocation"],
            "lastBlock": block["index"],
        }
        self.by_slug[slug] = cid
        self.next_id += 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file", nargs="?")
    ap.add_argument("--expect-companies", type=int)
    ap.add_argument("--expect-balances", type=int)
    ap.add_argument("--expect-punches", type=int)
    ap.add_argument("--expect-payslips", type=int)
    ap.add_argument("--expect-quants", type=int)
    ap.add_argument("--expect-moves", type=int)
    ap.add_argument("--expect-campaigns", type=int)
    ap.add_argument("--expect-closes", type=int)
    ap.add_argument("--expect-statements", type=int)
    ap.add_argument("--expect-deferrals", type=int)
    ap.add_argument("--expect-revaluations", type=int)
    ap.add_argument("--expect-assets", type=int)
    ap.add_argument("--expect-claims", type=int)
    ap.add_argument("--expect-payments", type=int)
    ap.add_argument("--expect-camt", type=int)
    ap.add_argument("--expect-items", type=int)
    ap.add_argument("--expect-consolidations", type=int)
    ap.add_argument("--expect-work-orders", type=int)
    ap.add_argument("--expect-quality-checks", type=int)
    ap.add_argument("--expect-tickets", type=int)
    ap.add_argument("--expect-visits", type=int)
    ap.add_argument("--expect-bookings", type=int)
    ap.add_argument("--expect-subscription-invoices", type=int)
    ap.add_argument("--expect-rentals", type=int)
    ap.add_argument("--expect-till-sessions", type=int)
    ap.add_argument("--expect-tabs", type=int)
    ap.add_argument("--expect-web-orders", type=int)
    ap.add_argument("--expect-pages", type=int)
    ap.add_argument("--raise-read-floor", action="store_true",
                    help="write the read pages' counts as the new floor (integration/oracle/read_floor.json)")
    ap.add_argument("--expect-posts", type=int)
    ap.add_argument("--expect-topics", type=int)
    ap.add_argument("--expect-conversations", type=int)
    ap.add_argument("--expect-workflows", type=int)
    ap.add_argument("--expect-text-mailings", type=int)
    ap.add_argument("--expect-social-posts", type=int)
    ap.add_argument("--expect-events", type=int)
    ap.add_argument("--expect-surveys", type=int)
    ap.add_argument("--expect-review-cycles", type=int)
    ap.add_argument("--expect-courses", type=int)
    ap.add_argument("--expect-pay-bands", type=int)
    ap.add_argument("--expect-vehicles", type=int)
    ap.add_argument("--expect-notifications", type=int)
    ap.add_argument("--expect-kb-articles", type=int)
    ap.add_argument("--expect-gov-policies", type=int)
    ap.add_argument("--expect-wf-requests", type=int)
    ap.add_argument("--expect-studio-fields", type=int)
    ap.add_argument("--expect-tip")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    source = open(a.file, encoding="utf-8") if a.file else sys.stdin
    pieces, tip = {}, None
    reported_payslips = {}
    reported_quants, reported_layers, reported_pickings, reported_values = {}, {}, {}, {}
    reported_campaigns = {}
    reported_closes = {}
    reported_statements = {}
    reported_deferrals = {}
    reported_revaluations = {}
    reported_assets = {}
    reported_claims = {}
    reported_payments = {}
    reported_camt = {}
    reported_items = {}
    reported_terms = {}
    reported_consolidations = {}
    reported_equipment = {}
    reported_plans = {}
    reported_work_orders = {}
    reported_control_points, reported_checks, reported_nonconformances = {}, {}, {}
    reported_teams, reported_slas, reported_tickets = {}, {}, {}
    reported_rates, reported_visits, reported_visit_invoices = {}, {}, {}
    reported_resources, reported_bookings = {}, {}
    reported_subscriptions, reported_subinvoices = {}, {}
    reported_rental_items, reported_rentals, reported_rental_charges = {}, {}, {}
    reported_shops, reported_till_sessions, reported_till_sales = {}, {}, {}
    reported_tables, reported_tabs, reported_shares = {}, {}, {}
    reported_storefronts, reported_web_orders, reported_holds = {}, {}, {}
    reported_pages, reported_versions = {}, {}
    reported_posts = {}
    reported_boards = {}
    reported_topics = {}
    reported_replies = {}
    reported_moderations = {}
    reported_operators = {}
    reported_conversations = {}
    reported_chat_messages = {}
    reported_workflows = {}
    reported_steps = {}
    reported_participants = {}
    reported_auto_runs = {}
    reported_sms_mailings = {}
    reported_sms_recipients = {}
    reported_sms_suppressions = {}
    reported_social_accounts = {}
    reported_social_posts = {}
    reported_events = {}
    reported_event_tickets = {}
    reported_surveys = {}
    reported_survey_questions = {}
    reported_survey_tallies = {}
    reported_survey_responses = {}
    reported_cycles = {}
    reported_reviews = {}
    reported_goals = {}
    reported_key_results = {}
    reported_recognitions = {}
    reported_courses = {}
    reported_paths = {}
    reported_path_items = {}
    reported_enrolments = {}
    reported_certifications = {}
    reported_skills = {}
    reported_mentorships = {}
    reported_pay_bands = {}
    reported_salary_reviews = {}
    reported_equity_grants = {}
    reported_incentive_scores = {}
    reported_offcycle_payments = {}
    reported_employee_loans = {}
    reported_loan_repayments = {}
    reported_enrolment_periods = {}
    reported_benefit_enrolments = {}
    reported_vehicles = {}
    reported_vehicle_assignments = {}
    reported_vehicle_contracts = {}
    reported_odometer_logs = {}
    reported_fuel_logs = {}
    reported_vehicle_costs = {}
    reported_channels = {}
    reported_channel_members = {}
    reported_channel_messages = {}
    reported_announcements = {}
    reported_reactions = {}
    reported_notifications = {}
    reported_announcement_sweeps = {}
    reported_kb_articles = {}
    reported_kb_versions = {}
    reported_kb_views = {}
    reported_kb_votes = {}
    reported_gov = {k: {} for k in ("gov_policy", "gov_version", "gov_ack", "gov_requirement", "gov_citation", "gov_layout")}
    reported_gov_runs = {}
    reported_wf = {k: {} for k in ("wf_cycle", "wf_request", "wf_decision", "wf_delegation")}
    reported_studio = {k: {} for k in ("studio_field", "studio_rule", "studio_value")}
    reported_studio_outside = None
    reported_ctl = {k: {} for k in ("move_posting", "order_confirmation", "ctl_standing", "ctl_profile", "ctl_item", "ctl_run",
                                    "ctl_count", "ctl_mark", "ctl_finding", "ctl_procedure", "ctl_conclusion")}
    reported_ctl_printed = None
    reported_voip = {"voip_call": {}, "voip_activity": {}}
    reported_codec = {"plain": {}, "rich": {}}
    reported_requirements = {}
    reported_requirements_printed = None
    reported_leads = {}
    reported_leads_printed = None
    reported_crm_rows = {"crm_activity": {}, "crm_run": {}}
    reported_crm_rows_printed = None
    reported_audit = {"caller": set(), "company": set()}
    reported_audit_lines = {"caller": 0, "company": 0}
    reported_audit_printed = {"caller": None, "company": None}
    reported_plm = {"plm_eco": {}, "plm_eco_line": {}, "plm_pin": {}}
    reported_plm_printed = None
    reported_esg = {"esg_gwp_set": {}, "esg_gas": {}, "esg_factor": {}, "esg_factor_text": {}, "esg_rule": {}, "esg_activity": {}, "esg_run": {}, "esg_figure": {}}
    reported_esg_disclosures = {}
    reported_esg_printed = None
    reported_draft = {}
    reported_draft_printed = None
    read_page_pieces = {}
    reported_read_pages = None
    reported_read_rows = None
    reported_voip_printed = None
    for line in source:
        line = line.strip()
        if line.startswith("block: "):
            _, idx, part, hexed = line.split(None, 3)
            pieces.setdefault(int(idx), {})[int(part)] = hexed
        elif line.startswith("payslip: "):
            _, subject, g, d, n, e, r = line.split()
            reported_payslips[subject] = (int(g), int(d), int(n), int(e), int(r))
        elif line.startswith("quant: "):
            _, qid, company, location, category, lot, quantity = line.split()
            reported_quants[int(qid)] = (int(company), int(location), int(category), int(lot), int(quantity))
        elif line.startswith("layer: "):
            _, lid, company, category, location, seq, remaining, unit_cost = line.split()
            reported_layers[int(lid)] = (int(company), int(category), int(location), int(seq), int(remaining), int(unit_cost))
        elif line.startswith("picking: "):
            _, pid, state, value, move = line.split()
            reported_pickings[int(pid)] = (state, int(value), int(move))
        elif line.startswith("stock-value: "):
            _, company, category, location, value = line.split()
            reported_values[(int(company), int(category), int(location))] = int(value)
        elif line.startswith("campaign: "):
            parts = line.split()
            reported_campaigns[int(parts[1])] = (parts[2], parts[3]) + tuple(int(x) for x in parts[4:])
        elif line.startswith("close: "):
            parts = line.split()
            # runId state fromDay throughDay planned swept movesPosted netIncome lock planHash reDebits reCredits
            reported_closes[int(parts[1])] = (parts[2], int(parts[3]), int(parts[4]), int(parts[5]), int(parts[6]),
                                              int(parts[7]), int(parts[8]), int(parts[9]), parts[10], int(parts[11]), int(parts[12]))
        elif line.startswith("statement: "):
            parts = line.split()
            # id kind state fromDay throughDay lines atBlock tip hash debits credits result
            reported_statements[int(parts[1])] = (parts[2], parts[3], int(parts[4]), int(parts[5]), int(parts[6]), int(parts[7]),
                                                  parts[8], parts[9], int(parts[10]), int(parts[11]), int(parts[12]))
        elif line.startswith("deferral: "):
            parts = line.split()
            # id kind state amount months recognized posted, then ordinal scheduledDay postedDay amount per entry
            tail = [int(x) for x in parts[8:]]
            entries = tuple(tuple(tail[i:i + 4]) for i in range(0, len(tail), 4))
            reported_deferrals[int(parts[1])] = (parts[2], parts[3], int(parts[4]), int(parts[5]), int(parts[6]), int(parts[7]), entries)
        elif line.startswith("revaluation: "):
            parts = line.split()
            # id runId accountId currency foreign book rate revalued difference posted reversed
            reported_revaluations[int(parts[1])] = (int(parts[2]), int(parts[3]), parts[4], int(parts[5]), int(parts[6]), int(parts[7]),
                                                    int(parts[8]), int(parts[9]), int(parts[10]), int(parts[11]))
        elif line.startswith("asset: "):
            parts = line.split()
            # id state cost salvage months recognized depreciated impaired eventsPosted result [ordinal scheduledDay postedDay amount]*
            tail = [int(x) for x in parts[11:]]
            entries = tuple(tuple(tail[i:i + 4]) for i in range(0, len(tail), 4))
            reported_assets[int(parts[1])] = (parts[2], int(parts[3]), int(parts[4]), int(parts[5]), int(parts[6]), int(parts[7]), int(parts[8]),
                                              int(parts[9]), int(parts[10]), entries)
        elif line.startswith("claim: "):
            parts = line.split()
            # id state total lineCount posted settled [ordinal kind quantity rate amount receipt]*
            tail = parts[7:]
            entries = tuple((int(tail[i]), tail[i + 1], int(tail[i + 2]), int(tail[i + 3]), int(tail[i + 4]), int(tail[i + 5])) for i in range(0, len(tail), 6))
            reported_claims[int(parts[1])] = (parts[2], int(parts[3]), int(parts[4]), int(parts[5]), int(parts[6]), entries)
        elif line.startswith("payment: "):
            parts = line.split()
            # id state billId amount currency uetr sha256hex posted
            reported_payments[int(parts[1])] = (parts[2], int(parts[3]), int(parts[4]), parts[5], parts[6], parts[7], int(parts[8]))
        elif line.startswith("camt: "):
            parts = line.split()
            # id name state currency day start declared computed lineCount [ordinal day amount ref partner]*
            tail = parts[10:]
            entries = tuple((int(tail[i]), int(tail[i + 1]), int(tail[i + 2]), tail[i + 3], int(tail[i + 4])) for i in range(0, len(tail), 5))
            reported_camt[int(parts[1])] = (parts[2], parts[3], parts[4], int(parts[5]), int(parts[6]), int(parts[7]), int(parts[8]), int(parts[9]), entries)
        elif line.startswith("credit: "):
            parts = line.split()
            # id kind state partnerId orderId billId moveId amount settled dueDay chargedThrough lateCharged charges interest
            reported_items[int(parts[1])] = (parts[2], parts[3]) + tuple(int(x) for x in parts[4:15])
        elif line.startswith("terms: "):
            parts = line.split()
            # id partnerId limit termDays graceDays lateCharge interestRate exposure
            reported_terms[int(parts[1])] = tuple(int(x) for x in parts[2:9])
        elif line.startswith("equipment: "):
            parts = line.split()
            # id code state downtimeDays locationId assetId
            reported_equipment[int(parts[1])] = (parts[2], parts[3], int(parts[4]), int(parts[5]), int(parts[6]))
        elif line.startswith("plan: "):
            parts = line.split()
            # id equipmentId intervalDays nextDay ordersMade active
            reported_plans[int(parts[1])] = tuple(int(x) for x in parts[2:7])
        elif line.startswith("maintenance: "):
            parts = line.split()
            # id kind state equipmentId planId productionId requestedDay dueDay doneDay downtimeDays partsPickingId
            reported_work_orders[int(parts[1])] = (parts[2], parts[3]) + tuple(int(x) for x in parts[4:12])
        elif line.startswith("control_point: "):
            parts = line.split()
            # id code trigger categoryId active checksMade
            reported_control_points[int(parts[1])] = (parts[2], parts[3], int(parts[4]), int(parts[5]), int(parts[6]))
        elif line.startswith("quality: "):
            parts = line.split()
            # id controlPointId trigger subjectId categoryId passed day nonConformanceId
            reported_checks[int(parts[1])] = (int(parts[2]), parts[3]) + tuple(int(x) for x in parts[4:9])
        elif line.startswith("nonconformance: "):
            parts = line.split()
            # id checkId controlPointId trigger subjectId disposition raisedDay decidedDay scrapPickingId
            reported_nonconformances[int(parts[1])] = (int(parts[2]), int(parts[3]), parts[4], int(parts[5]), parts[6], int(parts[7]), int(parts[8]), int(parts[9]))
        elif line.startswith("team: "):
            parts = line.split()
            # id code active ticketsOpened openTickets
            reported_teams[int(parts[1])] = (parts[2], int(parts[3]), int(parts[4]), int(parts[5]))
        elif line.startswith("sla: "):
            parts = line.split()
            # id teamId priority responseDays resolveDays
            reported_slas[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]), int(parts[5]))
        elif line.startswith("ticket: "):
            parts = line.split()
            # id teamId stageId state priority escalation openedDay responseDue resolveDue firstResponseDay closedDay messages
            reported_tickets[int(parts[1])] = (int(parts[2]), int(parts[3]), parts[4], parts[5]) + tuple(int(x) for x in parts[6:13])
        elif line.startswith("rate: "):
            parts = line.split()
            # id companyId labourCategoryId currency hourlyRate taxRate
            reported_rates[int(parts[2])] = (int(parts[3]), parts[4], int(parts[5]), int(parts[6]))
        elif line.startswith("visit: "):
            parts = line.split()
            # id ticketId partnerId taskId state windowFrom windowTo doneDay inWindow partsPickingId labourMinutes orderId invoiceMoveId
            reported_visits[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), parts[5]) + tuple(int(x) for x in parts[6:14])
        elif line.startswith("visit-invoice: "):
            parts = line.split()
            # visitId orderId untaxed tax total
            reported_visit_invoices[int(parts[1])] = tuple(int(x) for x in parts[2:6])
        elif line.startswith("resource: "):
            parts = line.split()
            # id code kind active bookingsMade
            reported_resources[int(parts[1])] = (parts[2], parts[3], int(parts[4]), int(parts[5]))
        elif line.startswith("booking: "):
            parts = line.split()
            # id resourceId day start end state late
            reported_bookings[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]), parts[6], int(parts[7]))
        elif line.startswith("subscription: "):
            parts = line.split()
            # id partnerId period quantity priceUnit state periodsInvoiced nextInvoiceDay
            reported_subscriptions[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]), int(parts[5]), parts[6], int(parts[7]), int(parts[8]))
        elif line.startswith("subinvoice: "):
            parts = line.split()
            # id subscriptionId ordinal kind fromDay toDay amount orderId moveId
            reported_subinvoices[int(parts[1])] = (int(parts[2]), int(parts[3]), parts[4], int(parts[5]), int(parts[6]), int(parts[7]), int(parts[8]), int(parts[9]))
        elif line.startswith("rental_item: "):
            parts = line.split()
            # id code categoryId lotId yardLocationId dailyRate lateRatePerDay active liveRentals
            reported_rental_items[int(parts[1])] = (parts[2],) + tuple(int(x) for x in parts[3:10])
        elif line.startswith("rental: "):
            parts = line.split()
            # id itemId partnerId fromDay toDay state pickedUpDay returnedDay daysLate pickupPicking returnPicking orderId moveId
            reported_rentals[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]), parts[6]) + tuple(int(x) for x in parts[7:14])
        elif line.startswith("rental-charge: "):
            parts = line.split()
            # rentalId orderId days late untaxed tax total
            reported_rental_charges[int(parts[1])] = tuple(int(x) for x in parts[2:8])
        elif line.startswith("pos_shop: "):
            parts = line.split()
            # id code stockLocationId customerLocationId partnerId journalId cashAccountId cardAccountId differenceAccountId active
            reported_shops[int(parts[1])] = (parts[2],) + tuple(int(x) for x in parts[3:11])
        elif line.startswith("pos_session: "):
            parts = line.split()
            # id shopId state openedDay closedDay postedDay openingFloat cashTakings cardTakings ordersCount untaxed tax total countedCash shortBy overBy postedOrders kindsMoved zMoveId
            reported_till_sessions[int(parts[1])] = (int(parts[2]), parts[3]) + tuple(int(x) for x in parts[4:20])
        elif line.startswith("pos_sale: "):
            parts = line.split()
            # id sessionId orderId invoiceMoveId amountTotal cashPaid cardPaid changeGiven day posted
            reported_till_sales[int(parts[1])] = tuple(int(x) for x in parts[2:11])
        elif line.startswith("rst_table: "):
            parts = line.split()
            # id shopId code seats active
            reported_tables[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]), int(parts[5]))
        elif line.startswith("rst_tab: "):
            parts = line.split()
            # id sessionId tableId state covers courses liveLines saleId orderId rule ways amountTotal
            reported_tabs[int(parts[1])] = (int(parts[2]), int(parts[3]), parts[4]) + tuple(int(x) for x in parts[5:10]) + (parts[10], int(parts[11]), int(parts[12]))
        elif line.startswith("rst_share: "):
            parts = line.split()
            # id tabId ordinal weight amount cash card change
            reported_shares[int(parts[1])] = tuple(int(x) for x in parts[2:9])
        elif line.startswith("web_storefront: "):
            parts = line.split()
            # id shopId slug open
            reported_storefronts[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]))
        elif line.startswith("web_order: "):
            parts = line.split()
            # id storefrontId cartId orderId state amountPaid amountRefunded checkoutDay fulfilledDay pickingId invoiceMoveId paymentMoveId
            reported_web_orders[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), parts[5]) + tuple(int(x) for x in parts[6:13])
        elif line.startswith("web_reservation: "):
            parts = line.split()
            # id locationId categoryId orderId quantity live
            reported_holds[int(parts[1])] = tuple(int(x) for x in parts[2:7])
        elif line.startswith("site_page: "):
            parts = line.split()
            # id companyId path currentVersion versions live
            reported_pages[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]), int(parts[5]), int(parts[6]))
        elif line.startswith("site_version: "):
            parts = line.split()
            # id pageId ordinal documentId byteSize fingerprint publishedBlock
            reported_versions[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]), parts[6], int(parts[7]))
        elif line.startswith("blog_post: "):
            parts = line.split()
            # id companyId slug publishedDay publishedBlock revisedDay revision documentId byteSize fingerprint live
            reported_posts[int(parts[1])] = (int(parts[2]), parts[3]) + tuple(int(x) for x in parts[4:10]) + (parts[10], int(parts[11]))
        elif line.startswith("forum_board: "):
            parts = line.split()
            # id companyId slug topics
            reported_boards[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]))
        elif line.startswith("forum_topic: "):
            parts = line.split()
            # id companyId boardId openedDay openedBlock lastDay activityBlock replies locked pinned hidden
            reported_topics[int(parts[1])] = tuple(int(x) for x in parts[2:12])
        elif line.startswith("forum_reply: "):
            parts = line.split()
            # id topicId day block hidden
            reported_replies[int(parts[1])] = tuple(int(x) for x in parts[2:6])
        elif line.startswith("forum_moderation: "):
            parts = line.split()
            # id target targetId act day block
            reported_moderations[int(parts[1])] = (parts[2], int(parts[3]), parts[4], int(parts[5]), int(parts[6]))
        elif line.startswith("chat_operator: "):
            parts = line.split()
            # id companyId enrolled taken
            reported_operators[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]))
        elif line.startswith("chat_conversation: "):
            parts = line.split()
            # id companyId state openedDay openedBlock takenBlock closedDay closedBlock messages rating storefrontId
            reported_conversations[int(parts[1])] = (int(parts[2]), parts[3]) + tuple(int(x) for x in parts[4:10]) + (parts[10], int(parts[11]))
        elif line.startswith("chat_message: "):
            parts = line.split()
            # id conversationId speaker day block
            reported_chat_messages[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]), int(parts[5]))
        elif line.startswith("auto_workflow: "):
            parts = line.split()
            # id companyId segmentId state steps participants ruleHash
            reported_workflows[int(parts[1])] = (int(parts[2]), int(parts[3]), parts[4], int(parts[5]), int(parts[6]), parts[7])
        elif line.startswith("auto_step: "):
            parts = line.split()
            # id workflowId ordinal kind mailingId delay condition fired
            reported_steps[int(parts[1])] = (int(parts[2]), int(parts[3]), parts[4], int(parts[5]), int(parts[6]), parts[7], int(parts[8]))
        elif line.startswith("auto_participant: "):
            parts = line.split()
            # id workflowId leadId nextStep dueDay state lastMailingId enrolledDay
            reported_participants[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]), parts[6], int(parts[7]), int(parts[8]))
        elif line.startswith("auto_run: "):
            parts = line.split()
            # id workflowId kind running throughDay scanned acted
            reported_auto_runs[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]), int(parts[5]), int(parts[6]), int(parts[7]))
        elif line.startswith("sms_mailing: "):
            parts = line.split()
            # id companyId segmentId state expected planned sent failed suppressed delivered optedOut rolling content
            reported_sms_mailings[int(parts[1])] = (int(parts[2]), int(parts[3]), parts[4]) + tuple(int(x) for x in parts[5:12]) + (parts[12], parts[13])
        elif line.startswith("sms_recipient: "):
            parts = line.split()
            # id mailingId leadId state reply attempts
            reported_sms_recipients[int(parts[1])] = (int(parts[2]), int(parts[3]), parts[4], parts[5], int(parts[6]))
        elif line.startswith("sms_suppression: "):
            parts = line.split()
            # id companyId reason active
            reported_sms_suppressions[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]))
        elif line.startswith("social_account: "):
            parts = line.split()
            # id companyId channel active posts
            reported_social_accounts[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]), int(parts[5]))
        elif line.startswith("social_post: "):
            parts = line.split()
            # id accountId documentId scheduledDay state attempts postedDay fingerprint
            reported_social_posts[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), parts[5], int(parts[6]), int(parts[7]), parts[8])
        elif line.startswith("event: "):
            parts = line.split()
            # id companyId day capacity seatsSold attended state
            reported_events[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]), int(parts[6]), parts[7])
        elif line.startswith("event_ticket: "):
            parts = line.split()
            # id eventId partnerId seats attended orderId moveId amount
            reported_event_tickets[int(parts[1])] = tuple(int(x) for x in parts[2:9])
        elif line.startswith("survey: "):
            parts = line.split()
            # id companyId anonymous dueDay state questions responses closedDay
            reported_surveys[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), parts[5], int(parts[6]), int(parts[7]), int(parts[8]))
        elif line.startswith("survey_question: "):
            parts = line.split()
            # id surveyId ordinal kind optionCount required answers
            reported_survey_questions[int(parts[1])] = (int(parts[2]), int(parts[3]), parts[4], int(parts[5]), int(parts[6]), int(parts[7]))
        elif line.startswith("survey_tally: "):
            parts = line.split()
            reported_survey_tallies[int(parts[1])] = tuple(int(x) for x in parts[2:])
        elif line.startswith("survey_response: "):
            parts = line.split()
            # id surveyId respondent key day answers
            reported_survey_responses[int(parts[1])] = (int(parts[2]), parts[3], parts[4], int(parts[5]), int(parts[6]))
        elif line.startswith("review_cycle: "):
            parts = line.split()
            # id companyId startDay endDay state cursor enrolled reviewed calibrated closedDay
            reported_cycles[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), parts[5], int(parts[6]), int(parts[7]), int(parts[8]), int(parts[9]), int(parts[10]))
        elif line.startswith("review: "):
            parts = line.split()
            # id cycleId employeeId reviewerId selfRating managerRating finalRating state final
            reported_reviews[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]), int(parts[6]), int(parts[7]), parts[8], int(parts[9]))
        elif line.startswith("goal: "):
            parts = line.split()
            # id ownerId cycleId dueDay state keyResults progress
            reported_goals[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), parts[5], int(parts[6]), int(parts[7]))
        elif line.startswith("key_result: "):
            parts = line.split()
            reported_key_results[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]), int(parts[5]))
        elif line.startswith("recognition: "):
            parts = line.split()
            reported_recognitions[int(parts[1])] = (parts[2], parts[3], parts[4], int(parts[5]), int(parts[6]))
        elif line.startswith("course: "):
            parts = line.split()
            # id companyId format level duration active enrolments
            reported_courses[int(parts[1])] = (int(parts[2]), parts[3], parts[4], int(parts[5]), int(parts[6]), int(parts[7]))
        elif line.startswith("learning_path: "):
            parts = line.split()
            reported_paths[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]))
        elif line.startswith("path_item: "):
            parts = line.split()
            reported_path_items[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]))
        elif line.startswith("enrolment: "):
            parts = line.split()
            # id courseId employeeId progress state enrolledDay completedDay
            reported_enrolments[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), parts[5], int(parts[6]), int(parts[7]))
        elif line.startswith("certification: "):
            parts = line.split()
            # id employeeId kind issuedDay expiryDay state day valid
            reported_certifications[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]), int(parts[5]), parts[6], int(parts[7]), int(parts[8]))
        elif line.startswith("skill: "):
            parts = line.split()
            # id employeeId category selfLevel managerLevel endorsements active
            reported_skills[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]), int(parts[5]), int(parts[6]), int(parts[7]))
        elif line.startswith("mentorship: "):
            parts = line.split()
            # id mentorId menteeId state sessions minutes
            reported_mentorships[int(parts[1])] = (int(parts[2]), int(parts[3]), parts[4], int(parts[5]), int(parts[6]))
        elif line.startswith("pay_band: "):
            parts = line.split()
            # id companyId grade min mid max active
            reported_pay_bands[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]), int(parts[6]), int(parts[7]))
        elif line.startswith("salary_review: "):
            parts = line.split()
            # id employeeId bandId current proposed effectiveDay state compaRatio
            reported_salary_reviews[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]), int(parts[6]), parts[7], int(parts[8]))
        elif line.startswith("equity_grant: "):
            parts = line.split()
            # id employeeId kind total vested exercised state day vestedOnDay
            reported_equity_grants[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]), int(parts[5]), int(parts[6]), parts[7], int(parts[8]), int(parts[9]))
        elif line.startswith("incentive_score: "):
            parts = line.split()
            # id planId employeeId periodDay finalBps baseMonthly amount paymentId
            reported_incentive_scores[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]), int(parts[6]), int(parts[7]), int(parts[8]))
        elif line.startswith("offcycle_payment: "):
            parts = line.split()
            # id employeeId kind gross deductions net state posted
            reported_offcycle_payments[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]), int(parts[5]), int(parts[6]), parts[7], int(parts[8]))
        elif line.startswith("employee_loan: "):
            parts = line.split()
            # id employeeId kind requested approved schedule repaid repayments state outstanding instalments...
            reported_employee_loans[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]), int(parts[5]), parts[6], int(parts[7]), int(parts[8]), parts[9], int(parts[10]),
                                                      tuple(int(x) for x in parts[11:]))
        elif line.startswith("loan_repayment: "):
            parts = line.split()
            # id loanId ordinal amount day
            reported_loan_repayments[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]))
        elif line.startswith("enrolment_period: "):
            parts = line.split()
            # id companyId startDay endDay day open
            reported_enrolment_periods[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]), int(parts[6]))
        elif line.startswith("benefit_enrolment: "):
            parts = line.split()
            # id planId employeeId tier active employeeCost employerCost
            reported_benefit_enrolments[int(parts[1])] = (int(parts[2]), int(parts[3]), parts[4], int(parts[5]), int(parts[6]), int(parts[7]))
        elif line.startswith("vehicle: "):
            parts = line.split()
            # id companyId assetId driverEmployeeId odometer active postedTotal consumption
            reported_vehicles[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]), int(parts[6]), int(parts[7]), int(parts[8]))
        elif line.startswith("vehicle_assignment: "):
            parts = line.split()
            reported_vehicle_assignments[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]))
        elif line.startswith("vehicle_contract: "):
            parts = line.split()
            # id vehicleId kind partnerId start end monthly state day inForce
            reported_vehicle_contracts[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]), int(parts[5]), int(parts[6]), int(parts[7]), parts[8], int(parts[9]), int(parts[10]))
        elif line.startswith("odometer_log: "):
            parts = line.split()
            reported_odometer_logs[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]))
        elif line.startswith("fuel_log: "):
            parts = line.split()
            # id vehicleId odometer litres price amount costId
            reported_fuel_logs[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]), int(parts[6]), int(parts[7]))
        elif line.startswith("vehicle_cost: "):
            parts = line.split()
            # id vehicleId kind amount day periodMonth contractId state posted
            reported_vehicle_costs[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]), int(parts[5]), int(parts[6]), int(parts[7]), parts[8], int(parts[9]))
        elif line.startswith("channel: "):
            parts = line.split()
            # id companyId private archived members messages lastMessageId
            reported_channels[int(parts[1])] = tuple(int(x) for x in parts[2:8])
        elif line.startswith("channel_member: "):
            parts = line.split()
            # id channelId membershipId active readUpTo
            reported_channel_members[int(parts[1])] = tuple(int(x) for x in parts[2:6])
        elif line.startswith("channel_message: "):
            parts = line.split()
            # id channelId senderMembership deleted day
            reported_channel_messages[int(parts[1])] = tuple(int(x) for x in parts[2:6])
        elif line.startswith("announcement: "):
            parts = line.split()
            # id companyId start end withdrawn pinned category reactions notified day stands
            reported_announcements[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]), int(parts[6]), parts[7], int(parts[8]), int(parts[9]), int(parts[10]), int(parts[11]))
        elif line.startswith("reaction: "):
            parts = line.split()
            reported_reactions[int(parts[1])] = (int(parts[2]), int(parts[3]))
        elif line.startswith("notification: "):
            parts = line.split()
            # id recipientMembership kind priority relatedId read dismissed runId day
            reported_notifications[int(parts[1])] = (int(parts[2]), parts[3], parts[4], int(parts[5]), int(parts[6]), int(parts[7]), int(parts[8]), int(parts[9]))
        elif line.startswith("announcement_sweep: "):
            parts = line.split()
            # id announcementId state cursor scanned acted
            reported_announcement_sweeps[int(parts[1])] = (int(parts[2]), parts[3], int(parts[4]), int(parts[5]), int(parts[6]))
        elif line.startswith("kb_article: "):
            parts = line.split()
            # id companyId category state versions publishedVersion views helpful notHelpful tags
            reported_kb_articles[int(parts[1])] = tuple(int(x) for x in parts[2:11])
        elif line.startswith("kb_version: "):
            parts = line.split()
            # id articleId number documentId category tags authorMembership day
            reported_kb_versions[int(parts[1])] = tuple(int(x) for x in parts[2:9])
        elif line.startswith("kb_view: "):
            parts = line.split()
            # id articleId viewerMembership version day
            reported_kb_views[int(parts[1])] = tuple(int(x) for x in parts[2:6])
        elif line.startswith("kb_vote: "):
            parts = line.split()
            # id articleId voterMembership helpful
            reported_kb_votes[int(parts[1])] = tuple(int(x) for x in parts[2:5])
        elif line.split(":", 1)[0] in reported_gov:
            # gov_policy: id companyId category state versions publishedVersion acks requiresAck
            # gov_version: id policyId number documentId category requiresAck acks authorMembership day
            # gov_ack: id policyId number memberMembership day
            # gov_requirement: id companyId certKind roleMask isRequired validityDays state
            # gov_citation: id requirementId subjectMembership certificationId citedByMembership day
            # gov_layout: id memberMembership widgets visibleMask
            parts = line.split()
            reported_gov[parts[0][:-1]][int(parts[1])] = tuple(int(x) for x in parts[2:])
        elif line.startswith("gov_run: "):
            parts = line.split()
            # id companyId state phase day openedByMembership figures(comma-separated)
            reported_gov_runs[int(parts[1])] = (int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]), int(parts[6]), [int(x) for x in parts[7].split(",")])
        elif line.split(":", 1)[0] in reported_ctl:
            # every controls row as the export prints it; compared whole with the line this reader prints of its own
            kind = line.split(":", 1)[0]
            reported_ctl[kind][int(line.split()[1])] = line.strip()
        elif line.startswith("count: controls rows printed = "):
            reported_ctl_printed = int(line.rsplit("=", 1)[1])
        elif line.split(":", 1)[0] in reported_voip:
            # every call and the activity it carried out as the export prints them; compared whole
            reported_voip[line.split(":", 1)[0]][int(line.split()[1])] = line.rstrip("\n")
        elif line.startswith("mrp_requirement: "):
            reported_requirements[int(line.split()[1])] = line.rstrip("\n")
        elif line.startswith("count: requirement rows printed = "):
            reported_requirements_printed = int(line.rsplit("=", 1)[1])
        elif line.split(":", 1)[0] in reported_crm_rows:
            reported_crm_rows[line.split(":", 1)[0]][int(line.split()[1])] = line.rstrip("\n")
        elif line.startswith("count: activity and run rows printed = "):
            reported_crm_rows_printed = int(line.rsplit("=", 1)[1])
        elif line.startswith("crm_lead: "):
            reported_leads[int(line.split()[1])] = line.rstrip("\n")
        elif line.startswith("count: lead rows printed = "):
            reported_leads_printed = int(line.rsplit("=", 1)[1])
        elif line.startswith("codec_sample: "):
            _, kind, i, h = line.split()
            reported_codec[kind][int(i)] = h
        elif line.startswith("audit_caller: ") or line.startswith("audit_company: "):
            kind, entry = audit.parse(line)
            reported_audit[kind].add(entry)
            reported_audit_lines[kind] += 1
        elif line.startswith("count: audit entries under their caller = "):
            reported_audit_printed["caller"] = int(line.rsplit("=", 1)[1])
        elif line.startswith("count: audit entries under their company = "):
            reported_audit_printed["company"] = int(line.rsplit("=", 1)[1])
        elif line.startswith("count: voip rows printed = "):
            reported_voip_printed = int(line.rsplit("=", 1)[1])
        elif line.split(":", 1)[0] in reported_plm:
            # every change, its lines and every production's pin as the export prints them; compared whole
            reported_plm[line.split(":", 1)[0]][int(line.split()[1])] = line.rstrip("\n")
        elif line.startswith("count: plm rows printed = "):
            reported_plm_printed = int(line.rsplit("=", 1)[1])
        elif line.split(":", 1)[0] in reported_esg:
            # every row of the seven ESG tables as the export prints them; compared whole
            reported_esg[line.split(":", 1)[0]][int(line.split()[1])] = line.rstrip("\n")
        elif line.startswith("esg_disclosure: "):
            # a sealed run's disclosure against a prior run (0 for none), then its seven answers of the FRA's form
            run_prior = (int(line.split()[1]), int(line.split()[2]))
            reported_esg_disclosures[run_prior] = [line.rstrip("\n")]
        elif line.startswith("esg_fra: "):
            reported_esg_disclosures[(int(line.split()[1]), int(line.split()[2]))].append(line.rstrip("\n"))
        elif line.startswith("count: esg rows printed = "):
            reported_esg_printed = int(line.rsplit("=", 1)[1])
        elif line.startswith("read_page: "):
            # a page of the read method, in parts as a block is: read_page: <sequence> <part> <hex>
            _, seq, part, hexed = line.split(None, 3)
            read_page_pieces.setdefault(int(seq), {})[int(part)] = hexed.strip()
        elif line.startswith("count: read pages printed = "):
            reported_read_pages = int(line.rsplit("=", 1)[1])
        elif line.startswith("count: read page rows printed = "):
            reported_read_rows = int(line.rsplit("=", 1)[1])
        elif line.startswith("draft: "):
            # every draft as the export prints it; compared whole
            reported_draft[int(line.split()[1])] = line.rstrip("\n")
        elif line.startswith("count: draft rows printed = "):
            reported_draft_printed = int(line.rsplit("=", 1)[1])
        elif line.split(":", 1)[0] in reported_studio:
            # studio_field: id companyId kind code type width scale unique choices state ruleVersion values definedByMembership
            # studio_rule: id fieldId version required minimum maximum writersMask setByMembership day ("-" for no bound)
            # studio_value: id fieldId recordId isSet number day flag choice ruleVersion setByMembership setDay hash
            parts = line.split()
            kind = parts[0][:-1]
            if kind == "studio_field":
                row = (int(parts[2]), parts[3], parts[4]) + tuple(int(x) for x in parts[5:])
            elif kind == "studio_rule":
                row = tuple(int(x) for x in parts[2:5]) + (parts[5], parts[6]) + tuple(int(x) for x in parts[7:])
            else:
                row = tuple(int(x) for x in parts[2:-1]) + (parts[-1],)
            reported_studio[kind][int(parts[1])] = row
        elif line.startswith("count: studio values outside the rule in force = "):
            reported_studio_outside = int(line.rsplit("=", 1)[1])
        elif line.split(":", 1)[0] in reported_wf:
            # wf_cycle: id companyId kind steps isActive
            # wf_request: id companyId kind recordId requesterMembership steps currentStep state day decidedDay
            # wf_decision: id instanceId order decidedByMembership onBehalfOfMembership approve day
            # wf_delegation: id fromMembership toMembership fromDay untilDay state
            parts = line.split()
            reported_wf[parts[0][:-1]][int(parts[1])] = tuple(int(x) for x in parts[2:])
        elif line.startswith("consolidation: "):
            parts = line.split()
            # id groupId kind state fromDay throughDay members lines eliminations atBlock tip hash debits credits difference [company counterparty code debit credit]*
            tail = parts[16:]
            entries = tuple((int(tail[i]), int(tail[i + 1]), tail[i + 2], int(tail[i + 3]), int(tail[i + 4])) for i in range(0, len(tail), 5))
            reported_consolidations[int(parts[1])] = (int(parts[2]), parts[3], parts[4], int(parts[5]), int(parts[6]), int(parts[7]), int(parts[8]), int(parts[9]),
                                                      int(parts[10]), parts[11], parts[12], int(parts[13]), int(parts[14]), int(parts[15]), entries)
        elif line.startswith("tip: "):
            tip = bytes.fromhex(line.split(None, 1)[1])

    blocks = []
    for idx, parts in pieces.items():
        # a part missing from the middle would silently shorten the block, so the parts must be
        # exactly 0..n-1 with none absent
        if sorted(parts) != list(range(len(parts))):
            print("ORACLE: block %d is missing one of its parts" % idx)
            return 1
        blocks.append((idx, bytes.fromhex("".join(parts[i] for i in range(len(parts))))))

    faults = []
    store = Store()
    prev = None
    decoded = []
    for i, (idx, raw) in enumerate(sorted(blocks)):
        try:
            b = decode_block(i, raw)
            decoded.append(b)
            if b["index"] != i:
                faults.append("block %d carries index %d" % (i, b["index"]))
                break
            if b["parent"] != prev:
                faults.append("block %d does not link to the block below it" % i)
                break
            # the command hash, re-derived under the version the BLOCK recorded
            if b["command"]["family"] == "bootstrapCompany":
                # re-derive the hash under the version the BLOCK recorded, from bytes this module
                # wrote itself - a reader that can only decode cannot check that what it read is
                # what the contract hashed
                command_hash(b["version"], b["command"])
            prev = b["hash"]
            store.apply(b)
            store.blocks_applied += 1
        except ValueError as e:
            faults.append(str(e))
            break

    if tip is not None and prev != tip:
        faults.append("the last block's hash is not the tip the contract published")

    print("count: blocks read = %d" % len(blocks))
    print("count: blocks folded = %d" % store.blocks_applied)
    print("count: companies reconstructed = %d" % len(store.companies))
    print("count: distinct slugs = %d" % len(store.by_slug))
    hrs = store.hr.summary()
    for k in ("members", "balances", "requests", "approved", "punches", "paired_punches",
              "open_punches", "corrected_punches"):
        print("count: hr %s = %d" % (k, hrs[k]))
    pays = store.pay.summary()
    for k in ("profiles", "brackets", "compensations", "runs", "payslips"):
        print("count: payroll %s = %d" % (k, pays[k]))
    led = store.ledger.summary()
    for k in ("accounts", "journals", "moves", "posted_moves", "closes", "closed", "statements", "published", "deferrals", "recognitions", "revaluations", "assets", "charges"):
        print("count: ledger %s = %d" % (k, led[k]))
    faults.extend(store.hr.faults)
    faults.extend(store.pay.faults)
    faults.extend(store.ledger.faults)
    stk = store.stock.summary()
    for k in ("locations", "lots", "costings", "pickings", "validated_pickings", "quants", "layers"):
        print("count: stock %s = %d" % (k, stk[k]))
    faults.extend(store.stock.faults)
    crms = store.crm.summary()
    for k in ("leads", "mailings", "recipients", "segments", "campaigns", "audience", "engagements", "suppressions"):
        print("count: crm %s = %d" % (k, crms[k]))
    faults.extend(store.crm.faults)
    exps = store.expenses.summary()
    for k in ("categories", "rates", "claims", "lines", "approved", "settled"):
        print("count: expenses %s = %d" % (k, exps[k]))
    faults.extend(store.expenses.faults)
    pays_out = store.payments.summary()
    for k in ("bills", "matched", "bank_accounts", "payments", "accepted", "rejected"):
        print("count: payments %s = %d" % (k, pays_out[k]))
    faults.extend(store.payments.faults)
    stmts = store.statements.summary()
    for k in ("statements", "from_camt", "lines"):
        print("count: statements %s = %d" % (k, stmts[k]))
    faults.extend(store.statements.faults)
    crd = store.credit.summary()
    for k in ("terms", "items", "open", "settled", "runs", "charges"):
        print("count: credit %s = %d" % (k, crd[k]))
    cons = store.consolidation.summary()
    for k in ("groups", "members", "links", "consolidations", "published", "eliminations"):
        print("count: consolidation %s = %d" % (k, cons[k]))
    mnt = store.maintenance.summary()
    for k in ("equipment", "plans", "runs", "work_orders", "done", "downtime_rows"):
        print("count: maintenance %s = %d" % (k, mnt[k]))
    mfg = store.manufacturing.summary()
    for k in ("boms", "productions", "produced"):
        print("count: manufacturing %s = %d" % (k, mfg[k]))
    faults.extend(store.manufacturing.faults)
    qc = store.quality.summary()
    for k in ("control_points", "checks", "passed", "non_conformances", "decided"):
        print("count: quality %s = %d" % (k, qc[k]))
    hd = store.helpdesk.summary()
    for k in ("teams", "stages", "service_levels", "tickets", "closed", "escalated", "messages", "runs"):
        print("count: helpdesk %s = %d" % (k, hd[k]))
    prj = store.projects.summary()
    for k in ("tasks", "entries", "timesheets", "approved_minutes"):
        print("count: projects %s = %d" % (k, prj[k]))
    faults.extend(store.projects.faults)
    fsv = store.fieldservice.summary()
    for k in ("rates", "visits", "done", "invoiced", "parts"):
        print("count: field service %s = %d" % (k, fsv[k]))
    apts = store.appointments.summary()
    for k in ("resources", "bookings", "confirmed", "late_cancellations"):
        print("count: appointments %s = %d" % (k, apts[k]))
    subs = store.subscriptions.summary()
    for k in ("subscriptions", "active", "invoices", "prorations", "runs"):
        print("count: subscriptions %s = %d" % (k, subs[k]))
    rnt = store.rental.summary()
    for k in ("items", "rentals", "out", "returned", "late"):
        print("count: rental %s = %d" % (k, rnt[k]))
    tills = store.pos.summary()
    for k in ("shops", "sessions", "posted", "sales", "kinds"):
        print("count: point of sale %s = %d" % (k, tills[k]))
    rest = store.rst.summary()
    for k in ("tables", "tabs", "paid", "shares"):
        print("count: restaurant %s = %d" % (k, rest[k]))
    shop = store.web.summary()
    for k in ("storefronts", "listings", "carts", "orders", "fulfilled", "holds"):
        print("count: web shop %s = %d" % (k, shop[k]))
    pages = store.site.summary()
    for k in ("pages", "live", "versions"):
        print("count: website %s = %d" % (k, pages[k]))
    posts = store.blog.summary()
    for k in ("posts", "live", "revisions"):
        print("count: blog %s = %d" % (k, posts[k]))
    talk = store.forum.summary()
    for k in ("boards", "topics", "replies", "moderations", "hidden", "idea boards", "idea decisions", "votes up"):
        print("count: forum %s = %d" % (k, talk[k]))
    print("count: idea acts held to their rules = %d" % store.forum.idea_acts_held)
    desk = store.chat.summary()
    for k in ("operators", "conversations", "open", "waiting", "messages"):
        print("count: chat %s = %d" % (k, desk[k]))
    flows = store.auto.summary()
    for k in ("workflows", "steps", "participants", "runs", "waves"):
        print("count: automation %s = %d" % (k, flows[k]))
    texts = store.sms.summary()
    for k in ("mailings", "copies", "suppressions", "numbers normalised"):
        print("count: sms %s = %d" % (k, texts[k]))
    voices = store.social.summary()
    for k in ("accounts", "posts", "posted"):
        print("count: social %s = %d" % (k, voices[k]))
    shows = store.events.summary()
    for k in ("events", "tickets", "seats sold", "attended", "responses", "places taken"):
        print("count: events %s = %d" % (k, shows[k]))
    print("count: members' answers held to their rules = %d" % store.events.responses_held)
    asks = store.surveys.summary()
    for k in ("surveys", "questions", "responses", "answers"):
        print("count: surveys %s = %d" % (k, asks[k]))
    rates = store.appraisals.summary()
    for k in ("cycles", "reviews", "goals", "key results", "recognitions"):
        print("count: appraisals %s = %d" % (k, rates[k]))
    lessons = store.learning.summary()
    for k in ("courses", "paths", "enrolments", "certifications", "skills", "endorsements", "mentorships"):
        print("count: learning %s = %d" % (k, lessons[k]))
    rewards = store.compensation.summary()
    for k in ("bands", "reviews", "grants", "scores", "payments", "loans", "repayments", "benefit plans", "enrolments"):
        print("count: compensation %s = %d" % (k, rewards[k]))
    wheels = store.fleet.summary()
    for k in ("vehicles", "assignments", "contracts", "readings", "fuellings", "costs"):
        print("count: fleet %s = %d" % (k, wheels[k]))
    talk = store.discuss.summary()
    for k in ("channels", "channel members", "messages", "announcements", "reactions", "notifications", "sweeps"):
        print("count: discussion %s = %d" % (k, talk[k]))
    know = store.knowledge.summary()
    for k in ("articles", "versions", "views", "votes", "published"):
        print("count: knowledge %s = %d" % (k, know[k]))
    gv = store.governance.summary()
    for k in ("policies", "versions", "acknowledgements", "requirements", "citations", "layouts", "runs"):
        print("count: governance %s = %d" % (k, gv[k]))
    wfs = store.workflow.summary()
    for k in ("cycles", "requests", "decisions", "delegations"):
        print("count: workflow %s = %d" % (k, wfs[k]))
    sts = store.studio.summary()
    for k in ("fields", "rules", "values", "values set"):
        print("count: studio %s = %d" % (k, sts[k]))
    cts = store.controls.summary()
    for k in ("postings", "confirmations", "profiles", "runs", "sealed", "slices", "findings", "criteria restated", "procedures", "conclusions"):
        print("count: controls %s = %d" % (k, cts[k]))
    vos = store.voip.summary()
    for k in ("calls", "recorded", "activities"):
        print("count: voip %s = %d" % (k, vos[k]))
    gs = store.gate.summary()
    print("count: blocks whose sender the reader held to its own holders table = %d" % gs["blocks_checked"])
    print("count: drafted acts whose acceptor the reader held to its own holders table = %d" % gs["drafted_checked"])
    print("count: founders the reader admitted as administrator at their company's bootstrap = %d" % gs["founders_admitted"])
    print("count: membership acts held to the administrator's rule for the reserved roles = %d" % gs["reserved_checked"])
    print("count: platform operators the log names = %d" % gs["operator_named"])
    aus = store.audit.summary()
    print("count: audit entries the reader wrote under their caller = %d" % aus["by caller"])
    print("count: audit entries the reader wrote under their company = %d" % aus["by company"])
    pls = store.plm.summary()
    for k in ("changes", "versions", "pins"):
        print("count: plm %s = %d" % (k, pls[k]))
    drs = store.draft.summary()
    for k in ("drafts", "accepted", "rejected"):
        print("count: drafts %s = %d" % (k, drs[k]))
    ess = store.esg.summary()
    for k in ("gwp sets", "factor versions", "rules", "activities", "runs", "runs sealed", "slices walked", "lines weighed",
              "activities weighed", "figures"):
        print("count: esg %s = %d" % (k, ess[k]))

    # THE CAMPAIGN, COMPARED FIGURE BY FIGURE. The state and the winner, the audience and each
    # arm's hand, what each arm sent, what the relay said, and the suppressions standing at the
    # end - every one recomputed from the log by this reader's own statement of the rules.
    if reported_campaigns:
        for cid, reported in reported_campaigns.items():
            if cid not in store.crm.campaigns:
                print("ORACLE: the contract reported campaign %d, which the log does not hold" % cid)
                faults.append("campaign %d missing" % cid)
                continue
            mine = store.crm.campaign_line(cid)
            if mine != reported:
                print("ORACLE: campaign %d disagrees - reader %r, contract %r" % (cid, mine, reported))
                faults.append("campaign %d disagrees" % cid)
        print("count: campaigns compared figure by figure = %d" % len(reported_campaigns))

    # THE STOCK, COMPARED ROW BY ROW. Every quant, every layer and every validated picking's value
    # the contract exported must be what this reader's own arithmetic arrives at from the bytes.
    if reported_quants or reported_layers or reported_pickings:
        mine_q = {qid: (q["companyId"], q["locationId"], q["categoryId"], q["lotId"], q["quantity"]) for qid, q in store.stock.quants.items()}
        mine_l = {lid: (l["companyId"], l["categoryId"], l["locationId"], l["sequence"], l["quantityRemaining"], l["unitCost"]) for lid, l in store.stock.layers.items()}
        mine_p = {pid: (p["state"], p["value"], p["valuationMoveId"]) for pid, p in store.stock.pickings.items()}
        if mine_q != reported_quants:
            print("ORACLE: the quants disagree - reader %r, contract %r" % (mine_q, reported_quants))
            faults.append("quants disagree")
        if mine_l != reported_layers:
            print("ORACLE: the layers disagree - reader %r, contract %r" % (mine_l, reported_layers))
            faults.append("layers disagree")
        if reported_pickings != mine_p:
            print("ORACLE: the pickings disagree - reader %r, contract %r" % (mine_p, reported_pickings))
            faults.append("pickings disagree")
        for pid, (state, value, move_id) in reported_pickings.items():
            if state == "done" and (value > 0) != (move_id > 0):
                print("ORACLE: picking %d carries value %d but %s" % (pid, value, "no journal entry" if move_id == 0 else "a journal entry"))
                faults.append("picking %d valuation entry" % pid)
        mine_v = {k: store.stock.stock_value(*k) for k in reported_values}
        if mine_v != reported_values:
            print("ORACLE: the stock values disagree - reader %r, contract %r" % (mine_v, reported_values))
            faults.append("stock values disagree")
        print("count: quants compared = %d" % len(reported_quants))
        print("count: layers compared = %d" % len(reported_layers))
        print("count: validated pickings valued alike = %d" % sum(1 for p in reported_pickings.values() if p[0] == "done"))
        print("count: stock values compared = %d" % len(reported_values))

    if led["posted_moves"] > 0:
        # THE SERIES. Contiguous from 1, per journal and year, over the full set.
        for bad in store.ledger.gapless():
            print("ORACLE: the numbering series has a gap or a duplicate - " + bad)
            faults.append("numbering series " + bad)

        # THE TRIAL BALANCE, TWICE. Two walks of the same data that must agree; a single walk would
        # carry an indexing mistake straight through.
        by_move = store.ledger.trial_balance_by_move()
        by_account = store.ledger.trial_balance_by_account()
        if by_move != by_account:
            print("ORACLE: the two trial-balance walks disagree")
            faults.append("trial balance walks disagree")
        debits = sum(d for d, _c in by_move.values())
        credits = sum(c for _d, c in by_move.values())
        if debits != credits:
            print("ORACLE: the trial balance does not balance: %d against %d" % (debits, credits))
            faults.append("trial balance does not balance")
        print("count: accounts with postings = %d" % len(by_move))
        print("count: trial-balance debits, minor units = %d" % debits)

        # BEANCOUNT. A verifier nobody here wrote, applying its own double-entry rules.
        bean = store.ledger.to_beancount()
        ran, ok, message = accounting.run_bean_check(bean)
        if not ran:
            print("ORACLE: %s - the emitted ledger was not externally verified" % message)
            faults.append("bean-check did not run")
        elif not ok:
            print("ORACLE: bean-check rejected the emitted ledger: " + message[:400])
            faults.append("bean-check rejected the ledger")
        else:
            print("count: postings beancount accepted = %d" % led["posted_moves"])
            # AND THE VERIFIER IS CONNECTED: the same ledger with one posting moved by a minor unit
            # must be REFUSED. Acceptance means nothing without it.
            ran2, rejected, msg2 = accounting.bean_check_is_connected(bean)
            if not ran2 or not rejected:
                print("ORACLE: beancount accepted a ledger that does not balance - %s" % msg2[:200])
                faults.append("bean-check is not connected")
            else:
                print("count: deliberately broken ledgers beancount refused = 1")

        # THE HLEDGER JOURNAL, re-read by a parser that shares nothing with the emitter - so the
        # emitter is checked even where the `hledger` binary is not installed.
        journal = store.ledger.to_hledger()
        reparsed = accounting.parse_hledger(journal)
        expected = {}
        for aid, (d, c) in by_move.items():
            expected[store.ledger.bean_name(aid)] = d - c
        if reparsed != expected:
            print("ORACLE: the hledger journal does not re-read to the balances it was written from")
            for k in sorted(set(list(reparsed) + list(expected)))[:5]:
                print("ORACLE:   %s emitted %s re-read %s" % (k, expected.get(k), reparsed.get(k)))
            faults.append("hledger journal does not round-trip")
        else:
            print("count: hledger accounts that round-tripped = %d" % len(reparsed))

        # THE CLOSE, COMPARED FIGURE BY FIGURE. The state, the period, the plan's size and hash, the
        # result, the moves posted, the lock, and what retained earnings carries - every one
        # recomputed from the log by this reader's own refold of the sweep.
        if reported_closes:
            for rid, reported in reported_closes.items():
                if rid not in store.ledger.closes:
                    print("ORACLE: the contract reported close run %d, which the log does not hold" % rid)
                    faults.append("close %d missing" % rid)
                    continue
                mine = store.ledger.close_line(rid)
                if mine != reported:
                    print("ORACLE: close run %d disagrees - reader %r, contract %r" % (rid, mine, reported))
                    faults.append("close %d disagrees" % rid)
            print("count: closes compared figure by figure = %d" % len(reported_closes))
        # THE STATEMENTS, COMPARED FIGURE BY FIGURE, AND ANCHORED. Each one recomputed from the log
        # over its window by this reader's own rules and hashed with the block and the tip it names;
        # and the tip it names must be the hash of the block before the one that sealed it, which
        # this reader verified link by link - so a statement is believed from the log alone.
        if reported_statements:
            hashes = {b["index"]: b["hash"] for b in decoded}
            anchored = 0
            for sid, reported in reported_statements.items():
                if sid not in store.ledger.statements:
                    print("ORACLE: the contract reported statement %d, which the log does not hold" % sid)
                    faults.append("statement %d missing" % sid)
                    continue
                mine = store.ledger.statement_line(sid)
                if mine != reported:
                    print("ORACLE: statement %d disagrees - reader %r, contract %r" % (sid, mine, reported))
                    faults.append("statement %d disagrees" % sid)
                s = store.ledger.statements[sid]
                if s["state"] == "published":
                    before = hashes.get(s["atBlock"] - 1) if s["atBlock"] > 0 else None
                    if (before or bytes(32)) == s["tip"]:
                        anchored += 1
                    else:
                        print("ORACLE: statement %d names a tip that is not the hash of block %d" % (sid, s["atBlock"] - 1))
                        faults.append("statement %d is not anchored" % sid)
            print("count: statements compared figure by figure = %d" % len(reported_statements))
            print("count: statements anchored to the block before theirs = %d" % anchored)

        # THE DEFERRALS, COMPARED TO THE MINOR UNIT. Every schedule recomputed by this reader's own
        # calendar arithmetic and integer division - each month's part, its month-end, the day it was
        # posted where that month was locked, and what the deferral has recognised so far.
        if reported_deferrals:
            parts_compared = 0
            for did, reported in reported_deferrals.items():
                if did not in store.ledger.deferrals:
                    print("ORACLE: the contract reported deferral %d, which the log does not hold" % did)
                    faults.append("deferral %d missing" % did)
                    continue
                mine = store.ledger.deferral_line(did)
                if mine != reported:
                    print("ORACLE: deferral %d disagrees - reader %r, contract %r" % (did, mine, reported))
                    faults.append("deferral %d disagrees" % did)
                parts_compared += len(reported[6])
            print("count: deferrals compared figure by figure = %d" % len(reported_deferrals))
            print("count: deferral parts compared to the minor unit = %d" % parts_compared)

        # THE REVALUATIONS, COMPARED TO THE MINOR UNIT under the declared exponents and rounding.
        if reported_revaluations:
            for rid, reported in reported_revaluations.items():
                if rid not in store.ledger.revaluations:
                    print("ORACLE: the contract reported revaluation %d, which the log does not hold" % rid)
                    faults.append("revaluation %d missing" % rid)
                    continue
                mine = store.ledger.revaluation_line(rid)
                if mine != reported:
                    print("ORACLE: revaluation %d disagrees - reader %r, contract %r" % (rid, mine, reported))
                    faults.append("revaluation %d disagrees" % rid)
            print("count: revaluations compared figure by figure = %d" % len(reported_revaluations))

        # THE ASSETS, COMPARED TO THE MINOR UNIT: every charge recomputed by this reader's own rule - 
        # what is left over the months that are left - on its month-end or on the first open day, and
        # every event's result against the carrying value the reader keeps.
        if reported_assets:
            charges_compared = 0
            for aid, reported in reported_assets.items():
                if aid not in store.ledger.assets:
                    print("ORACLE: the contract reported asset %d, which the log does not hold" % aid)
                    faults.append("asset %d missing" % aid)
                    continue
                mine = store.ledger.asset_line(aid)
                if mine != reported:
                    print("ORACLE: asset %d disagrees - reader %r, contract %r" % (aid, mine, reported))
                    faults.append("asset %d disagrees" % aid)
                charges_compared += len(reported[9])
            print("count: assets compared figure by figure = %d" % len(reported_assets))
            print("count: depreciation charges compared to the minor unit = %d" % charges_compared)

        # THE CLAIMS, COMPARED TO THE MINOR UNIT: every rate line repriced by this reader at the rate
        # IT finds in force on the line's day, half to even, every total summed again, and whether the
        # claim posted and settled by the reader's own state machine.
        if reported_claims:
            lines_compared = 0
            for cid, reported in reported_claims.items():
                if cid not in store.expenses.claims:
                    print("ORACLE: the contract reported claim %d, which the log does not hold" % cid)
                    faults.append("claim %d missing" % cid)
                    continue
                mine = store.expenses.claim_line(cid)
                if mine != reported:
                    print("ORACLE: claim %d disagrees - reader %r, contract %r" % (cid, mine, reported))
                    faults.append("claim %d disagrees" % cid)
                lines_compared += len(reported[5])
            print("count: claims compared figure by figure = %d" % len(reported_claims))
            print("count: claim lines repriced to the minor unit = %d" % lines_compared)

        # THE PAYMENTS, COMPARED BYTE FOR BYTE: every pacs.008 rebuilt by this reader's own writer from
        # the rows it folded - the UETR it derives, the day it formats, the amount it writes - and its
        # SHA-256 required to be the fingerprint the contract fixed; the state and whether it posted.
        if reported_payments:
            for pid, reported in reported_payments.items():
                if pid not in store.payments.payments:
                    print("ORACLE: the contract reported payment %d, which the log does not hold" % pid)
                    faults.append("payment %d missing" % pid)
                    continue
                mine = store.payments.payment_line(pid)
                if mine != reported:
                    print("ORACLE: payment %d disagrees - reader %r, contract %r" % (pid, mine, reported))
                    faults.append("payment %d disagrees" % pid)
            print("count: payments compared figure by figure = %d" % len(reported_payments))
            print("count: pacs.008 messages rebuilt under the same fingerprint = %d" % sum(1 for pid, r in reported_payments.items() if pid in store.payments.payments and store.payments.payments[pid]["hash"].hex() == r[5]))

        # THE STATEMENTS FROM THE BANK, READ AGAIN: every camt.053 the contract folded is parsed here
        # by Python's own parser into the same statement and lines, held to the official schema where
        # the hub's copy of it is on this machine, and required to be the fixture file it says it is.
        if reported_camt:
            for sid, reported in reported_camt.items():
                if sid not in store.statements.statements:
                    print("ORACLE: the contract reported statement %d, which the log does not hold" % sid)
                    faults.append("statement %d missing" % sid)
                    continue
                mine = store.statements.camt_line(sid)
                if mine != reported:
                    print("ORACLE: statement %d disagrees - reader %r, contract %r" % (sid, mine, reported))
                    faults.append("statement %d disagrees" % sid)
            print("count: camt.053 statements compared figure by figure = %d" % len(reported_camt))
            print("count: camt.053 lines compared to the minor unit = %d" % sum(len(r[8]) for r in reported_camt.values()))
            valid = 0
            carried = 0
            for sid, raw in store.statements.camt_messages:
                v = statements.schema_valid(raw)
                if v is None:
                    print("note: the official camt.053.001.08 schema is not on this machine (the hub is not beside this tree); the message was not held to it")
                elif v:
                    valid += 1
                else:
                    print("ORACLE: the camt.053 behind statement %d is not valid against the official schema" % sid)
                    faults.append("statement %d schema" % sid)
                name = statements.fixture_named(raw)
                if name is None:
                    print("ORACLE: the camt.053 behind statement %d is not, byte for byte, a fixture file under test/fixtures/camt053/" % sid)
                    faults.append("statement %d fixture" % sid)
                else:
                    carried += 1
            print("count: camt.053 messages valid against the official schema = %d" % valid)
            print("count: camt.053 messages that are their fixture file byte for byte = %d" % carried)

        # THE CREDIT ACCOUNT, COMPARED TO THE MINOR UNIT: every open item as this reader kept it - the
        # reservation, the invoice it opened on and the due day the terms gave it, what settled it, the
        # late charge charged once and the interest recomputed by this reader's own Fraction arithmetic
        # for the days it finds - and every terms row with its exposure, which the reader also sums
        # again from the live items.
        if reported_items or reported_terms:
            interest_compared = 0
            for iid, reported in reported_items.items():
                if iid not in store.credit.items:
                    print("ORACLE: the contract reported open item %d, which the log does not hold" % iid)
                    faults.append("open item %d missing" % iid)
                    continue
                mine = store.credit.item_line(iid)
                if mine != reported:
                    print("ORACLE: open item %d disagrees - reader %r, contract %r" % (iid, mine, reported))
                    faults.append("open item %d disagrees" % iid)
                if reported[12] > 0:
                    interest_compared += 1
            for tid, reported in reported_terms.items():
                if tid not in store.credit.terms:
                    print("ORACLE: the contract reported credit terms %d, which the log does not hold" % tid)
                    faults.append("credit terms %d missing" % tid)
                    continue
                mine = store.credit.terms_line(tid)
                if mine != reported:
                    print("ORACLE: credit terms %d disagree - reader %r, contract %r" % (tid, mine, reported))
                    faults.append("credit terms %d disagree" % tid)
            print("count: open items compared figure by figure = %d" % len(reported_items))
            print("count: credit terms compared figure by figure = %d" % len(reported_terms))
            print("count: interest charges recomputed to the minor unit = %d" % interest_compared)
        faults.extend(store.credit.faults)

        # THE CONSOLIDATIONS, REFOLDED. Every one the contract published is recomputed here from the
        # member statements it names - each already refolded from the log and anchored above - summed
        # by account code, with this reader's own reversal of every intercompany line over the window
        # and its own difference, chained and hashed as the contract states it, and required to be
        # anchored to the block before its own.
        if reported_consolidations:
            anchored = 0
            entries_compared = 0
            block_hashes = {b["index"]: b["hash"] for b in decoded}
            for cid, reported in reported_consolidations.items():
                if cid not in store.consolidation.consolidations:
                    print("ORACLE: the contract reported consolidation %d, which the log does not hold" % cid)
                    faults.append("consolidation %d missing" % cid)
                    continue
                mine = store.consolidation.consolidation_line(cid)
                if mine != reported:
                    print("ORACLE: consolidation %d disagrees - reader %r, contract %r" % (cid, mine, reported))
                    faults.append("consolidation %d disagrees" % cid)
                else:
                    entries_compared += len(reported[14])
                x = store.consolidation.consolidations[cid]
                if x["state"] == "published":
                    before = block_hashes.get(x["atBlock"] - 1) if x["atBlock"] > 0 else None
                    if (before or bytes(32)) == x["tip"]:
                        anchored += 1
                    else:
                        print("ORACLE: consolidation %d names a tip that is not the hash of block %d" % (cid, x["atBlock"] - 1))
                        faults.append("consolidation %d is not anchored" % cid)
            print("count: consolidations compared figure by figure = %d" % len(reported_consolidations))
            print("count: elimination entries recomputed to the minor unit = %d" % entries_compared)
            print("count: consolidations anchored to the block before theirs = %d" % anchored)
        faults.extend(store.consolidation.faults)

        # THE REGISTER, THE PLANS AND THE WORK ORDERS, COMPARED. Every plan's next due day by this
        # reader's own advancement rule, every work order's days and the picking that consumed its
        # parts - which this reader made and validated through its own stock fold - and every piece
        # of equipment's downtime, summed again from its rows.
        if reported_equipment or reported_plans or reported_work_orders:
            parts_pickings = 0
            for eid, reported in reported_equipment.items():
                if eid not in store.maintenance.equipment:
                    print("ORACLE: the contract reported equipment %d, which the log does not hold" % eid)
                    faults.append("equipment %d missing" % eid)
                    continue
                mine = store.maintenance.equipment_line(eid)
                if mine != reported:
                    print("ORACLE: equipment %d disagrees - reader %r, contract %r" % (eid, mine, reported))
                    faults.append("equipment %d disagrees" % eid)
            for pid, reported in reported_plans.items():
                if pid not in store.maintenance.plans:
                    print("ORACLE: the contract reported maintenance plan %d, which the log does not hold" % pid)
                    faults.append("maintenance plan %d missing" % pid)
                    continue
                mine = store.maintenance.plan_line(pid)
                if mine != reported:
                    print("ORACLE: maintenance plan %d disagrees - reader %r, contract %r" % (pid, mine, reported))
                    faults.append("maintenance plan %d disagrees" % pid)
            for oid, reported in reported_work_orders.items():
                if oid not in store.maintenance.work_orders:
                    print("ORACLE: the contract reported work order %d, which the log does not hold" % oid)
                    faults.append("work order %d missing" % oid)
                    continue
                mine = store.maintenance.work_order_line(oid)
                if mine != reported:
                    print("ORACLE: work order %d disagrees - reader %r, contract %r" % (oid, mine, reported))
                    faults.append("work order %d disagrees" % oid)
                elif reported[9] and store.stock.pickings.get(reported[9], {}).get("state") == "done":
                    parts_pickings += 1
            print("count: equipment compared figure by figure = %d" % len(reported_equipment))
            print("count: maintenance plans compared figure by figure = %d" % len(reported_plans))
            print("count: work orders compared figure by figure = %d" % len(reported_work_orders))
            print("count: parts pickings refolded through the reader's stock fold = %d" % parts_pickings)
        faults.extend(store.maintenance.faults)

        # THE CONTROL POINTS, THE CHECKS AND THE NON-CONFORMANCES, COMPARED. Every check's verdict and
        # record, every record's disposition and the day it was decided, every point's count summed
        # again from the checks - and the scrapped delivery's goods, a picking this reader made and
        # validated through its own stock fold. The hold itself is checked at every validation and
        # every production above: a block that moved held goods is a fault.
        if reported_control_points or reported_checks or reported_nonconformances:
            scrap_pickings = 0
            for pid, reported in reported_control_points.items():
                if pid not in store.quality.control_points:
                    print("ORACLE: the contract reported control point %d, which the log does not hold" % pid)
                    faults.append("control point %d missing" % pid)
                    continue
                mine = store.quality.control_point_line(pid)
                if mine != reported:
                    print("ORACLE: control point %d disagrees - reader %r, contract %r" % (pid, mine, reported))
                    faults.append("control point %d disagrees" % pid)
            for cid, reported in reported_checks.items():
                if cid not in store.quality.checks:
                    print("ORACLE: the contract reported quality check %d, which the log does not hold" % cid)
                    faults.append("quality check %d missing" % cid)
                    continue
                mine = store.quality.check_line(cid)
                if mine != reported:
                    print("ORACLE: quality check %d disagrees - reader %r, contract %r" % (cid, mine, reported))
                    faults.append("quality check %d disagrees" % cid)
            for nid, reported in reported_nonconformances.items():
                if nid not in store.quality.non_conformances:
                    print("ORACLE: the contract reported non-conformance %d, which the log does not hold" % nid)
                    faults.append("non-conformance %d missing" % nid)
                    continue
                mine = store.quality.nonconformance_line(nid)
                if mine != reported:
                    print("ORACLE: non-conformance %d disagrees - reader %r, contract %r" % (nid, mine, reported))
                    faults.append("non-conformance %d disagrees" % nid)
                elif reported[7] and store.stock.pickings.get(reported[7], {}).get("state") == "done":
                    scrap_pickings += 1
            print("count: control points compared figure by figure = %d" % len(reported_control_points))
            print("count: quality checks compared figure by figure = %d" % len(reported_checks))
            print("count: non-conformances compared figure by figure = %d" % len(reported_nonconformances))
            print("count: scrap pickings refolded through the reader's stock fold = %d" % scrap_pickings)
            print("count: productions whose pickings the reader refolded through its stock fold = %d" % mfg["produced"])
        faults.extend(store.quality.faults)

        # THE DESK, COMPARED. Every team's counts summed again from its tickets, every promise, and
        # every ticket - its stage, state, priority and level, and ITS TWO CLOCKS, which this reader
        # walks again over the company's working week and holidays from the day the ticket was opened,
        # and the escalations it re-derived by running the sweep itself over the same head.
        if reported_teams or reported_slas or reported_tickets:
            clocks = 0
            for tid, reported in reported_teams.items():
                if tid not in store.helpdesk.teams:
                    print("ORACLE: the contract reported helpdesk team %d, which the log does not hold" % tid)
                    faults.append("helpdesk team %d missing" % tid)
                    continue
                mine = store.helpdesk.team_line(tid)
                if mine != reported:
                    print("ORACLE: helpdesk team %d disagrees - reader %r, contract %r" % (tid, mine, reported))
                    faults.append("helpdesk team %d disagrees" % tid)
            for lid, reported in reported_slas.items():
                if lid not in store.helpdesk.service_levels:
                    print("ORACLE: the contract reported service level %d, which the log does not hold" % lid)
                    faults.append("service level %d missing" % lid)
                    continue
                mine = store.helpdesk.sla_line(lid)
                if mine != reported:
                    print("ORACLE: service level %d disagrees - reader %r, contract %r" % (lid, mine, reported))
                    faults.append("service level %d disagrees" % lid)
            for tid, reported in reported_tickets.items():
                if tid not in store.helpdesk.tickets:
                    print("ORACLE: the contract reported ticket %d, which the log does not hold" % tid)
                    faults.append("ticket %d missing" % tid)
                    continue
                mine = store.helpdesk.ticket_line(tid)
                if mine != reported:
                    print("ORACLE: ticket %d disagrees - reader %r, contract %r" % (tid, mine, reported))
                    faults.append("ticket %d disagrees" % tid)
                else:
                    clocks += 2
            print("count: helpdesk teams compared figure by figure = %d" % len(reported_teams))
            print("count: service levels compared figure by figure = %d" % len(reported_slas))
            print("count: tickets compared figure by figure = %d" % len(reported_tickets))
            print("count: service-level clocks recomputed by the calendar = %d" % clocks)
            print("count: escalations the reader re-derived by running the sweep = %d" % store.helpdesk.escalations)
        faults.extend(store.helpdesk.faults)

        # THE VISITS, COMPARED. Every rate; every visit - its task, its state, its window and its day,
        # its parts delivery, its labour summed again from the task's approved entries, its order and
        # its move - and every invoice's figures recomputed from the order this reader placed itself.
        if reported_rates or reported_visits:
            invoices = 0
            for company, reported in reported_rates.items():
                if company not in store.fieldservice.rates:
                    print("ORACLE: the contract reported a service rate for company %d, which the log does not hold" % company)
                    faults.append("service rate of company %d missing" % company)
                    continue
                mine = store.fieldservice.rate_line(company)
                if mine != reported:
                    print("ORACLE: the service rate of company %d disagrees - reader %r, contract %r" % (company, mine, reported))
                    faults.append("service rate of company %d disagrees" % company)
            for vid, reported in reported_visits.items():
                if vid not in store.fieldservice.visits:
                    print("ORACLE: the contract reported visit %d, which the log does not hold" % vid)
                    faults.append("visit %d missing" % vid)
                    continue
                mine = store.fieldservice.visit_line(vid, store.projects)
                if mine != reported:
                    print("ORACLE: visit %d disagrees - reader %r, contract %r" % (vid, mine, reported))
                    faults.append("visit %d disagrees" % vid)
            for vid, reported in reported_visit_invoices.items():
                v = store.fieldservice.visits.get(vid)
                o = store.credit.orders.get(v["orderId"]) if v else None
                if o is None:
                    print("ORACLE: the contract reported an invoice for visit %d, which the log does not hold" % vid)
                    faults.append("visit %d's invoice missing" % vid)
                    continue
                untaxed = tax = 0
                for l in o["facts"]["lines"]:
                    sub, t = credit.line_amounts(l["quantity"], l["priceUnit"], l["taxRate"])
                    untaxed += sub
                    tax += t
                mine = (v["orderId"], untaxed, tax, untaxed + tax)
                if mine != reported:
                    print("ORACLE: visit %d's invoice disagrees - reader %r, contract %r" % (vid, mine, reported))
                    faults.append("visit %d's invoice disagrees" % vid)
                else:
                    invoices += 1
            print("count: visits compared figure by figure = %d" % len(reported_visits))
            print("count: labour minutes recomputed from the timesheet = %d" % store.fieldservice.labour_recomputed)
            print("count: visit invoices recomputed to the minor unit = %d" % invoices)
        faults.extend(store.fieldservice.faults)

        # THE BOOKINGS, COMPARED: every resource's count summed again from its bookings, every booking's
        # slot, state and lateness - and every slot checked again against the ones that held the day.
        if reported_resources or reported_bookings:
            for rid, reported in reported_resources.items():
                if rid not in store.appointments.resources:
                    print("ORACLE: the contract reported bookable resource %d, which the log does not hold" % rid)
                    faults.append("bookable resource %d missing" % rid)
                    continue
                mine = store.appointments.resource_line(rid)
                if mine != reported:
                    print("ORACLE: bookable resource %d disagrees - reader %r, contract %r" % (rid, mine, reported))
                    faults.append("bookable resource %d disagrees" % rid)
            for bid, reported in reported_bookings.items():
                if bid not in store.appointments.bookings:
                    print("ORACLE: the contract reported booking %d, which the log does not hold" % bid)
                    faults.append("booking %d missing" % bid)
                    continue
                mine = store.appointments.booking_line(bid)
                if mine != reported:
                    print("ORACLE: booking %d disagrees - reader %r, contract %r" % (bid, mine, reported))
                    faults.append("booking %d disagrees" % bid)
            print("count: bookable resources compared figure by figure = %d" % len(reported_resources))
            print("count: bookings compared figure by figure = %d" % len(reported_bookings))
            print("count: slots checked again against the day's bookings = %d" % store.appointments.slot_checks)
        faults.extend(store.appointments.faults)

        # THE SUBSCRIPTIONS, COMPARED: every subscription's standing with its periods counted again from
        # its invoices, every invoice - a period's amount repriced from the sale this reader placed, a
        # proration's recomputed by this reader's own arithmetic over the calendar's days.
        if reported_subscriptions or reported_subinvoices:
            for sid, reported in reported_subscriptions.items():
                if sid not in store.subscriptions.subscriptions:
                    print("ORACLE: the contract reported subscription %d, which the log does not hold" % sid)
                    faults.append("subscription %d missing" % sid)
                    continue
                mine = store.subscriptions.subscription_line(sid)
                if mine != reported:
                    print("ORACLE: subscription %d disagrees - reader %r, contract %r" % (sid, mine, reported))
                    faults.append("subscription %d disagrees" % sid)
            for iid, reported in reported_subinvoices.items():
                if iid not in store.subscriptions.invoices:
                    print("ORACLE: the contract reported subscription invoice %d, which the log does not hold" % iid)
                    faults.append("subscription invoice %d missing" % iid)
                    continue
                mine = store.subscriptions.invoice_line(iid, store.credit)
                if mine != reported:
                    print("ORACLE: subscription invoice %d disagrees - reader %r, contract %r" % (iid, mine, reported))
                    faults.append("subscription invoice %d disagrees" % iid)
            print("count: subscriptions compared figure by figure = %d" % len(reported_subscriptions))
            print("count: subscription invoices compared to the minor unit = %d" % len(reported_subinvoices))
            print("count: prorations recomputed over the calendar's days = %d" % store.subscriptions.prorations_recomputed)
        faults.extend(store.subscriptions.faults)

        # THE RENTALS, COMPARED: every item's live count summed again, every rental's standing with its
        # late days recomputed from the agreed day and the day of return, and every charge recomputed from
        # the item's rates and the days, repriced by the credit reader's own arithmetic.
        if reported_rental_items or reported_rentals:
            for iid, reported in reported_rental_items.items():
                if iid not in store.rental.items:
                    print("ORACLE: the contract reported item for hire %d, which the log does not hold" % iid)
                    faults.append("rental item %d missing" % iid)
                    continue
                mine = store.rental.item_line(iid)
                if mine != reported:
                    print("ORACLE: item for hire %d disagrees - reader %r, contract %r" % (iid, mine, reported))
                    faults.append("rental item %d disagrees" % iid)
            for rid, reported in reported_rentals.items():
                if rid not in store.rental.rentals:
                    print("ORACLE: the contract reported rental %d, which the log does not hold" % rid)
                    faults.append("rental %d missing" % rid)
                    continue
                mine = store.rental.rental_line(rid)
                if mine != reported:
                    print("ORACLE: rental %d disagrees - reader %r, contract %r" % (rid, mine, reported))
                    faults.append("rental %d disagrees" % rid)
            for rid, reported in reported_rental_charges.items():
                if rid not in store.rental.rentals or store.rental.rentals[rid]["state"] != "returned":
                    print("ORACLE: the contract reported a charge for rental %d, which the log does not hold returned" % rid)
                    faults.append("rental %d's charge missing" % rid)
                    continue
                mine = store.rental.charge_line(rid, store.credit)
                if mine != reported:
                    print("ORACLE: rental %d's charge disagrees - reader %r, contract %r" % (rid, mine, reported))
                    faults.append("rental %d's charge disagrees" % rid)
            print("count: rentals compared figure by figure = %d" % len(reported_rentals))
            print("count: rental charges recomputed to the minor unit = %d" % store.rental.charges_recomputed)
        faults.extend(store.rental.faults)

        # THE TILLS, COMPARED: every shop, every session with its takings, its count of sales and its
        # totals recomputed from the sales this reader folded and the orders it placed for them, the
        # shortfall and the excess recomputed from the count, and every sale.
        if reported_shops or reported_till_sessions:
            for sid, reported in reported_shops.items():
                if sid not in store.pos.shops:
                    print("ORACLE: the contract reported shop %d, which the log does not hold" % sid)
                    faults.append("shop %d missing" % sid)
                    continue
                mine = store.pos.shop_line(sid)
                if mine != reported:
                    print("ORACLE: shop %d disagrees - reader %r, contract %r" % (sid, mine, reported))
                    faults.append("shop %d disagrees" % sid)
            for sid, reported in reported_till_sessions.items():
                if sid not in store.pos.sessions:
                    print("ORACLE: the contract reported till session %d, which the log does not hold" % sid)
                    faults.append("till session %d missing" % sid)
                    continue
                mine = store.pos.session_line(sid, store.credit)
                if mine != reported:
                    print("ORACLE: till session %d disagrees - reader %r, contract %r" % (sid, mine, reported))
                    faults.append("till session %d disagrees" % sid)
            for xid, reported in reported_till_sales.items():
                if xid not in store.pos.sales:
                    print("ORACLE: the contract reported till sale %d, which the log does not hold" % xid)
                    faults.append("till sale %d missing" % xid)
                    continue
                mine = store.pos.sale_line(xid)
                if mine != reported:
                    print("ORACLE: till sale %d disagrees - reader %r, contract %r" % (xid, mine, reported))
                    faults.append("till sale %d disagrees" % xid)
            print("count: till sessions compared figure by figure = %d" % len(reported_till_sessions))
            print("count: till sessions' totals recomputed from their sales = %d" % store.pos.totals_recomputed)
            print("count: till sales compared figure by figure = %d" % len(reported_till_sales))
        faults.extend(store.pos.faults)

        # THE RESTAURANT, COMPARED: every table, every tab with its courses and lines standing recounted
        # and a paid tab's total held to the till's sale, and every share of a split bill recomputed by
        # the largest-remainder rule from the sale's total and the shares' weights.
        if reported_tables or reported_tabs or reported_shares:
            for tid, reported in reported_tables.items():
                if tid not in store.rst.tables:
                    print("ORACLE: the contract reported table %d, which the log does not hold" % tid)
                    faults.append("table %d missing" % tid)
                    continue
                mine = store.rst.table_line(tid)
                if mine != reported:
                    print("ORACLE: table %d disagrees - reader %r, contract %r" % (tid, mine, reported))
                    faults.append("table %d disagrees" % tid)
            for xid, reported in reported_tabs.items():
                if xid not in store.rst.tabs:
                    print("ORACLE: the contract reported tab %d, which the log does not hold" % xid)
                    faults.append("tab %d missing" % xid)
                    continue
                mine = store.rst.tab_line(xid, store.pos)
                if mine != reported:
                    print("ORACLE: tab %d disagrees - reader %r, contract %r" % (xid, mine, reported))
                    faults.append("tab %d disagrees" % xid)
            for sid, reported in reported_shares.items():
                if sid not in store.rst.shares:
                    print("ORACLE: the contract reported bill share %d, which the log does not hold" % sid)
                    faults.append("share %d missing" % sid)
                    continue
                mine = store.rst.share_line(sid, store.pos)
                if mine != reported:
                    print("ORACLE: bill share %d disagrees - reader %r, contract %r" % (sid, mine, reported))
                    faults.append("share %d disagrees" % sid)
            print("count: tabs compared figure by figure = %d" % len(reported_tabs))
            print("count: bill shares recomputed by the rule = %d" % store.rst.shares_recomputed)
        faults.extend(store.rst.faults)

        # THE WEB SHOP, COMPARED: every storefront, every web order with its payment held to the order's
        # total as this reader priced it, and every hold held to its order's line.
        if reported_storefronts or reported_web_orders or reported_holds:
            for sid, reported in reported_storefronts.items():
                if sid not in store.web.storefronts:
                    print("ORACLE: the contract reported storefront %d, which the log does not hold" % sid)
                    faults.append("storefront %d missing" % sid)
                    continue
                mine = store.web.storefront_line(sid)
                if mine != reported:
                    print("ORACLE: storefront %d disagrees - reader %r, contract %r" % (sid, mine, reported))
                    faults.append("storefront %d disagrees" % sid)
            for wid, reported in reported_web_orders.items():
                if wid not in store.web.orders:
                    print("ORACLE: the contract reported web order %d, which the log does not hold" % wid)
                    faults.append("web order %d missing" % wid)
                    continue
                mine = store.web.order_line(wid, store.credit)
                if mine != reported:
                    print("ORACLE: web order %d disagrees - reader %r, contract %r" % (wid, mine, reported))
                    faults.append("web order %d disagrees" % wid)
            for rid, reported in reported_holds.items():
                if rid not in store.web.reservations:
                    print("ORACLE: the contract reported hold %d, which the log does not hold" % rid)
                    faults.append("hold %d missing" % rid)
                    continue
                mine = store.web.reservation_line(rid, store.credit, store.pos)
                if mine != reported:
                    print("ORACLE: hold %d disagrees - reader %r, contract %r" % (rid, mine, reported))
                    faults.append("hold %d disagrees" % rid)
            print("count: web orders compared figure by figure = %d" % len(reported_web_orders))
            print("count: web payments held to their orders' totals = %d" % store.web.payments_held)
            print("count: holds compared figure by figure = %d" % len(reported_holds))
        faults.extend(store.web.faults)

        # THE WEBSITE, COMPARED: every page with its versions recounted, every version with its
        # fingerprint recomputed from the chunks the log carries and held to the fingerprint the contract
        # published and to the one the document declared.
        if reported_pages or reported_versions:
            for pid, reported in reported_pages.items():
                if pid not in store.site.pages:
                    print("ORACLE: the contract reported page %d, which the log does not hold" % pid)
                    faults.append("page %d missing" % pid)
                    continue
                mine = store.site.page_line(pid)
                if mine != reported:
                    print("ORACLE: page %d disagrees - reader %r, contract %r" % (pid, mine, reported))
                    faults.append("page %d disagrees" % pid)
            for vid, reported in reported_versions.items():
                if vid not in store.site.versions:
                    print("ORACLE: the contract reported page version %d, which the log does not hold" % vid)
                    faults.append("page version %d missing" % vid)
                    continue
                mine = store.site.version_line(vid)
                if mine != reported:
                    print("ORACLE: page version %d disagrees - reader %r, contract %r" % (vid, mine, reported))
                    faults.append("page version %d disagrees" % vid)
            print("count: pages compared figure by figure = %d" % len(reported_pages))
            print("count: page fingerprints recomputed from the chunks on the log = %d" % store.site.fingerprints_recomputed)
        faults.extend(store.site.faults)

        # THE BLOG, COMPARED: every post with its day held to the block's and its fingerprint to the chunks.
        if reported_posts:
            for pid, reported in reported_posts.items():
                if pid not in store.blog.posts:
                    print("ORACLE: the contract reported post %d, which the log does not hold" % pid)
                    faults.append("post %d missing" % pid)
                    continue
                mine = store.blog.post_line(pid, store)
                if mine != reported:
                    print("ORACLE: post %d disagrees - reader %r, contract %r" % (pid, mine, reported))
                    faults.append("post %d disagrees" % pid)
            print("count: posts compared figure by figure = %d" % len(reported_posts))
            print("count: post dates held to the day of their block = %d" % store.blog.dates_held)
        faults.extend(store.blog.faults)

        # THE FORUM, COMPARED: every board, topic, reply and moderation, the replies recounted from the log and
        # every moderation held to a second person.
        if reported_topics:
            for name, reported_rows, mine_rows, line_fn in (
                ("board", reported_boards, store.forum.boards, store.forum.board_line),
                ("topic", reported_topics, store.forum.topics, store.forum.topic_line),
                ("reply", reported_replies, store.forum.replies, store.forum.reply_line),
                ("moderation", reported_moderations, store.forum.moderations, store.forum.moderation_line),
            ):
                for rid, reported in reported_rows.items():
                    if rid not in mine_rows:
                        print("ORACLE: the contract reported forum %s %d, which the log does not hold" % (name, rid))
                        faults.append("forum %s %d missing" % (name, rid))
                        continue
                    mine = line_fn(rid)
                    if mine != reported:
                        print("ORACLE: forum %s %d disagrees - reader %r, contract %r" % (name, rid, mine, reported))
                        faults.append("forum %s %d disagrees" % (name, rid))
            print("count: topics compared figure by figure = %d" % len(reported_topics))
            print("count: reply counts recomputed from the replies on the log = %d" % store.forum.reply_counts_recomputed)
            print("count: moderations held to a second person = %d" % store.forum.four_eyes_held)
        faults.extend(store.forum.faults)

        # LIVE CHAT, COMPARED: every operator, conversation and word, the words recounted from the log and every
        # assignment re-derived from the reader's own queue.
        if reported_conversations:
            for name, reported_rows, mine_rows, line_fn in (
                ("operator", reported_operators, store.chat.operators, store.chat.operator_line),
                ("conversation", reported_conversations, store.chat.conversations, store.chat.conversation_line),
                ("message", reported_chat_messages, store.chat.messages, store.chat.message_line),
            ):
                for rid, reported in reported_rows.items():
                    if rid not in mine_rows:
                        print("ORACLE: the contract reported chat %s %d, which the log does not hold" % (name, rid))
                        faults.append("chat %s %d missing" % (name, rid))
                        continue
                    mine = line_fn(rid)
                    if mine != reported:
                        print("ORACLE: chat %s %d disagrees - reader %r, contract %r" % (name, rid, mine, reported))
                        faults.append("chat %s %d disagrees" % (name, rid))
            print("count: conversations compared figure by figure = %d" % len(reported_conversations))
            print("count: message counts recounted from the messages on the log = %d" % store.chat.message_counts_recounted)
            print("count: assignments re-derived from the queue = %d" % store.chat.assignments_rederived)
            print("count: chat stamps re-derived, each on an open storefront of its company = %d" % store.chat.stamps_rederived)
        faults.extend(store.chat.faults)

        # MARKETING AUTOMATION, COMPARED: every workflow, step, participant and run against the reader's own runs,
        # every wave raised through its own mailing fold, every condition decided on the acknowledgements it folded.
        if reported_workflows:
            for name, reported_rows, mine_rows, line_fn in (
                ("workflow", reported_workflows, store.auto.workflows, store.auto.workflow_line),
                ("step", reported_steps, store.auto.steps, store.auto.step_line),
                ("participant", reported_participants, store.auto.participants, store.auto.participant_line),
                ("run", reported_auto_runs, store.auto.runs, store.auto.run_line),
            ):
                for rid, reported in reported_rows.items():
                    if rid not in mine_rows:
                        print("ORACLE: the contract reported automation %s %d, which the log does not hold" % (name, rid))
                        faults.append("automation %s %d missing" % (name, rid))
                        continue
                    mine = line_fn(rid)
                    if mine != reported:
                        print("ORACLE: automation %s %d disagrees - reader %r, contract %r" % (name, rid, mine, reported))
                        faults.append("automation %s %d disagrees" % (name, rid))
            print("count: workflows compared figure by figure = %d" % len(reported_workflows))
            print("count: participants re-derived from the reader's own runs = %d" % len(reported_participants))
            print("count: waves refolded through the reader's mailing fold = %d" % store.auto.waves_refolded)
            print("count: conditions decided on the relay's word = %d" % store.auto.conditions_decided)
        faults.extend(store.auto.faults)

        # SMS MARKETING, COMPARED: every text mailing, copy and suppressed number, the copies recounted by state and
        # every list's hash re-chained from the numbers this reader brought to one form.
        if reported_sms_mailings:
            for name, reported_rows, mine_rows, line_fn in (
                ("text mailing", reported_sms_mailings, store.sms.mailings, store.sms.mailing_line),
                ("copy", reported_sms_recipients, store.sms.recipients, store.sms.recipient_line),
                ("suppression", reported_sms_suppressions, store.sms.suppressions, store.sms.suppression_line),
            ):
                for rid, reported in reported_rows.items():
                    if rid not in mine_rows:
                        print("ORACLE: the contract reported sms %s %d, which the log does not hold" % (name, rid))
                        faults.append("sms %s %d missing" % (name, rid))
                        continue
                    mine = line_fn(rid)
                    if mine != reported:
                        print("ORACLE: sms %s %d disagrees - reader %r, contract %r" % (name, rid, mine, reported))
                        faults.append("sms %s %d disagrees" % (name, rid))
            print("count: text mailings compared figure by figure = %d" % len(reported_sms_mailings))
            print("count: lists re-chained from the numbers on the log = %d" % store.sms.lists_rechained)
            print("count: copies recounted by state = %d" % len(reported_sms_recipients))
        faults.extend(store.sms.faults)

        # SOCIAL MARKETING, COMPARED: every account and post, each claim re-derived from the reader's own queue, every
        # image's fingerprint recomputed from the chunks on the log.
        if reported_social_posts:
            for name, reported_rows, mine_rows, line_fn in (
                ("account", reported_social_accounts, store.social.accounts, store.social.account_line),
                ("post", reported_social_posts, store.social.posts, store.social.post_line),
            ):
                for rid, reported in reported_rows.items():
                    if rid not in mine_rows:
                        print("ORACLE: the contract reported social %s %d, which the log does not hold" % (name, rid))
                        faults.append("social %s %d missing" % (name, rid))
                        continue
                    mine = line_fn(rid)
                    if mine != reported:
                        print("ORACLE: social %s %d disagrees - reader %r, contract %r" % (name, rid, mine, reported))
                        faults.append("social %s %d disagrees" % (name, rid))
            print("count: social posts compared figure by figure = %d" % len(reported_social_posts))
            print("count: claims re-derived from the queue = %d" % store.social.claims_rederived)
            print("count: image fingerprints recomputed from the chunks on the log = %d" % store.social.fingerprints_recomputed)
        faults.extend(store.social.faults)

        # EVENTS, COMPARED: every event and ticket, the seats and the attendance recounted from the tickets, every
        # ticket's sale raised through the reader's own order fold and its amount recomputed.
        if reported_events:
            for name, reported_rows, mine_rows, line_fn in (
                ("event", reported_events, store.events.events, store.events.event_line),
                ("ticket", reported_event_tickets, store.events.tickets, store.events.ticket_line),
            ):
                for rid, reported in reported_rows.items():
                    if rid not in mine_rows:
                        print("ORACLE: the contract reported %s %d, which the log does not hold" % (name, rid))
                        faults.append("%s %d missing" % (name, rid))
                        continue
                    mine = line_fn(rid)
                    if mine != reported:
                        print("ORACLE: %s %d disagrees - reader %r, contract %r" % (name, rid, mine, reported))
                        faults.append("%s %d disagrees" % (name, rid))
            print("count: events compared figure by figure = %d" % len(reported_events))
            print("count: tickets raised through the reader's order fold = %d" % store.events.tickets_raised)
            print("count: attendance held to the seats = %d" % store.events.attendance_held)
        faults.extend(store.events.faults)

        # SURVEYS, COMPARED: every survey, question, tally and response - the counts recounted from the rows, every
        # tally recomputed from the answers on the log, every respondent key computed by the reader itself.
        if reported_surveys:
            for name, reported_rows, mine_rows, line_fn in (
                ("survey", reported_surveys, store.surveys.surveys, store.surveys.survey_line),
                ("survey question", reported_survey_questions, store.surveys.questions, store.surveys.question_line),
                ("survey tally", reported_survey_tallies, store.surveys.questions, store.surveys.tally_line),
                ("survey response", reported_survey_responses, store.surveys.responses, store.surveys.response_line),
            ):
                for rid, reported in reported_rows.items():
                    if rid not in mine_rows:
                        print("ORACLE: the contract reported %s %d, which the log does not hold" % (name, rid))
                        faults.append("%s %d missing" % (name, rid))
                        continue
                    mine = line_fn(rid)
                    if mine != reported:
                        print("ORACLE: %s %d disagrees - reader %r, contract %r" % (name, rid, mine, reported))
                        faults.append("%s %d disagrees" % (name, rid))
            print("count: surveys compared figure by figure = %d" % len(reported_surveys))
            print("count: tallies recomputed from the answers on the log = %d" % store.surveys.tallies_recomputed)
            print("count: responses held to one per respondent = %d" % store.surveys.responses_held)
        faults.extend(store.surveys.faults)

        # APPRAISALS, COMPARED: every cycle with its counts recounted from the reviews, every review with its reviewer
        # re-derived from the reader's own employees and its final rating read by the rule, every goal's progress
        # recomputed, every key result and recognition.
        if reported_cycles:
            for name, reported_rows, mine_rows, line_fn in (
                ("review cycle", reported_cycles, store.appraisals.cycles, store.appraisals.cycle_line),
                ("review", reported_reviews, store.appraisals.reviews, store.appraisals.review_line),
                ("goal", reported_goals, store.appraisals.goals, store.appraisals.goal_line),
                ("key result", reported_key_results, store.appraisals.key_results, store.appraisals.key_result_line),
                ("recognition", reported_recognitions, store.appraisals.recognitions, store.appraisals.recognition_line),
            ):
                for rid, reported in reported_rows.items():
                    if rid not in mine_rows:
                        print("ORACLE: the contract reported %s %d, which the log does not hold" % (name, rid))
                        faults.append("%s %d missing" % (name, rid))
                        continue
                    mine = line_fn(rid)
                    if mine != reported:
                        print("ORACLE: %s %d disagrees - reader %r, contract %r" % (name, rid, mine, reported))
                        faults.append("%s %d disagrees" % (name, rid))
            print("count: review cycles compared figure by figure = %d" % len(reported_cycles))
            print("count: reviewers re-derived from the reader's own employees = %d" % store.appraisals.reviewers_rederived)
            print("count: final ratings read by the rule = %d" % store.appraisals.finals_read)
            print("count: goal progress recomputed = %d" % store.appraisals.progress_recomputed)
        faults.extend(store.appraisals.faults)

        # LEARNING, COMPARED: every course with its enrolments recounted, every path and item, every enrolment with its
        # progress held forward, every certification's validity read on the day the contract names, every skill's
        # endorsements recounted, every mentorship's sessions and minutes re-added.
        if reported_courses:
            for name, reported_rows, mine_rows, line_fn in (
                ("course", reported_courses, store.learning.courses, store.learning.course_line),
                ("learning path", reported_paths, store.learning.paths, store.learning.path_line),
                ("path item", reported_path_items, store.learning.path_items, store.learning.item_line),
                ("enrolment", reported_enrolments, store.learning.enrolments, store.learning.enrolment_line),
                ("skill", reported_skills, store.learning.skills, store.learning.skill_line),
                ("mentorship", reported_mentorships, store.learning.mentorships, store.learning.mentorship_line),
            ):
                for rid, reported in reported_rows.items():
                    if rid not in mine_rows:
                        print("ORACLE: the contract reported %s %d, which the log does not hold" % (name, rid))
                        faults.append("%s %d missing" % (name, rid))
                        continue
                    mine = line_fn(rid)
                    if mine != reported:
                        print("ORACLE: %s %d disagrees - reader %r, contract %r" % (name, rid, mine, reported))
                        faults.append("%s %d disagrees" % (name, rid))
            for rid, reported in reported_certifications.items():
                if rid not in store.learning.certifications:
                    print("ORACLE: the contract reported certification %d, which the log does not hold" % rid)
                    faults.append("certification %d missing" % rid)
                    continue
                mine = store.learning.certification_line(rid, reported[5])
                if mine != reported:
                    print("ORACLE: certification %d disagrees - reader %r, contract %r" % (rid, mine, reported))
                    faults.append("certification %d disagrees" % rid)
            print("count: courses compared figure by figure = %d" % len(reported_courses))
            print("count: enrolment progress held forward = %d" % store.learning.progress_held)
            print("count: certification validity read against the calendar = %d" % store.learning.validity_read)
            print("count: mentor room counted from the mentorships that stand = %d" % store.learning.room_counted)
        faults.extend(store.learning.faults)

        # COMPENSATION AND BENEFITS, COMPARED: every band; every review with its compa-ratio recomputed; every grant with
        # what the schedule says on the day the contract names, computed again with Python's own calendar; every score
        # with its final figure and amount recomputed; every payment with its net; every loan with its repayments re-added,
        # its instalments and what is owed computed again; every period read against the calendar; every enrolment with
        # the employee's monthly cost re-added.
        if reported_pay_bands:
            for name, reported_rows, mine_rows, line_fn in (
                ("pay band", reported_pay_bands, store.compensation.bands, store.compensation.band_line),
                ("salary review", reported_salary_reviews, store.compensation.reviews, store.compensation.review_line),
                ("incentive score", reported_incentive_scores, store.compensation.scores, store.compensation.score_line),
                ("off-cycle payment", reported_offcycle_payments, store.compensation.payments, store.compensation.payment_line),
                ("employee loan", reported_employee_loans, store.compensation.loans, store.compensation.loan_line),
                ("loan repayment", reported_loan_repayments, store.compensation.repayments, store.compensation.repayment_line),
                ("benefit enrolment", reported_benefit_enrolments, store.compensation.enrolments, store.compensation.enrolment_line),
            ):
                for rid, reported in reported_rows.items():
                    if rid not in mine_rows:
                        print("ORACLE: the contract reported %s %d, which the log does not hold" % (name, rid))
                        faults.append("%s %d missing" % (name, rid))
                        continue
                    mine = line_fn(rid)
                    if mine != reported:
                        print("ORACLE: %s %d disagrees - reader %r, contract %r" % (name, rid, mine, reported))
                        faults.append("%s %d disagrees" % (name, rid))
            for name, reported_rows, mine_rows, line_fn, day_at in (
                ("equity grant", reported_equity_grants, store.compensation.grants, store.compensation.grant_line, 6),
                ("enrolment period", reported_enrolment_periods, store.compensation.periods, store.compensation.period_line, 3),
            ):
                for rid, reported in reported_rows.items():
                    if rid not in mine_rows:
                        print("ORACLE: the contract reported %s %d, which the log does not hold" % (name, rid))
                        faults.append("%s %d missing" % (name, rid))
                        continue
                    mine = line_fn(rid, reported[day_at])
                    if mine != reported:
                        print("ORACLE: %s %d disagrees - reader %r, contract %r" % (name, rid, mine, reported))
                        faults.append("%s %d disagrees" % (name, rid))
            print("count: pay bands compared figure by figure = %d" % len(reported_pay_bands))
            print("count: vested figures recomputed from the schedule = %d" % store.compensation.vesting_recomputed)
            print("count: incentive finals recomputed = %d" % store.compensation.finals_recomputed)
            print("count: loan schedules recomputed = %d" % store.compensation.schedules_recomputed)
            print("count: enrolment periods read against the calendar = %d" % store.compensation.periods_read)
            print("count: benefit costs re-added = %d" % store.compensation.costs_readded)
        faults.extend(store.compensation.faults)

        # THE FLEET, COMPARED: every vehicle with its odometer recomputed from the readings and fuellings, its posted total
        # re-added from the costs and what it burns recomputed from its fuellings; every assignment; every contract with its
        # force read on the day the contract names; every reading; every fuelling with its amount recomputed; every cost.
        if reported_vehicles:
            for name, reported_rows, mine_rows, line_fn in (
                ("vehicle", reported_vehicles, store.fleet.vehicles, store.fleet.vehicle_line),
                ("vehicle assignment", reported_vehicle_assignments, store.fleet.assignments, store.fleet.assignment_line),
                ("odometer reading", reported_odometer_logs, store.fleet.odometer_logs, store.fleet.odometer_line),
                ("fuelling", reported_fuel_logs, store.fleet.fuel_logs, store.fleet.fuel_line),
                ("vehicle cost", reported_vehicle_costs, store.fleet.costs, store.fleet.cost_line),
            ):
                for rid, reported in reported_rows.items():
                    if rid not in mine_rows:
                        print("ORACLE: the contract reported %s %d, which the log does not hold" % (name, rid))
                        faults.append("%s %d missing" % (name, rid))
                        continue
                    mine = line_fn(rid)
                    if mine != reported:
                        print("ORACLE: %s %d disagrees - reader %r, contract %r" % (name, rid, mine, reported))
                        faults.append("%s %d disagrees" % (name, rid))
            for rid, reported in reported_vehicle_contracts.items():
                if rid not in store.fleet.contracts:
                    print("ORACLE: the contract reported vehicle contract %d, which the log does not hold" % rid)
                    faults.append("vehicle contract %d missing" % rid)
                    continue
                mine = store.fleet.contract_line(rid, reported[7])
                if mine != reported:
                    print("ORACLE: vehicle contract %d disagrees - reader %r, contract %r" % (rid, mine, reported))
                    faults.append("vehicle contract %d disagrees" % rid)
            print("count: vehicles compared figure by figure = %d" % len(reported_vehicles))
            print("count: odometers recomputed from the readings = %d" % store.fleet.odometers_recomputed)
            print("count: fuel amounts recomputed = %d" % store.fleet.amounts_recomputed)
            print("count: consumption recomputed from the fuellings = %d" % store.fleet.consumption_recomputed)
            print("count: contract force read against the calendar = %d" % store.fleet.force_read)
        faults.extend(store.fleet.faults)

        # DISCUSSION, COMPARED BOTH WAYS: every channel with its members and messages recounted, every member, every
        # message, every announcement with its reactions re-added, its notified recounted and its standing read on the
        # day the contract names, every reaction, every notification - the sweep's to an audience this reader
        # computed - and every sweep with its acted recounted from the notifications it wrote.
        if reported_announcements:
            for name, reported_rows, mine_rows, line_fn in (
                ("channel", reported_channels, store.discuss.channels, store.discuss.channel_line),
                ("channel member", reported_channel_members, store.discuss.members, store.discuss.member_line),
                ("channel message", reported_channel_messages, store.discuss.messages, store.discuss.message_line),
                ("reaction", reported_reactions, store.discuss.reactions, store.discuss.reaction_line),
                ("notification", reported_notifications, store.discuss.notifications, store.discuss.notification_line),
                ("announcement sweep", reported_announcement_sweeps, store.discuss.sweeps, store.discuss.sweep_line),
            ):
                for rid in sorted(set(mine_rows) - set(reported_rows)):
                    print("ORACLE: the log holds %s %d, which the contract did not report" % (name, rid))
                    faults.append("%s %d unreported" % (name, rid))
                for rid, reported in reported_rows.items():
                    if rid not in mine_rows:
                        print("ORACLE: the contract reported %s %d, which the log does not hold" % (name, rid))
                        faults.append("%s %d missing" % (name, rid))
                        continue
                    mine = line_fn(rid)
                    if mine != reported:
                        print("ORACLE: %s %d disagrees - reader %r, contract %r" % (name, rid, mine, reported))
                        faults.append("%s %d disagrees" % (name, rid))
            for rid in sorted(set(store.discuss.announcements) - set(reported_announcements)):
                print("ORACLE: the log holds announcement %d, which the contract did not report" % rid)
                faults.append("announcement %d unreported" % rid)
            for rid, reported in reported_announcements.items():
                if rid not in store.discuss.announcements:
                    print("ORACLE: the contract reported announcement %d, which the log does not hold" % rid)
                    faults.append("announcement %d missing" % rid)
                    continue
                mine = store.discuss.announcement_line(rid, reported[8])
                if mine != reported:
                    print("ORACLE: announcement %d disagrees - reader %r, contract %r" % (rid, mine, reported))
                    faults.append("announcement %d disagrees" % rid)
            print("count: notifications compared figure by figure = %d" % len(reported_notifications))
            print("count: discussion audiences computed from the memberships = %d" % store.discuss.audiences_computed)
            print("count: channel counts recomputed from the rows = %d" % store.discuss.counts_recomputed)
            print("count: announcement reactions re-added = %d" % store.discuss.reactions_readded)
            print("count: announcement standing read against the calendar = %d" % store.discuss.standing_read)
        faults.extend(store.discuss.faults)

        # KNOWLEDGE, COMPARED BOTH WAYS: every article with its views and votes re-added from the rows and a published
        # one's category and tags re-read from the version it names, every version, every view, every vote.
        if reported_kb_articles:
            kb = store.knowledge
            for name, reported_rows, mine_rows, line_fn in (
                ("knowledge article", reported_kb_articles, kb.articles, kb.article_line),
                ("knowledge version", reported_kb_versions, kb.versions, lambda rid: kb.version_line(rid, store)),
                ("knowledge view", reported_kb_views, kb.views, lambda rid: kb.view_line(rid, store)),
                ("knowledge vote", reported_kb_votes, kb.votes, lambda rid: kb.vote_line(rid, store)),
            ):
                for rid in sorted(set(mine_rows) - set(reported_rows)):
                    print("ORACLE: the log holds %s %d, which the contract did not report" % (name, rid))
                    faults.append("%s %d unreported" % (name, rid))
                for rid, reported in reported_rows.items():
                    if rid not in mine_rows:
                        print("ORACLE: the contract reported %s %d, which the log does not hold" % (name, rid))
                        faults.append("%s %d missing" % (name, rid))
                        continue
                    mine = line_fn(rid)
                    if mine != reported:
                        print("ORACLE: %s %d disagrees - reader %r, contract %r" % (name, rid, mine, reported))
                        faults.append("%s %d disagrees" % (name, rid))
            print("count: knowledge articles compared figure by figure = %d" % len(reported_kb_articles))
            print("count: knowledge counts re-added from the rows = %d" % kb.counts_readded)
            print("count: knowledge published versions re-read = %d" % kb.published_reread)
        faults.extend(store.knowledge.faults)

        # GOVERNANCE AND THE APPROVAL WORKFLOWS, COMPARED BOTH WAYS: every row this reader folded reported and every
        # row reported folded, figure by figure; every run's members phase recounted by this reader.
        gov, wfl = store.governance, store.workflow
        for name, reported_rows, mine_rows, line_fn in (
            ("policy", reported_gov["gov_policy"], gov.policies, gov.policy_line),
            ("policy version", reported_gov["gov_version"], gov.versions, lambda rid: gov.version_line(rid, store)),
            ("acknowledgement", reported_gov["gov_ack"], gov.acks, lambda rid: gov.ack_line(rid, store)),
            ("requirement", reported_gov["gov_requirement"], gov.requirements, gov.requirement_line),
            ("citation", reported_gov["gov_citation"], gov.citations, lambda rid: gov.citation_line(rid, store)),
            ("dashboard layout", reported_gov["gov_layout"], gov.layouts, lambda rid: gov.layout_line(rid, store)),
            ("approval cycle", reported_wf["wf_cycle"], wfl.cycles, wfl.cycle_line),
            ("approval request", reported_wf["wf_request"], wfl.instances, lambda rid: wfl.instance_line(rid, store)),
            ("approval decision", reported_wf["wf_decision"], wfl.decisions, lambda rid: wfl.decision_line(rid, store)),
            ("delegation", reported_wf["wf_delegation"], wfl.delegations, lambda rid: wfl.delegation_line(rid, store)),
        ):
            for rid in sorted(set(mine_rows) - set(reported_rows)):
                print("ORACLE: the log holds %s %d, which the contract did not report" % (name, rid))
                faults.append("%s %d unreported" % (name, rid))
            for rid, reported in reported_rows.items():
                if rid not in mine_rows:
                    print("ORACLE: the contract reported %s %d, which the log does not hold" % (name, rid))
                    faults.append("%s %d missing" % (name, rid))
                    continue
                mine = line_fn(rid)
                if mine != reported:
                    print("ORACLE: %s %d disagrees - reader %r, contract %r" % (name, rid, mine, reported))
                    faults.append("%s %d disagrees" % (name, rid))
        for rid in sorted(set(gov.runs) - set(reported_gov_runs)):
            faults.append("figures run %d unreported" % rid)
        runs_recounted = 0
        for rid, reported in reported_gov_runs.items():
            if rid not in gov.runs:
                faults.append("figures run %d missing" % rid)
                continue
            for what in gov.run_check(rid, reported, store):
                print("ORACLE: " + what)
                faults.append(what)
            if gov.runs[rid]["phase"] != governance.PHASE_MEMBERS:
                runs_recounted += 1
        print("count: governance rows compared figure by figure = %d" % sum(len(v) for v in reported_gov.values()))
        print("count: acknowledgement fingerprints compared with the words registered = %d" % gov.fingerprints_compared)
        print("count: policy acknowledgements re-added from the rows = %d" % gov.acks_readded)
        print("count: figures runs whose members this reader recounted = %d" % runs_recounted)
        print("count: compliance standings read against the calendar = %d" % gov.standings_read)
        print("count: workflow rows compared figure by figure = %d" % sum(len(v) for v in reported_wf.values()))
        print("count: domain decisions held to the chain = %d" % wfl.gates_held)
        print("count: step authorities checked = %d" % wfl.authorities_checked)
        print("count: requests held to their domain's record = %d" % wfl.records_read)
        print("count: requests about a record no reader here folds = %d" % wfl.records_unread)
        faults.extend(gov.faults)
        faults.extend(wfl.faults)

        # STUDIO, COMPARED BOTH WAYS: every field, rule and value this reader folded reported and every one reported
        # folded, figure by figure - each field's count of values re-added from the rows, each value's fingerprint
        # recomputed from the bytes its command carried - and the values the rule in force would now refuse
        # re-derived and held to the contract's own read of them.
        stu = store.studio
        for name, reported_rows, mine_rows, line_fn in (
            ("studio field", reported_studio["studio_field"], stu.fields, lambda rid: stu.field_line(rid, store)),
            ("studio rule", reported_studio["studio_rule"], stu.rules, lambda rid: stu.rule_line(rid, store)),
            ("studio value", reported_studio["studio_value"], stu.values, lambda rid: stu.value_line(rid, store)),
        ):
            for rid in sorted(set(mine_rows) - set(reported_rows)):
                print("ORACLE: the log holds %s %d, which the contract did not report" % (name, rid))
                faults.append("%s %d unreported" % (name, rid))
            for rid, reported in reported_rows.items():
                if rid not in mine_rows:
                    print("ORACLE: the contract reported %s %d, which the log does not hold" % (name, rid))
                    faults.append("%s %d missing" % (name, rid))
                    continue
                mine = line_fn(rid)
                if mine != reported:
                    print("ORACLE: %s %d disagrees - reader %r, contract %r" % (name, rid, mine, reported))
                    faults.append("%s %d disagrees" % (name, rid))
        outside = stu.nonconforming()
        if reported_studio_outside is None:
            faults.append("the contract reported no count of studio values outside the rule in force")
        elif reported_studio_outside != outside:
            print("ORACLE: the contract finds %d studio value(s) outside the rule in force, this reader %d" % (reported_studio_outside, outside))
            faults.append("studio values outside the rule in force disagree")
        print("count: studio rows compared figure by figure = %d" % sum(len(v) for v in reported_studio.values()))
        print("count: studio value counts re-added from the rows = %d" % stu.counts_readded)
        print("count: studio value fingerprints recomputed from the log = %d" % stu.hashes_recomputed)
        print("count: studio values held to a record a reader here watched = %d" % stu.records_held)
        print("count: studio values outside the rule in force, by the reader = %d" % outside)
        faults.extend(stu.faults)

        # CONTROLS, COMPARED BOTH WAYS AND WHOLE: every posting and confirmation record, profile, item, run, count, mark,
        # finding, procedure and conclusion this reader restated from the log printed as the export prints the
        # contract's, and required to be the same line - the run's population, its figures, its digit test, the chain
        # of its findings, the block and tip it was sealed at and its hash all among them.
        ctl = store.controls
        mine_ctl = ctl.lines()
        for kind in reported_ctl:
            for rid in sorted(set(mine_ctl[kind]) - set(reported_ctl[kind])):
                print("ORACLE: the log yields %s %d, which the contract did not report" % (kind, rid))
                faults.append("%s %d unreported" % (kind, rid))
            for rid, reported in sorted(reported_ctl[kind].items()):
                mine = mine_ctl[kind].get(rid)
                if mine is None:
                    print("ORACLE: the contract reported %s %d, which the log does not yield" % (kind, rid))
                    faults.append("%s %d missing" % (kind, rid))
                elif mine != reported:
                    print("ORACLE: %s %d disagrees - \n  reader   %s\n  contract %s" % (kind, rid, mine, reported))
                    faults.append("%s %d disagrees" % (kind, rid))
        compared = sum(len(v) for v in reported_ctl.values())
        if reported_ctl_printed is None or reported_ctl_printed != compared:
            print("ORACLE: the contract printed %s controls row(s), this reader read %d" % (reported_ctl_printed, compared))
            faults.append("the controls rows printed and read disagree")
        if not ctl.table_holds:
            faults.append("the first-two-digits table is not log10(1 + 1/d) to its last place")
        print("count: controls rows compared whole = %d" % compared)
        print("count: controls criteria re-decided for a move = %d" % ctl.criteria_restated)
        print("count: controls slices walked over the reader's own rows = %d" % ctl.slices)
        faults.extend(ctl.faults)

        # VOICE OVER IP, COMPARED BOTH WAYS AND WHOLE: every call this reader folded - its number in the form this reader
        # brought it to, its seconds, its consent, its recording and the block it was last written in - and the activity
        # it carried out, from this reader's own view of the activities: the assignee, due and done days, the summary a
        # call nobody scheduled gave it and the feedback every call gives.
        if reported_voip_printed is not None:
            mine_voip = store.voip.lines()
            for kind in reported_voip:
                for rid in sorted(set(mine_voip[kind]) - set(reported_voip[kind])):
                    print("ORACLE: the log yields %s %d, which the contract did not report" % (kind, rid))
                    faults.append("%s %d unreported" % (kind, rid))
                for rid, reported in sorted(reported_voip[kind].items()):
                    mine = mine_voip[kind].get(rid)
                    if mine is None:
                        print("ORACLE: the contract reported %s %d, which the log does not yield" % (kind, rid))
                        faults.append("%s %d missing" % (kind, rid))
                    elif mine != reported:
                        print("ORACLE: %s %d disagrees - \n  reader   %s\n  contract %s" % (kind, rid, mine, reported))
                        faults.append("%s %d disagrees" % (kind, rid))
            compared = sum(len(v) for v in reported_voip.values())
            if reported_voip_printed != compared:
                print("ORACLE: the contract printed %d voip row(s), this reader read %d" % (reported_voip_printed, compared))
                faults.append("the voip rows printed and read disagree")
            print("count: voip rows compared whole = %d" % compared)
        faults.extend(store.voip.faults)

        # PRODUCT LIFECYCLE, COMPARED BOTH WAYS AND WHOLE: every change this reader folded - its version number, its
        # state, its decider and day and the block it was last written in - its lines, and the version every production
        # was pinned to, which the manufacturing reader consumed when it produced.
        if reported_plm_printed is not None:
            mine_plm = store.plm.rows()
            for kind in reported_plm:
                for rid in sorted(set(mine_plm[kind]) - set(reported_plm[kind])):
                    print("ORACLE: the log yields %s %d, which the contract did not report" % (kind, rid))
                    faults.append("%s %d unreported" % (kind, rid))
                for rid, reported in sorted(reported_plm[kind].items()):
                    mine = mine_plm[kind].get(rid)
                    if mine is None:
                        print("ORACLE: the contract reported %s %d, which the log does not yield" % (kind, rid))
                        faults.append("%s %d missing" % (kind, rid))
                    elif mine != reported:
                        print("ORACLE: %s %d disagrees - \n  reader   %s\n  contract %s" % (kind, rid, mine, reported))
                        faults.append("%s %d disagrees" % (kind, rid))
            compared = sum(len(v) for v in reported_plm.values())
            if reported_plm_printed != compared:
                print("ORACLE: the contract printed %d plm row(s), this reader read %d" % (reported_plm_printed, compared))
                faults.append("the plm rows printed and read disagree")
            print("count: plm rows compared whole = %d" % compared)
        faults.extend(store.plm.faults)

        # ESG, COMPARED BOTH WAYS AND WHOLE: every set, gas, factor version, rule and activity this reader folded, every
        # run as its slices left it - its counts, cursor, chain and hash - and every figure; then each disclosure the
        # contract printed, restated from this reader's figures and compared line for line, the FRA's answers text for text.
        if reported_esg_printed is not None:
            mine_esg = store.esg.rows()
            for kind in reported_esg:
                for rid in sorted(set(mine_esg[kind]) - set(reported_esg[kind])):
                    print("ORACLE: the log yields %s %d, which the contract did not report" % (kind, rid))
                    faults.append("%s %d unreported" % (kind, rid))
                for rid, reported in sorted(reported_esg[kind].items()):
                    mine = mine_esg[kind].get(rid)
                    if mine is None:
                        print("ORACLE: the contract reported %s %d, which the log does not yield" % (kind, rid))
                        faults.append("%s %d missing" % (kind, rid))
                    elif mine != reported:
                        print("ORACLE: %s %d disagrees - \n  reader   %s\n  contract %s" % (kind, rid, mine, reported))
                        faults.append("%s %d disagrees" % (kind, rid))
            compared = sum(len(v) for v in reported_esg.values())
            answers = 0
            for (run_id, prior_id), reported in sorted(reported_esg_disclosures.items()):
                mine = store.esg.disclosure(run_id, prior_id)
                if mine is None:
                    print("ORACLE: the contract disclosed run %d, which this reader did not seal" % run_id)
                    faults.append("esg disclosure %d unsealed" % run_id)
                    continue
                for m, r in zip([mine[0]] + mine[1], reported):
                    if m != r:
                        print("ORACLE: the disclosure of run %d against %d disagrees - \n  reader   %s\n  contract %s" % (run_id, prior_id, m, r))
                        faults.append("esg disclosure %d/%d disagrees" % (run_id, prior_id))
                if len(reported) != 1 + len(mine[1]):
                    print("ORACLE: the contract printed %d line(s) of the disclosure of run %d, this reader %d" % (len(reported), run_id, 1 + len(mine[1])))
                    faults.append("esg disclosure %d/%d short" % (run_id, prior_id))
                compared += 1
                answers += len(mine[1])
            if reported_esg_printed != compared:
                print("ORACLE: the contract printed %d esg row(s), this reader read %d" % (reported_esg_printed, compared))
                faults.append("the esg rows printed and read disagree")
            print("count: esg rows compared whole = %d" % compared)
            print("count: esg disclosures restated = %d" % len(reported_esg_disclosures))
            print("count: esg FRA answers restated text for text = %d" % answers)
        faults.extend(store.esg.faults)

        # DRAFTS, COMPARED BOTH WAYS AND WHOLE: every draft this reader folded, its act's bytes, its source, its state
        # and the block its act was made in, against the row the contract printed.
        if reported_draft_printed is not None:
            mine_draft = store.draft.rows()
            for rid in sorted(set(mine_draft) - set(reported_draft)):
                print("ORACLE: the log yields draft %d, which the contract did not report" % rid)
                faults.append("draft %d unreported" % rid)
            for rid, reported in sorted(reported_draft.items()):
                mine = mine_draft.get(rid)
                if mine is None:
                    print("ORACLE: the contract reported draft %d, which the log does not yield" % rid)
                    faults.append("draft %d missing" % rid)
                elif mine != reported:
                    print("ORACLE: draft %d disagrees - \n  reader   %s\n  contract %s" % (rid, mine, reported))
                    faults.append("draft %d disagrees" % rid)
            if reported_draft_printed != len(reported_draft):
                print("ORACLE: the contract printed %d draft row(s), this reader read %d" % (reported_draft_printed, len(reported_draft)))
                faults.append("the draft rows printed and read disagree")
            print("count: draft rows compared whole = %d" % len(reported_draft))
        faults.extend(store.draft.faults)

        # THE READ METHOD'S PAGES, decoded from their bytes and held to this reader's fold both ways
        if sorted(read_page_pieces) != list(range(len(read_page_pieces))) or \
                any(sorted(ps) != list(range(len(ps))) for ps in read_page_pieces.values()):
            print("ORACLE: the read pages printed are not one sequence of whole pages")
            faults.append("the read pages are not one sequence")
        if reported_read_pages is None or reported_read_pages != len(read_page_pieces) or reported_read_pages == 0:
            print("ORACLE: the contract printed %s read page(s), this reader read %d" % (reported_read_pages, len(read_page_pieces)))
            faults.append("the read pages printed and read disagree")
        pages_hex = ["".join(read_page_pieces[seq][i] for i in sorted(read_page_pieces[seq])) for seq in sorted(read_page_pieces)]
        read_faults, read_counts = read_compare.compare(pages_hex, store, len(blocks), prev)
        for f in read_faults[:20]:
            print("ORACLE: read page: " + f)
        if read_faults:
            faults.append("%d read page fault(s)" % len(read_faults))
        if reported_read_rows is not None and reported_read_rows != read_counts["page rows"]:
            print("ORACLE: the contract printed %d read page row(s), this reader read %d" % (reported_read_rows, read_counts["page rows"]))
            faults.append("the read page rows printed and read disagree")
        floor_faults = read_compare.hold_to_floor(read_counts, a.raise_read_floor)
        for f in floor_faults:
            print("ORACLE: read page: " + f)
        faults.extend(floor_faults)
        for k, v in read_counts.items():
            print("count: read %s = %d" % (k, v))

        # AND THE PROPERTY: after a closed period every profit-and-loss account is at zero through
        # its end, by the reader's own figures.
        swept_total = 0
        for rid, r in store.ledger.closes.items():
            if r["state"] != "closed":
                continue
            left, seen = store.ledger.not_swept(rid)
            swept_total += seen - len(left)
            for aid in left[:5]:
                print("ORACLE: close run %d left account %d standing" % (rid, aid))
            if left:
                faults.append("close %d left %d account(s) standing" % (rid, len(left)))
        if store.ledger.closes:
            print("count: accounts the close swept to zero, by the reader = %d" % swept_total)

        # HLEDGER ITSELF, where the binary is present: a verifier nobody here wrote reading the
        # emitted journal and arriving at every account's balance - the trial balance after the close
        # among them, with the swept accounts at zero.
        try:
            ran, hl = accounting.run_hledger(journal)
        except ValueError as e:
            ran, hl = True, None
            print("ORACLE: %s" % e)
            faults.append("hledger refused the journal")
        if not ran:
            print("note: hledger is not installed here; the journal was re-read by this reader's own parser only")
        elif hl is not None:
            if hl != expected:
                print("ORACLE: hledger's balances are not the ledger's")
                for k in sorted(set(list(hl) + list(expected)))[:5]:
                    print("ORACLE:   %s ledger %s hledger %s" % (k, expected.get(k), hl.get(k)))
                faults.append("hledger disagrees")
            else:
                print("count: hledger accounts agreed = %d" % len(hl))
                zero_pl = sum(1 for aid, (d, c) in by_move.items()
                              if store.ledger.accounts[aid]["accountType"] in accounting.PROFIT_AND_LOSS
                              and hl.get(store.ledger.bean_name(aid)) == 0 and d - c == 0)
                if store.ledger.closes:
                    print("count: profit-and-loss accounts hledger shows at zero after the close = %d" % zero_pl)

    # EVERY PAYSLIP, COMPARED. Not the count - the figures. The contract prints its own and this
    # recomputes them from the log with a different arithmetic; a disagreement on any line of any
    # payslip is a fault, and it names both figures.
    # THE REQUIREMENT EXPLOSION, COMPARED BOTH WAYS AND WHOLE: every row the manufacturing reader published by
    # exploding on its own graph, against every row the contract printed
    if reported_requirements or reported_requirements_printed is not None:
        mine_rq = {rid: store.manufacturing.requirement_line(rid) for rid in store.manufacturing.requirements}
        for rid in sorted(set(mine_rq) | set(reported_requirements)):
            if mine_rq.get(rid) != reported_requirements.get(rid):
                print("ORACLE: requirement %d disagrees - \n  reader   %s\n  contract %s" % (rid, mine_rq.get(rid), reported_requirements.get(rid)))
                faults.append("requirement %d disagrees" % rid)
        if reported_requirements_printed != len(reported_requirements):
            print("ORACLE: the contract printed %r requirement row(s), this reader read %d" % (reported_requirements_printed, len(reported_requirements)))
            faults.append("the requirement rows printed and read disagree")
        print("count: requirement rows compared whole = %d" % len(set(mine_rq) & set(reported_requirements)))

    # EVERY LEAD'S PIPELINE, COMPARED BOTH WAYS AND WHOLE: its state, stage, board state and forecast as the CRM reader
    # folded them from the log - the weighted figure derived, the won stage's transition applied - against every
    # lead the contract printed
    if reported_leads or reported_leads_printed is not None:
        mine_ld = {lid: store.crm.lead_line(lid) for lid in store.crm.leads}
        for lid in sorted(set(mine_ld) | set(reported_leads)):
            if mine_ld.get(lid) != reported_leads.get(lid):
                print("ORACLE: lead %d disagrees - \n  reader   %s\n  contract %s" % (lid, mine_ld.get(lid), reported_leads.get(lid)))
                faults.append("lead %d disagrees" % lid)
        if reported_leads_printed != len(reported_leads):
            print("ORACLE: the contract printed %r lead row(s), this reader read %d" % (reported_leads_printed, len(reported_leads)))
            faults.append("the lead rows printed and read disagree")
        print("count: lead rows compared whole = %d" % len(set(mine_ld) & set(reported_leads)))

    # EVERY ACTIVITY AND EVERY RUN, COMPARED BOTH WAYS AND WHOLE: each activity as the shared view folded it, reminded
    # by the reader's own sweep of the due heads, and each reminder sweep and scoring run with its cursor, its counts
    # and the plan the reader restated
    if any(reported_crm_rows.values()) or reported_crm_rows_printed is not None:
        mine_rows = {"crm_activity": {i: store.crm.activity_line(i) for i in store.crm.activities},
                     "crm_run": {i: store.crm.run_line(i) for i in store.crm.runs}}
        for kind in ("crm_activity", "crm_run"):
            mine_k, theirs_k = mine_rows[kind], reported_crm_rows[kind]
            for i in sorted(set(mine_k) | set(theirs_k)):
                if mine_k.get(i) != theirs_k.get(i):
                    print("ORACLE: %s %d disagrees - \n  reader   %s\n  contract %s" % (kind, i, mine_k.get(i), theirs_k.get(i)))
                    faults.append("%s %d disagrees" % (kind, i))
        printed = sum(len(v) for v in reported_crm_rows.values())
        if reported_crm_rows_printed != printed:
            print("ORACLE: the contract printed %r activity and run row(s), this reader read %d" % (reported_crm_rows_printed, printed))
            faults.append("the activity and run rows printed and read disagree")
        print("count: activity rows compared whole = %d" % len(set(mine_rows["crm_activity"]) & set(reported_crm_rows["crm_activity"])))
        print("count: reminder and scoring runs compared whole = %d" % len(set(mine_rows["crm_run"]) & set(reported_crm_rows["crm_run"])))

    # EVERY FAMILY, FROM THE CONTRACT'S OWN BYTES: the plainest and the richest sample of each, as the contract encoded
    # them, read back by the family's declared type byte for byte and value for value (test/fixtures/
    # codec_samples.json holds the values the samples were written with), and by the family's hand reader where one
    # states it - read whole and, where it has an encoder, written back as the same bytes.
    if reported_codec["plain"] or reported_codec["rich"]:
        fixture = json.load(open(os.path.join(typed_codec.ROOT, "test", "fixtures", "codec_samples.json"), encoding="utf-8"))
        held = {"plain": 0, "rich": 0}
        by_hand = set()
        for kind in ("plain", "rich"):
            for i, h in sorted(reported_codec[kind].items()):
                body = bytes.fromhex(h)
                want = fixture["families"][i] if i < len(fixture["families"]) else None
                try:
                    fam, value = CODEC.round_trip(body)
                    if want is None or fam != want["family"]:
                        raise ValueError("sample %d is %s, the samples' %d is %s" % (i, fam, i, want and want["family"]))
                    if value != typed_codec.expected(want[kind]):
                        raise ValueError("%s reads back as other values than it was written with" % fam)
                    cmd = read_command(1, body)
                    if not cmd.get("byType"):
                        by_hand.add(fam)
                        if has_encoder(fam) and command_bytes(1, cmd) != body:
                            raise ValueError("%s: the hand reader writes it back as different bytes" % fam)
                    held[kind] += 1
                except (ValueError, KeyError, IndexError, UnicodeDecodeError) as e:
                    print("ORACLE: the %s sample of family %d does not read back: %s" % (kind, i, e))
                    faults.append("%s sample %d" % (kind, i))
        for kind in ("plain", "rich"):
            if sorted(reported_codec[kind]) != list(range(len(CODEC.families))):
                print("ORACLE: the export printed %d %s sample(s); the command type has %d families"
                      % (len(reported_codec[kind]), kind, len(CODEC.families)))
                faults.append("%s samples incomplete" % kind)
        print("count: families the reader holds to their declared type = %d" % len(CODEC.families))
        print("count: plain samples read back byte for byte and value for value = %d" % held["plain"])
        print("count: rich samples read back byte for byte and value for value = %d" % held["rich"])
        print("count: families a hand reader also states, held to the same bytes = %d" % len(by_hand))
    print("count: blocks written back by their declared type = %d" % REENCODED["by type"])
    print("count: blocks written back by a hand encoder too = %d" % REENCODED["by hand"])

    # THE AUDIT INDEX, COMPARED BOTH WAYS AND ENTRY BY ENTRY: the reader writes one entry under the caller and one
    # under the company for every block it folds, the company found by its own statement of where an act is, and holds
    # the contract's two tables to them; the printed counts are held to the lines read, so a line printed twice is a
    # fault too.
    if reported_audit_lines["caller"] or reported_audit_lines["company"] or reported_audit_printed["caller"] is not None:
        for kind in ("caller", "company"):
            if reported_audit_printed[kind] != reported_audit_lines[kind] or reported_audit_lines[kind] != len(reported_audit[kind]):
                print("ORACLE: the contract counted %r audit entries under their %s, printed %d lines, %d of them distinct"
                      % (reported_audit_printed[kind], kind, reported_audit_lines[kind], len(reported_audit[kind])))
                faults.append("audit entries under their %s counted and printed disagree" % kind)
        print("count: audit entries compared both ways = %d" % audit.compare(store.audit, reported_audit, faults))

    if reported_payslips:
        mismatches = store.pay.compare(reported_payslips)
        print("count: payslips compared figure by figure = %d" % len(reported_payslips))
        for m in mismatches[:10]:
            print("ORACLE: " + m)
        faults.extend(mismatches)
    print("count: oracle faults = %d" % len(faults))
    if tip is not None:
        print("tip: %s" % tip.hex())

    for f in faults[:10]:
        print("ORACLE: " + f)

    if a.expect_camt is not None and stmts["from_camt"] != a.expect_camt:
        faults.append("the contract holds %d statement(s) from camt.053, the log yields %d" % (a.expect_camt, stmts["from_camt"]))
    if a.expect_items is not None and len(store.credit.items) != a.expect_items:
        faults.append("the contract holds %d open item(s), the log yields %d" % (a.expect_items, len(store.credit.items)))
    if a.expect_consolidations is not None and len(store.consolidation.consolidations) != a.expect_consolidations:
        faults.append("the contract holds %d consolidation(s), the log yields %d" % (a.expect_consolidations, len(store.consolidation.consolidations)))
    if a.expect_work_orders is not None and len(store.maintenance.work_orders) != a.expect_work_orders:
        faults.append("the contract holds %d work order(s), the log yields %d" % (a.expect_work_orders, len(store.maintenance.work_orders)))
    if a.expect_quality_checks is not None and len(store.quality.checks) != a.expect_quality_checks:
        faults.append("the contract holds %d quality check(s), the log yields %d" % (a.expect_quality_checks, len(store.quality.checks)))
    if a.expect_tickets is not None and len(store.helpdesk.tickets) != a.expect_tickets:
        faults.append("the contract holds %d ticket(s), the log yields %d" % (a.expect_tickets, len(store.helpdesk.tickets)))
    if a.expect_visits is not None and len(store.fieldservice.visits) != a.expect_visits:
        faults.append("the contract holds %d visit(s), the log yields %d" % (a.expect_visits, len(store.fieldservice.visits)))
    if a.expect_bookings is not None and len(store.appointments.bookings) != a.expect_bookings:
        faults.append("the contract holds %d booking(s), the log yields %d" % (a.expect_bookings, len(store.appointments.bookings)))
    if a.expect_subscription_invoices is not None and len(store.subscriptions.invoices) != a.expect_subscription_invoices:
        faults.append("the contract holds %d subscription invoice(s), the log yields %d" % (a.expect_subscription_invoices, len(store.subscriptions.invoices)))
    if a.expect_rentals is not None and len(store.rental.rentals) != a.expect_rentals:
        faults.append("the contract holds %d rental(s), the log yields %d" % (a.expect_rentals, len(store.rental.rentals)))
    if a.expect_till_sessions is not None and len(store.pos.sessions) != a.expect_till_sessions:
        faults.append("the contract holds %d till session(s), the log yields %d" % (a.expect_till_sessions, len(store.pos.sessions)))
    if a.expect_tabs is not None and len(store.rst.tabs) != a.expect_tabs:
        faults.append("the contract holds %d tab(s), the log yields %d" % (a.expect_tabs, len(store.rst.tabs)))
    if a.expect_web_orders is not None and len(store.web.orders) != a.expect_web_orders:
        faults.append("the contract holds %d web order(s), the log yields %d" % (a.expect_web_orders, len(store.web.orders)))
    if a.expect_pages is not None and len(store.site.pages) != a.expect_pages:
        faults.append("the contract holds %d page(s), the log yields %d" % (a.expect_pages, len(store.site.pages)))
    if a.expect_posts is not None and len(store.blog.posts) != a.expect_posts:
        faults.append("the contract holds %d post(s), the log yields %d" % (a.expect_posts, len(store.blog.posts)))
    if a.expect_topics is not None and len(store.forum.topics) != a.expect_topics:
        faults.append("the contract holds %d topic(s), the log yields %d" % (a.expect_topics, len(store.forum.topics)))
    if a.expect_conversations is not None and len(store.chat.conversations) != a.expect_conversations:
        faults.append("the contract holds %d conversation(s), the log yields %d" % (a.expect_conversations, len(store.chat.conversations)))
    if a.expect_workflows is not None and len(store.auto.workflows) != a.expect_workflows:
        faults.append("the contract holds %d workflow(s), the log yields %d" % (a.expect_workflows, len(store.auto.workflows)))
    if a.expect_text_mailings is not None and len(store.sms.mailings) != a.expect_text_mailings:
        faults.append("the contract holds %d text mailing(s), the log yields %d" % (a.expect_text_mailings, len(store.sms.mailings)))
    if a.expect_social_posts is not None and len(store.social.posts) != a.expect_social_posts:
        faults.append("the contract holds %d social post(s), the log yields %d" % (a.expect_social_posts, len(store.social.posts)))
    if a.expect_events is not None and len(store.events.events) != a.expect_events:
        faults.append("the contract holds %d event(s), the log yields %d" % (a.expect_events, len(store.events.events)))
    if a.expect_surveys is not None and len(store.surveys.surveys) != a.expect_surveys:
        faults.append("the contract holds %d survey(s), the log yields %d" % (a.expect_surveys, len(store.surveys.surveys)))
    if a.expect_review_cycles is not None and len(store.appraisals.cycles) != a.expect_review_cycles:
        faults.append("the contract holds %d review cycle(s), the log yields %d" % (a.expect_review_cycles, len(store.appraisals.cycles)))
    if a.expect_courses is not None and len(store.learning.courses) != a.expect_courses:
        faults.append("the contract holds %d course(s), the log yields %d" % (a.expect_courses, len(store.learning.courses)))
    if a.expect_pay_bands is not None and len(store.compensation.bands) != a.expect_pay_bands:
        faults.append("the contract holds %d pay band(s), the log yields %d" % (a.expect_pay_bands, len(store.compensation.bands)))
    if a.expect_vehicles is not None and len(store.fleet.vehicles) != a.expect_vehicles:
        faults.append("the contract holds %d vehicle(s), the log yields %d" % (a.expect_vehicles, len(store.fleet.vehicles)))
    if a.expect_kb_articles is not None and len(store.knowledge.articles) != a.expect_kb_articles:
        faults.append("the contract holds %d knowledge article(s), the log yields %d" % (a.expect_kb_articles, len(store.knowledge.articles)))
    if a.expect_gov_policies is not None and len(store.governance.policies) != a.expect_gov_policies:
        faults.append("the contract holds %d polic(ies), the log yields %d" % (a.expect_gov_policies, len(store.governance.policies)))
    if a.expect_wf_requests is not None and len(store.workflow.instances) != a.expect_wf_requests:
        faults.append("the contract holds %d approval request(s), the log yields %d" % (a.expect_wf_requests, len(store.workflow.instances)))
    if a.expect_studio_fields is not None and len(store.studio.fields) != a.expect_studio_fields:
        faults.append("the contract holds %d studio field(s), the log yields %d" % (a.expect_studio_fields, len(store.studio.fields)))
    if a.expect_notifications is not None and len(store.discuss.notifications) != a.expect_notifications:
        faults.append("the contract holds %d notification(s), the log yields %d" % (a.expect_notifications, len(store.discuss.notifications)))
    if a.expect_payments is not None and len(store.payments.payments) != a.expect_payments:
        faults.append("the contract holds %d payment(s), the log yields %d" % (a.expect_payments, len(store.payments.payments)))
    if a.expect_claims is not None and len(store.expenses.claims) != a.expect_claims:
        faults.append("the contract holds %d claim(s), the log yields %d" % (a.expect_claims, len(store.expenses.claims)))
    if a.expect_assets is not None and len(store.ledger.assets) != a.expect_assets:
        faults.append("the contract holds %d asset(s), the log yields %d" % (a.expect_assets, len(store.ledger.assets)))
    if a.expect_revaluations is not None and len(store.ledger.revaluations) != a.expect_revaluations:
        faults.append("the contract holds %d revaluation(s), the log yields %d" % (a.expect_revaluations, len(store.ledger.revaluations)))
    if a.expect_deferrals is not None and len(store.ledger.deferrals) != a.expect_deferrals:
        faults.append("the contract holds %d deferral(s), the log yields %d" % (a.expect_deferrals, len(store.ledger.deferrals)))
    if a.expect_statements is not None and len(store.ledger.statements) != a.expect_statements:
        faults.append("the contract holds %d statement(s), the log yields %d" % (a.expect_statements, len(store.ledger.statements)))
    if a.expect_closes is not None and len(store.ledger.closes) != a.expect_closes:
        faults.append("the contract holds %d close run(s), the log yields %d" % (a.expect_closes, len(store.ledger.closes)))
    if a.expect_companies is not None and len(store.companies) != a.expect_companies:
        print("ORACLE: the contract reported %d companies; the log reconstructs %d"
              % (a.expect_companies, len(store.companies)))
        faults.append("company count disagrees")

    if a.expect_balances is not None and hrs["balances"] != a.expect_balances:
        print("ORACLE: the contract reported %d leave balances; the log reconstructs %d"
              % (a.expect_balances, hrs["balances"]))
        faults.append("leave-balance count disagrees")

    if a.expect_payslips is not None and pays["payslips"] != a.expect_payslips:
        print("ORACLE: the contract reported %d payslips; the log reconstructs %d"
              % (a.expect_payslips, pays["payslips"]))
        faults.append("payslip count disagrees")

    if a.expect_moves is not None and led["moves"] != a.expect_moves:
        print("ORACLE: the contract reported %d moves in its ledger; the log reconstructs %d (the stock's own valuation entries included)" % (a.expect_moves, led["moves"]))
        faults.append("move count disagrees")

    if a.expect_quants is not None and stk["quants"] != a.expect_quants:
        print("ORACLE: the contract reported %d quants; the log reconstructs %d" % (a.expect_quants, stk["quants"]))
        faults.append("quant count disagrees")

    if a.expect_campaigns is not None and crms["campaigns"] != a.expect_campaigns:
        print("ORACLE: the contract reported %d campaigns; the log reconstructs %d" % (a.expect_campaigns, crms["campaigns"]))
        faults.append("campaign count disagrees")

    if a.expect_punches is not None and hrs["punches"] != a.expect_punches:
        print("ORACLE: the contract reported %d punches; the log reconstructs %d"
              % (a.expect_punches, hrs["punches"]))
        faults.append("punch count disagrees")

    if a.json:
        print(json.dumps({"companies": len(store.companies), "faults": faults}, indent=2))

    if faults:
        print("ORACLE FAILED: %d fault(s)" % len(faults))
        return 1
    print("ORACLE GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
