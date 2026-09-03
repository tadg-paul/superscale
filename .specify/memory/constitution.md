<!-- SYNC IMPACT: UNRATIFIED -> 0.1.0 | Principles: native local product; explicit external processing; distinct rights | Added: brownfield authority map; ownership boundaries; ratification blockers | Removed: generic core-template placeholders | TODOs: reconcile stale docs/ACs.md migration references; confirm adopted SDLC release -->

# Superscale Constitution

<!-- SDLC-GENERATED-SCAFFOLD: editable until ratification. -->

## Engineering Standards

This project MUST comply with the following canonical standards. The standards are referenced, not copied; load only those relevant to the current operation.

- **Universal engineering behaviour:** `~/.agents/sdlc/MAIN.md`.
- **Specification and requirement quality:** `~/.agents/sdlc/ISSUES.md`.
- **Implementation and design:** `~/.agents/sdlc/CODING.md`.
- **Testing and evidence:** `~/.agents/sdlc/TESTING.md`.
- **Security and vulnerability checking:** `~/.agents/sdlc/SECURITY.md`.
- **Independent audits:** `~/.agents/sdlc/AUDITS.md`.
- **Paired development:** `~/.agents/sdlc/PAIRING.md`.
- **Documentation:** `~/.agents/sdlc/DOCUMENTATION.md`.
- **Source control:** `~/.agents/sdlc/GIT.md`.
- **Python Standards:** `~/.agents/sdlc/technologies/PYTHON.md`.
- **Shell Standards:** `~/.agents/sdlc/technologies/SHELL.md`.
- **Swift Standards:** `~/.agents/sdlc/technologies/SWIFT.md`.

A deviation MUST name the standard, reason, risk, and approving authority. Silence is not a deviation.

The adopted SDLC revision is `1ac3855450cad5b8e1efce52e63c93cddec74f67`.


## Specification and Evidence

No implementation may begin without a defined specification. Before drafting a brownfield specification or design, the author MUST examine the current requirement and design authorities, relevant historical work records, the maintained regression test pack, and the affected implementation. The resulting artefact MUST identify what existing behaviour and decisions it preserves, changes, supersedes, or leaves unaffected. Tests MUST be used to trace actively protected behaviour to its originating requirements and compatibility constraints. Tests and code are implementation evidence; they do not approve requirements. Project documentation and the active specification MUST be updated when delivered behaviour or ownership boundaries change.

## Specification Baseline

**Project classification:** Brownfield

### Requirement Authority

`docs/ACs.org` is the sole authority for requirements established under the
completed legacy ticket-led process. Approved `specs/*/spec.md` artefacts govern
requirements established or changed through Spec Kit. The legacy record governs
only its own established requirements. A later approved Spec Kit specification
MAY supersede a legacy requirement only explicitly and MUST preserve its lineage.

### Migration Record and Historical Context

`docs/ticket-migration.org` is the disposition index for the completed SDLC v1
legacy-ticket migration. `docs/archive/migrated-tickets/` is its lossless
historical source. The index, archived tickets, ticket bodies, and comments
provide disposition, provenance, and rationale only; they are not current
requirement, acceptance-criterion, or design authorities. Scope classified as
defective, undelivered, or abandoned requires an approved Spec Kit specification
before implementation.

`docs/v1/`, `docs/E2E_DESIGN.md`, and `docs/proposal/` provide historical design
and product context only. Archived implementation plans are historical
provenance, not design authority.

### Design Authority

`docs/IMPLEMENTATION_GUIDE_v2.md` is the current approved design of record.
`docs/ARCHITECTURE.md` is the current approved as-built architecture and MUST
remain consistent with that design. `docs/FAL_REQUEST_REFERENCE.md` is the
project's durable integration reference within the external provider boundary.

### Regression Evidence and Traceability

`Tests/` and `SuperscaleApp/SuperscaleAppUITests/` are the maintained regression
test pack. The supported regression entry points are `make test`,
`make test-ssim`, and `make test-gui`. `docs/ACs.org` records traceability from
legacy requirements to their regression evidence; test sources carry the
corresponding regression-test identifiers.

Tests and code provide evidence of implemented behaviour. They do not approve requirements.

### Precedence and Supersession

Authority is concern-specific. Taḋg O'Brien, as human project owner, controls
ratification, constitutional change, and deviations. After ratification, this
constitution and its selected standards govern engineering and governance.
`docs/VISION.md` governs durable product purpose and policy. `docs/ACs.org` and
approved Spec Kit feature specifications govern observable behaviour within
their respective scopes. The approved design sources govern technical choices
within those requirements. Operational, testing, migration, release, and user
documentation govern their respective procedures and evidence. Code and tests
record implemented state and evidence; they do not approve requirements.

An external integration contract is authoritative only within the external
provider's named ownership boundary. A later source supersedes another source
only when the competent authority explicitly records the supersession and
preserves lineage. Any other same-concern conflict requires a human decision
before affected work proceeds.

## Mandatory Independent Audits

For staged Spec Kit delivery, each audit MUST run in a fresh agent context that did not author the artefact and MUST emit the exact structured verdict required by its skill. PASS may retain advisories. A PROVISIONAL verdict becomes effective PASS only through the exact condition receipt defined by the audit standard. On FAIL, the author remediates and a fresh independent audit runs. The next stage MUST NOT begin until the required audit records effective PASS.

1. Specification and clarification require `audit-spec` PASS before planning.
2. Plan and design require `audit-design` PASS before test design and tasks.
3. Test design and traceability require `audit-tests` PASS before implementation.
4. Implementation requires `audit-code` PASS before completion or convergence.

Record each audit name, auditor provider and model, artefact revision, exact verdict, findings, and superseding rerun in the active feature's `audits.md`. `speckit-analyze` is a consistency check and does not replace an independent audit.

When the operator explicitly selects paired development under `~/.agents/sdlc/PAIRING.md`, its change-scoped closure and user-validation contract replaces these staged transitions for that change. Engineering standards and applicable audit requirements remain mandatory.

## Project-Specific Principles

### I. Native Local Product

Superscale MUST remain a native Mac product whose image-upscaling capability
executes locally. The command-line product MUST remain limited to local
upscaling and MUST NOT become a cloud-generation client. Changing either
boundary requires constitutional revision because both define the project's
durable identity rather than a feature-level choice.

### II. Explicit External Processing

Local processing MUST NOT be represented as external processing, and external
processing MUST NOT be represented as local. An image or credential MAY leave
the device only through an explicitly invoked, accurately disclosed external
operation. The application MUST preserve meaningful human control over paid
and externally processed work by requiring deliberate user initiation. This
principle protects the project's durable privacy and agency boundary while
allowing providers and features to evolve.

### III. Distinct Rights and Provenance

The Apache-2.0 licence for Superscale source MUST NOT be represented as granting
rights in third-party model artefacts or the Superscale name and logo. Model,
source, and trademark rights MUST remain separately attributed and governed by
their applicable authorities. A change to this rights boundary requires a
constitutional decision because it changes project-wide ownership policy.

## Project Ownership and Architecture Boundaries

Superscale owns its product semantics, native application and command-line
behaviour, local processing, integration implementation, and the project data
it creates. External providers own and evolve their hosted infrastructure and
published service contracts. Superscale is a consumer of those contracts: it
MUST comply with the provider-owned protocol and MUST honour the application
behaviour and data-handling commitments it publishes. Provider authority does
not extend to Superscale product policy, and Superscale authority does not
extend to redefining provider infrastructure behaviour.

Third-party model owners retain authority over their model licences. Taḋg
O'Brien retains authority over the Superscale name and logo under
`docs/trademark.md`. These ownership boundaries do not confer requirement
authority on implementation code, tests, or historical records.

## Governance

This constitution governs project specifications, plans, tasks, implementation, and review after ratification. Before ratification, this scaffold has no authority. Amendments MUST explain compatibility and migration effects and update the version and dates below.

Taḋg O'Brien, as human project owner, is the ratification and amendment
authority. No standards deviation is approved by this draft. After ratification,
compliance review MUST identify the applicable constitutional principles,
approved deviations, and every unresolved constitutional conflict. A conflict
MUST be resolved by the competent human authority before affected work proceeds.

Initial ratification sets the version to `1.0.0`. After ratification, a MAJOR
version removes or incompatibly redefines governance, a MINOR version adds or
materially expands governance, and a PATCH version clarifies wording without
changing meaning. Revisions before ratification are draft revisions, not
constitutional amendments.

Ratification is blocked until all of the following are resolved:

- `docs/ticket-migration.org` names the missing `docs/ACs.md` as the canonical
  ledger in two places; the project authority actually present and selected by
  this draft is `docs/ACs.org`.
- The human ratification authority confirms that SDLC revision
  `1ac3855450cad5b8e1efce52e63c93cddec74f67` identifies the SDLC release being
  adopted at ratification.

**Version**: 0.1.0 | **Ratified**: UNRATIFIED | **Last Revised**: 2026-09-03
