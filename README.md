# Mentat: Thebes Business Management

**Mentat is a business management system (an ERP) that runs as a smart contract on
the Thebes substrate.** Every act that changes a company's records is a command,
encoded to canonical bytes, appended to a hash-chained log and applied by a fold
that is the only writer of every table; the state is a function of the log, and a
reader who trusts nothing can rebuild it from the bytes. It keeps the books, sales
and purchase, stock and manufacturing, projects, the person record and payroll,
attendance and recruitment, payments and bank statements over ISO 20022, electronic
invoices to the tax authority, consolidation across a group, the company's website,
shop and marketing, and the governance around all of it. Written in Motoko.
Apache 2.0.

- **One log, one fold, one route in.** `submit` (and `submitAs` for a person signed
  in with a passkey) is the only way a command reaches the log: the contract reads the
  calendar, binds the command's canonical bytes to the version they were encoded under,
  folds it and appends the block, or refuses it with a typed reason
  (`src/Contract.mo`, `src/Mentat.mo`). Replaying the log from genesis reproduces every
  byte of every store; the batteries check it by fingerprint.
- **A refused command moves nothing.** Not a row, an identifier counter, a byte of
  the text arena or the log. Every fold checks everything that can refuse before it
  writes anything, and every refusal in the product is exercised and followed by a
  comparison of the whole state (`test/Refusals.test.mo`).
- **Four eyes on everything that moves money, stock or a person's record.** Authority
  is a catalogue row per operation (`src/Catalogue.mo`); a second act by a second
  principal completes a posting, a payment, a payroll run, a salary review, a stock
  disposition or a published policy, and the row that results names both people.
- **One gate for who may act.** Every command family is routed to the company it
  names and to the holders who may send it, deny by default, before any fold runs
  (`src/Gate.mo`); a battery holds every family to its route and its holders
  (`test/Isolation.test.mo`). Company roles (administrator, HR, director, manager,
  member, a read-only auditor, a drafting service) are rows; the platform operator is
  a fact of the log, claimed once while no company exists and handed over in two steps
  (`src/PlatformFold.mo`).
- **Dates from the calendar, never from the caller.** One module supplies time
  (`src/ClockWiring.mo`); no command carries a date or a time a person states, so
  nothing can be back-dated or post-dated by the person writing it. A check holds every
  other file to that (`tools/no_direct_clock.sh`, with its control).
- **Every read bounded, every sweep resumable.** Tables are fixed-width rows in stable
  memory with declared indexes; a list is a page with a cursor; a sweep (a payroll run,
  the month-end close, an invoice run, an escalation) is a run whose plan is hashed
  before the first slice and whose cursor is a row, so an upgrade in the middle of it
  loses nothing.
- **One read method for every kind of record.** `read` serves a page of one kind of
  record in one company to the class of reader written for it, deny by default
  (`src/ReadSurface.mo`, `src/ReadRules.mo`, generated into `src/ReadKinds.mo` by
  `tools/read_surface.py`). A person's payroll, medical, disciplinary or family record
  is served by query to nobody until the chain checks a query's sender by its signature
  (`src/Personal.mo`); the log keeps every byte.
- **The audit index.** Every accepted block is found by its caller and by its company
  (`entriesByCaller`, `entriesByCompany`), an index that points into the log and never
  stands in for it (`src/AuditIndex.mo`).
- **Documents encrypted in the browser, erasable and signed.** The contract holds
  ciphertext, the plaintext's fingerprint and keys wrapped to the company's devices;
  rotating the ring leaves out a device, erasing destroys the key and records the day,
  and a signature is a WebAuthn ES256 assertion verified over the document's digest,
  addressed to named signers in order (`src/EvFold.mo`, `test/Sign.test.mo`).
- **A sign-in that is a passkey.** A person signs in to Memphis, the Thebes passkey
  identity contract, with a session token scoped to one web origin; the contract asks
  Memphis who the token names and acts as that person's derived principal, never as the
  browser's key (`src/Identity.mo`).
- **Custom fields on every record, held to a rule.** Studio fields stand on every
  kind of record whose rows name their company (305 in the current verification
  set); a field's shape is fixed when it is defined, and its rule (whether it may be cleared, its bounds, who may write it) is a
  version recorded at a block (`src/StudioFold.mo`, `tools/studio_lint.py`).
- **Drafts that only a person makes acts.** An act proposed for a person (from a
  template, an import line or a rule) is kept as its canonical bytes; only that person,
  or a holder of the act by role, makes it an act, through the gate and the act's own
  fold. The assistant role ships with no model (`src/DraftFold.mo`).
- **Outbound calls that cannot repeat themselves.** Every outbound request (the tax
  filing, the mail relay) is made by exactly one validator, since a filing or a send is
  not idempotent at the far end; credentials are read at the edge and appear in no command and no row (`src/Outcall.mo`,
  `tools/outcall_and_secrets.sh`, with its control).
- **Upgrades that keep the state, proved.** The stable-type signature is committed
  (`src/Mentat.most`), and every retired layout of what the contract keeps is upgraded
  to the current one through its migration (`src/Migration.mo`, `tools/layouts/`,
  `tools/stable_compat.sh`).

| | |
|---|---|
| Record | append-only, hash-chained domain log; every table a fold over it; the log's tip set as the contract's certified data after every block |
| Controls | four eyes on every act that moves money, stock or a person's record; one deny-by-default gate; a catalogue checked in both directions; drafts made acts only by people |
| Standards | ISO 20022 (`pacs.008.001.08` out, `camt.053.001.08` in), ISO 13616 IBAN, ISO 9362 BIC, ISO 4217, the Egyptian Tax Authority's e-invoice document and CAdES-BES seal, WebAuthn ES256, GHG Protocol scopes with GRI and ESRS disclosures |
| Verification | the Motoko batteries under WASI, each rule removed on purpose by its control; the independent reader in Python that refolds the exported log; Beancount and hledger over the books; the read method's pages held to the reader's own fold |

Mentat is written in Motoko for the Thebes substrate, on the Thebes Domain Kernel
(rows, commands, permissions, bounded runs, exact arithmetic, the civil calendar).

**Type-safe, memory-safe, no silent errors.** Motoko is a strongly and statically
typed language of the ML family. It has option types in place of nulls,
arbitrary-precision and overflow-checked arithmetic that traps instead of wrapping,
garbage-collected memory with no pointers to corrupt, and atomic message execution: a
trap rolls the whole message back. Mentat is written to that discipline throughout.
Every refusal is a typed value naming its reason (a missing role, a closed period, a
balance that does not balance, a slot already taken, a stamp already spent); no
default is silently applied; money is exact integers in minor units with every
rounding accumulated and posted; a read that would be unbounded is refused with its
bound.

## Why it runs on Thebes

A business management system holds the record a company is run on and audited
against: what it sold and bought, what it owes, what it paid its people. Running it as
a smart contract on the Thebes substrate changes what that record is:

- **Redundant by construction.** The contract runs on every validator of the
  network, and its state is what a Byzantine fault-tolerant
  quorum of them agrees on. There is no primary to fail over from and no standby to
  fall behind: every validator holds the same log, the same books and the same person
  records, and a validator that is lost is replaced by the others without a restore.

- **Tamper-proof execution.** A posting, an approval, a payslip or a published page
  exists only if the validators executed the same command on the same state and
  reached the same result. No administrator, no operator of a single machine and no
  validator on its own can alter a balance, back-date an entry or remove a block: the
  log is append-only and hash-chained, each block carries the calendar's day, and the
  state every validator holds is hashed and compared at every height.

- **Verification and proofs.** After every block the log's tip is the contract's
  certified data (`certifiedTip`). A statement names the block it was sealed at and the
  tip at that block (`statement`, `consolidation`, `esgStatement`); a reader verifies
  the certificate with the network's root key, reads the blocks from the statement's to
  the certified tip (`blockBytes`) and checks the chain, and has the statement on the
  log's own authority. The independent reader (`integration/oracle/log_reader.py`)
  decodes every block from its bytes and recomputes every figure with code that shares
  nothing with the contract. An auditor, a regulator, a lender or a counterparty
  checks the books against the chain's own commitment.

- **The group's own infrastructure.** The validators of a Thebes network can be run
  by the parties to the record themselves: the companies of a group, their auditor,
  their bank. The books then live on infrastructure they jointly operate and jointly
  verify, with every member able to prove the state to itself, instead of on a system
  one vendor owns and the rest must trust.

- **Upgrades that keep the record.** The contract is upgraded in place, its stable
  memory carried across, and the batteries prove the state survives every retired
  layout's upgrade. An upgrade never rewrites or re-keys the history: the chain it was
  written on is the chain it stays on.

What follows from it for this product:

- **One deployable unit.** The data, the rules, the sign-in (passkey sessions through
  Memphis) and the company's public web presence (its pages, blog, forum, shop and
  careers page, served by the contract's own `http_request` from documents it holds)
  are one contract. There is no separate database, sign-in service, web host or backup
  job to buy and run.
- **Several companies and branches on one shared ledger.** Companies, their branches
  and departments are rows of one log, each company's records reachable only through
  its own holders at the gate. A group consolidates by reading each member's sealed
  statement at its block, generating the eliminations for what the members owe and
  sold each other, and sealing the consolidated statement at a block with the tip
  (`src/GrpFold.mo`).
- **Statements and e-invoices as objects a third party checks.** A financial
  statement is a fold of the log over a locked period, sealed at a block with the tip.
  An e-invoice is derived from the order and the move it invoiced (no figure is typed),
  sealed by the taxpayer's certificate over the canonical serialisation the Egyptian
  Tax Authority's SDK defines, and filed through its submission API; the body that was
  filed is served by the contract (`etaSubmissionBody`). An ESG statement names the
  published source files of its factors by SHA-256, and anyone re-derives it from them
  (`integration/esg/SOURCES.md`, `tools/esg_sources.py`). A supplier payment's
  `pacs.008` has its SHA-256 fixed before it leaves, and posts only on the hub's word.
- **Personal data kept to its readers.** Documents, candidates' applications and
  sealed fields are ciphertext under the company's ring, readable only on the company's
  own devices; the platform operator holds no company role, so the read method serves it
  nothing inside a company; a person's sensitive records are served by query to nobody.

## What is here

| Area | What is in it |
|---|---|
| **Accounting** | Charts, journals and moves; a posted move that does not balance is unrepresentable and its sequence number is allocated by the fold that posts it, so a series has no gaps; posting under four eyes; the month-end close as a bounded run that locks the period, sweeps profit and loss to retained earnings and can be reversed; statements sealed at a block; deferrals recognised by schedule; foreign-currency revaluation at the close; fixed assets charged month by month, impaired and disposed (`AcctFold.mo`). |
| **Finance and banking** | Currencies and rates, taxes, bank reconciliation; bank statements imported as `camt.053` and reconciled by the matching already present; supplier payments as `pacs.008` to the ISO 20022 hub, posted on its acceptance (`FinFold.mo`, `PmtFold.mo`, `Pacs008.mo`). |
| **Electronic invoicing** | The tax document derived from the order, its CAdES-BES seal, the filing and its answer, the credit note that amends it; the authority's credential installed once and read at the edge (`EtaDocument.mo`, `EtaSubmit.mo`). |
| **Sales and purchase** | Orders and the balanced invoice they become; the three-way match of order, receipt and the bill as the supplier sent it; credit limits refused at confirmation, payment terms that produce due days, late charges and interest posted by a run (`OrderFold.mo`, `CrdFold.mo`). |
| **Stock and manufacturing** | Pickings validated whole or not at all; valuation by first-in-first-out layers, average or standard cost; manufacturing orders that consume components into work in progress and book finished goods; engineering changes to a bill of materials as versions made effective by a second member, each manufacturing order pinned to its version; quality control points that hold goods until a check passes; maintenance plans, work orders and downtime against the order it stopped (`StockFold.mo`, `MrpFold.mo`, `PlmFold.mo`, `QcFold.mo`, `MntFold.mo`). |
| **Projects and service** | One task table for projects and the person record; timesheets approved by somebody else; the helpdesk with teams, boards and service levels whose clocks run on the company's working calendar; field service visits with parts from stock and an invoice; appointments on bookable resources; subscriptions invoiced by a run with proration; rental with pickup, return and late charges (`ProjFold.mo`, `HdFold.mo`, `FsFold.mo`, `AptFold.mo`, `SubFold.mo`, `RntFold.mo`). |
| **Point of sale and the web shop** | The shop's till session with a counted float and a Z report; the restaurant's tables, courses and a bill split by a recorded rule; the storefront's catalogue from the shop's price list, the cart as a draft order, checkout as a confirmed order and a payment (`PosFold.mo`, `RstFold.mo`, `WebFold.mo`). |
| **The person record** | Branches, departments and job titles; memberships and employees; leave balances kept by the fold; onboarding per engagement; probation, relocation, disciplinary cases that expire on their day, anonymous grievances; dependants' papers as encrypted evidence; an import checked whole before any row is written (`HrFold.mo`, `PeopleFold.mo`). |
| **Payroll and pay** | The statutory layer as data (profiles, bracket tables with no gaps); exact decimal arithmetic with every rounding posted; a run whose plan is hashed before the first payslip, approved by nobody whose payslip is in it; pay bands and salary reviews decided by a second person, equity vesting by schedule, incentive scores, loans and benefits posted through the ledger; expenses priced by the company's rates and approved by a second person (`PayFold.mo`, `PayEngine.mo`, `CnbFold.mo`, `ExpFold.mo`). |
| **Attendance** | Shifts, breaks timed by the block, overtime claimed in minutes at the rate the compensation row holds, holidays, working from home, time in lieu; punches from devices that sign their batches with their own P-256 key (`AttFold.mo`). |
| **Recruitment and development** | A careers page open to strangers and bounded by daily and per-posting ceilings and a proof-of-work stamp, every application ciphertext and erasable; panels, scorecards, offers that only their candidate answers and that expire by a run; appraisals with self, manager and calibrated ratings; goals with key results; courses, paths, certifications valid by the calendar, skills, endorsements and mentoring (`RecFold.mo`, `AprFold.mo`, `LrnFold.mo`). |
| **Customers and marketing** | Leads, stages, activities, scoring and reminders as runs; mailings that reach every recipient exactly once with suppression honoured; segments and A/B arms; marketing automation as a recorded rule set; text mailings and scheduled social posts through relays; calls logged as pipeline activities with consented recordings (`CrmFold.mo`, `AutoFold.mo`, `SmsFold.mo`, `SocialFold.mo`, `VoipFold.mo`). |
| **Website and community** | Pages published at a block from documents the company holds, a blog with bylines and calendar dates, a forum with moderation as a recorded act, live chat assigned by the fold to the longest-waiting visitor, events with tickets sold as orders, surveys answered once per member (`SiteFold.mo`, `BlogFold.mo`, `ForumFold.mo`, `ChatFold.mo`, `EventFold.mo`, `SurveyFold.mo`). |
| **Collaboration and knowledge** | Channels, announcements with an audience and a window, notifications read by their person alone; knowledge articles and policies as versions published by someone other than their author; acknowledgements signed against the policy's fingerprint (`DscFold.mo`, `KbFold.mo`, `GovFold.mo`). |
| **Fleet** | Vehicles carried as fixed assets, drivers assigned by somebody else, contracts in force by the calendar, an odometer that never goes backwards, fuel and costs posted through the ledger (`FltFold.mo`). |
| **Controls and approvals** | Journal screening over the company's own journal under a versioned profile, duplicate-bill and split-order rules, control procedures concluded under four eyes; approval workflows by company role with delegation until a day, whose last step is the domain's own decision (`CtlFold.mo`, `WfFold.mo`). |
| **ESG** | Emission factors and global warming potentials that name their published source by SHA-256, rules assigning factors to ledger lines and activities, a run over a locked period sealed as a statement, and its disclosures (GRI, ESRS and the Financial Regulatory Authority's environmental form) (`EsgFold.mo`). |
| **The platform** | The command codec and its frozen versions (`Encoding.mo`), the gate, the read method, the audit index, passkey sessions, Studio fields, drafts, the platform operator, the migration of every retired layout (`Gate.mo`, `ReadSurface.mo`, `AuditIndex.mo`, `Identity.mo`, `StudioFold.mo`, `DraftFold.mo`, `PlatformFold.mo`, `Migration.mo`). |

Every file in the table is under `src/`.

## Layout

```
src/            the contract: widths, vocabularies, rows, facts, folds, the command codec,
                the gate, the read method, the accept path (Mentat.mo is the actor)
test/           one battery per domain under WASI (test/run.sh), the refusal battery, the
                isolation battery, and the exporter (Export.export.mo) the reader reads
integration/    the independent reader (oracle/): Python that decodes the exported log and
                recomputes every figure; the published EPA files (esg/) and the tax
                authority's example documents (eta/)
tools/          tools/check.sh and every check it runs, each with its control; the
                generators of src/ReadKinds.mo, the codec samples and the command schema;
                the stable-layout gate; the module's compile bound
docs/landed/    the contract's Candid (mentat.did) and the command type as data
                (commands.json), from which a client's forms and encoder are generated
vendor/         thebes-kernel/README.md: the kernel's commit and where to place it
thebes.toml     the deployment manifest, as a template
```

## Building and testing

Requirements: `mops`, which installs `moc` 1.4.1 for the batteries (the toolchain in
`mops.toml`); the Thebes Motoko compiler `moc` 1.4.1+thebes.2 for the deployable
module, installed by `install-thebes-moc.sh` from the compiler release (1.4.1+thebes.2)
of `Mercatura-Forum/Thebes-Protocol-` into `~/.thebes/toolchain/moc` (or named by
`MOC_THEBES`); `wasmtime`; Python 3 with `cryptography`; Beancount's `bean-check` for
the books; `hledger`, where installed, is read as well.

The pinned dependencies sit beside this tree, each at the commit
`vendor/thebes-kernel/README.md` names:

```
work/
  Mentat/                                    this repository
  thebes-kernel/                             the Thebes Domain Kernel
  thebes-example-open-banking-iso20022/      the ISO 20022 hub, for the payment battery
```

```
git clone https://github.com/Mercatura-Forum/Mentat.git
git clone https://github.com/Mercatura-Forum/thebes-example-open-banking-iso20022.git
git -C thebes-example-open-banking-iso20022 checkout 0de7a826b38f493483c5ebc86ab6000a4102babe
(cd thebes-example-open-banking-iso20022 &&
  python3 integration-kit/scripts/iso-xsd-fetch.py)   # the official ISO 20022 schemas, which the
                                                      # hub fetches and does not redistribute
# the kernel, at the commit vendor/thebes-kernel/README.md names, as thebes-kernel/ beside them
cd Mentat
mops install
./test/run.sh                      # every battery; ./test/run.sh Payroll runs one
./tools/check.sh --quick           # the batteries, the exported log refolded by the reader,
                                   # the upgrade paths, every lint: no chain is needed
./tools/check.sh                   # the same with every control: each rule removed on
                                   # purpose, each must turn its check red
```

`tools/packages.sh` emits the compiler's package flags: the mops dependencies, the
kernel (`KERNEL`, else `vendor/thebes-kernel` when the kernel is placed there, else
`../thebes-kernel`) and the hub (`HUB`, else the sibling checkout). The deployable
module is built with the Thebes compiler and legacy (classical) persistence, so that an
in-place upgrade keeps the state:

```
"$MOC_THEBES" --legacy-persistence $(./tools/packages.sh) -o build/mentat.wasm src/Mentat.mo
```

Every battery prints the count of what it examined, and the runner refuses a count
that is absent or zero.

The current verification set, from `tools/check.sh --quick` on a fresh checkout of this
tree laid out as above: all 70 batteries green; the independent reader decodes and
refolds 1,776 blocks with no fault, holds all 634 command families to their declared
type with each family's samples read back byte for byte, and compares 40 payslips
figure by figure; the camt.053 message is valid against the official ISO 20022 schema;
6 retired layouts upgrade to the current one over 19 paths; the
filing twin re-derives the tax authority's digest over its published example, and
OpenSSL accepts both e-invoice seals and refuses both documents changed by one
character; 5 passkey assertions are verified independently with `cryptography`; the
read method serves 329 kinds of record; and the gate holds 634 command routes to their
holders.

## Known limitations and open items

- The Thebes Domain Kernel's repository is not public yet. Until it is, the tree builds
  where the kernel at the commit `vendor/thebes-kernel/README.md` names is available.
- The staff-facing web application is a separate front end and is not part of this
  repository; the contract serves the company's public pages, blog, forum and shop.
- A query's sender is not yet checked by its signature on the chain. Until it is, the
  records `src/Personal.mo` lists are served by query to nobody, and the sensitive
  person-record readers depend on that rule.
- The official ISO 20022 schemas are fetched from ISO 20022 by the hub's
  `integration-kit/scripts/iso-xsd-fetch.py`, not carried in either repository; without
  them `tools/check.sh` says the camt.053 messages were not held to the official schema.
- The checks that need a running chain (the block-time clock, an upgrade on a live
  subnet, the session against a live Memphis contract) are not part of this tree;
  `tools/check.sh` runs every check that needs no chain.
- The statutory payroll profile and the e-invoice document follow Egypt's published
  texts; other jurisdictions are data the company records, and none is shipped.
- `src/Mentat.most` names types with a hash of their package's path, so on a checkout
  at another path `tools/stable_signature.sh` reports a difference: the type names and
  the line wrapping they cause, with each signature stable-compatible with the other.
  `tools/stable_compat.sh` is the upgrade check and does not depend on the path.

## Contributing

This repository is the clean cut of a product built through iteration, test
batteries, oracle comparison and review; each release states what the system
guarantees. Open an issue for a question or a report, with the file and line; open a
pull request against `main` with `tools/check.sh` green. Contributions are attributed
to the team.

## Related repositories

Under `Mercatura-Forum`: [Manticore](https://github.com/Mercatura-Forum/Manticore)
(core banking and payments), [Solari](https://github.com/Mercatura-Forum/Solari)
(the audit system whose journal screening criteria Mentat's controls apply), [Lazarus](https://github.com/Mercatura-Forum/Lazarus)
(insurance), [thebes-lib](https://github.com/Mercatura-Forum/thebes-lib) (the Memphis
passkey identity this contract's sign-in restates), [thebes-sdk](https://github.com/Mercatura-Forum/thebes-sdk),
and [thebes-example-open-banking-iso20022](https://github.com/Mercatura-Forum/thebes-example-open-banking-iso20022)
(the ISO 20022 hub).

## Licence

Apache License 2.0 (see `LICENSE`). Provenance and third-party notices are in `NOTICE`.

Attribution: Thebes Core Team.
