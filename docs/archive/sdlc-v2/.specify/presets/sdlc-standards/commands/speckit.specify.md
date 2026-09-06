## SDLC standards

The canonical SDLC root is exactly `~/.agents/sdlc`. Never search the
filesystem to locate it. If `~/.agents/sdlc/MAIN.md` is absent or unreadable,
report that exact path.

Read `~/.agents/sdlc/MAIN.md`, `~/.agents/sdlc/AUDITS.md`, and
`~/.agents/sdlc/ISSUES.md` in full. Apply their defined-specification,
requirement-quality, acceptance-criteria, traceability, and identifier rules
throughout this command. Do not put implementation or test procedures into
requirements.

Read `.specify/memory/constitution.md` and its `Specification Baseline` before
drafting. When the project classification is brownfield:

- complete the brownfield context pass in `ISSUES.md` before drafting;
- read the named requirement and design authorities relevant to the requested
  change;
- consult relevant historical work records, including ticket comments or their
  equivalent, by following direct traceability references and performing a
  targeted search of the affected area;
- inspect the maintained regression tests for the affected behaviour, follow
  their requirement and ticket references, and read their assertions as
  evidence of actively protected functional behaviour;
- inspect the affected implementation for current facts and untested behaviour;
- treat approved existing requirements as the requirement baseline and use
  tests and code to establish the current implemented state;
- specify only the requested behavioural delta and its compatibility boundaries;
- record the sources consulted and what existing behaviour the delta preserves,
  changes, supersedes, or leaves unaffected;
- cite unchanged baseline requirements with identifiers and descriptors instead
  of copying them into the feature specification;
- use design authorities only for technical context, not to manufacture product
  requirements; and
- use tests and code as evidence, not as independent requirement authority.

Do not expand a brownfield delta into a standalone specification of the existing
system. Do not invent normalization, migration, persistence, workflow, fixture,
or test-oracle requirements merely to fill the core template. If a material
baseline source is missing, conflicting, or unresolved, make that clarification
explicit rather than guessing.

After specification and clarification are complete, the specification MUST
receive `audit-spec` PASS or satisfy a PROVISIONAL receipt under `AUDITS.md`.
Record the verdict and any receipt in the active feature's `audits.md`.
Planning MUST NOT begin without a current effective PASS.
The main authoring context owns convergence under `AUDITS.md`: remediate
current-phase blockers and dispatch fresh audits without handback, up to five
total attempts, then request operator sign-off with the required decision and
assumption summary.

After the applicable audit PASS, or validation when none applies, present
approval artefacts with `HTML_PREVIEW_TOOL`; otherwise use an available
non-blocking text editor or report the exact paths. Previewing is not approval
and must not stop the workflow.
