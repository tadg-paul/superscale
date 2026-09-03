## SDLC standards

The canonical SDLC root is exactly `~/.agents/sdlc`. Never search the
filesystem to locate it. If `~/.agents/sdlc/MAIN.md` is absent or unreadable,
report that exact path.

Read `~/.agents/sdlc/MAIN.md`, `~/.agents/sdlc/AUDITS.md`,
`~/.agents/sdlc/CODING.md`, `~/.agents/sdlc/TESTING.md`,
`~/.agents/sdlc/SECURITY.md`, `~/.agents/sdlc/GIT.md`, and
`~/.agents/sdlc/DOCUMENTATION.md` in full. Read
only the additional language and domain documents selected by the
constitution's Engineering Standards Profile. Apply them to architecture,
dependencies, interfaces, migration, security, test architecture,
compatibility, and operational design.

For a deployable application, define the repository-owned `make vulncheck`
implementation, scanner inputs, failure behaviour, exception mechanism, and
boundary with any external infrastructure owner. Do not treat vulnerability
checking as part of the behavioural regression suite.

Read the project constitution, its `Specification Baseline`, and the active
specification before drafting. For a brownfield project:

- read the current design and architecture authorities relevant to the change;
- consult relevant historical work records, including ticket comments or their
  equivalent, for rationale, rejected alternatives, migrations, and operational
  lessons;
- inspect the maintained regression tests and follow their requirement and
  ticket traceability to identify protected behaviour and compatibility
  constraints;
- inspect the affected implementation for current facts and untested behaviour;
  and
- record the inherited design constraints, deliberate changes, superseded
  decisions, unaffected boundaries, and unresolved conflicts.

Historical work records inform rationale and lineage but are not automatically
current design authority. Tests and code are implementation evidence, not
authority to change signed-off requirements or design.

If the plan needs a standard not yet selected, amend the standards profile. Do
not duplicate the standards text in `plan.md`; record project decisions and
references.

Before planning, verify that the active specification has a current
effective `audit-spec` PASS in the feature's `audits.md`. After the plan and
design are complete, they MUST receive `audit-design` PASS or satisfy a
PROVISIONAL receipt under `AUDITS.md`. Test design and task generation MUST NOT
begin without that current effective PASS.
The main authoring context owns convergence under `AUDITS.md`: remediate
current-phase blockers and dispatch fresh audits without handback, up to five
total attempts, then request operator sign-off with the required decision and
assumption summary.

After the applicable audit PASS, or validation when none applies, present
approval artefacts with `HTML_PREVIEW_TOOL`; otherwise use an available
non-blocking text editor or report the exact paths. Previewing is not approval
and must not stop the workflow.
