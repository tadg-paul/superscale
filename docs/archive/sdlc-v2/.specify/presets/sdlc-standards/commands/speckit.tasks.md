## SDLC standards

The canonical SDLC root is exactly `~/.agents/sdlc`. Never search the
filesystem to locate it. If `~/.agents/sdlc/MAIN.md` is absent or unreadable,
report that exact path.

Read `~/.agents/sdlc/MAIN.md`, `~/.agents/sdlc/AUDITS.md`,
`~/.agents/sdlc/TESTING.md`, `~/.agents/sdlc/SECURITY.md`, and
`~/.agents/sdlc/DOCUMENTATION.md` in full, plus the standards selected by the
constitution that affect the tasks. Ensure the task set covers specification
evidence, error and boundary behaviour, documentation, migration, security, and
human validation where relevant.

For a deployable application, include implementation and verification of the
`make vulncheck` security-gate contract. Keep it separate from `make test` and
from behavioural test traceability.

Select every applicable test type; a change may require automated regression,
one-off, and user tests together. Order each automated regression test before
the production-code task it governs and require confirmation that it fails for
the intended reason. Where no automated regression test is justified, add the
specific rationale. Define one-off and user-test evidence before implementation
where practical, and schedule its execution after implementation without a
pre-change failure requirement. When either category is selected, create or
update the active feature's `validation.md` with one `PENDING` entry per test as
defined by `TESTING.md`, and include tasks that record the results there.
Explicitly selected paired development follows `PAIRING.md` instead.

Before generating tasks, verify that the plan and design have a current
effective `audit-design` PASS in the feature's `audits.md`. After test design
and traceability are complete, they MUST receive `audit-tests` PASS or satisfy
a PROVISIONAL receipt under `AUDITS.md`. Implementation MUST NOT begin without
that current effective PASS.
The main authoring context owns convergence under `AUDITS.md`: remediate
current-phase blockers and dispatch fresh audits without handback, up to five
total attempts, then request operator sign-off with the required decision and
assumption summary.

After the applicable audit PASS, or validation when none applies, present
approval artefacts with `HTML_PREVIEW_TOOL`; otherwise use an available
non-blocking text editor or report the exact paths. Previewing is not approval
and must not stop the workflow.
