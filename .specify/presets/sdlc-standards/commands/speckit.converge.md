## SDLC standards

The canonical SDLC root is exactly `~/.agents/sdlc`. Never search the
filesystem to locate it. If `~/.agents/sdlc/MAIN.md` is absent or unreadable,
report that exact path.

Read `~/.agents/sdlc/MAIN.md`, `~/.agents/sdlc/AUDITS.md`,
`~/.agents/sdlc/CODING.md`, `~/.agents/sdlc/TESTING.md`, and
`~/.agents/sdlc/SECURITY.md` in full, plus the
constitution's selected standards that apply to the assessment. Distinguish
verified implementation evidence from remaining tasks and give every cited
identifier an adjacent descriptor.

For a deployable application, do not declare convergence while the required
`make vulncheck` target is absent, incomplete, or failing. Report its result as
a security gate, not as behavioural regression evidence.

Do not declare convergence while the implementation lacks a current
effective `audit-code` PASS in the feature's `audits.md`. Relevant changes made
during convergence preserve that PASS as revision-specific history but make it
non-current and require a fresh independent audit unless they satisfy an exact
PROVISIONAL condition under `AUDITS.md`.
Follow the autonomous convergence and handback rules in `AUDITS.md` for any
resulting implementation and audit-code cycle.

When one-off or user tests were selected, do not declare convergence unless the
active feature's `validation.md` contains a current PASS for every required
test. A missing, `PENDING`, `FAIL`, or materially stale result blocks
convergence. Preserve superseded audit and validation history, rerunning only
the audits and tests materially affected by later changes.
