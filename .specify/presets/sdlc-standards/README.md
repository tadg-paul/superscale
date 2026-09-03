# SDLC Engineering Standards Preset

This preset composes the public SDLC standards into Spec Kit 1.0 or later. It
does not replace Spec Kit's specification, planning, task, analysis, or
implementation workflow.

Install this repository with `make install`, which deploys the standards and
installs the CLI helpers. Then run the project initializer from the adopting
project:

```bash
sdlc-project-init
```

It installs this preset, records the project as greenfield or brownfield,
discovers applicable technology standards, renders an editable constitution
scaffold with its adopted SDLC revision, and invokes the selected agent harness.
Inspect or render without launching an agent with:

```bash
sdlc-project-init --no-launch
```

The generated scaffold has no authority before ratification. The agent
populates the brownfield authority map when applicable and adds only durable
project-specific principles, ownership boundaries, and explicit deviations.
Ratification makes the constitution authoritative; later amendments use it
directly rather than reapplying the scaffold. The current Sync Impact Report is
one compact HTML-comment line at the top of the constitution and is replaced on
amendment. A current rerun writes nothing, asks nothing, and does not invoke an
agent.

The command fragments reference the canonical installed root
`~/.agents/sdlc`. No command may search for an alternative SDLC root.

For brownfield projects, the specification and planning fragments require an
evidenced context pass across the relevant requirement and design authorities,
historical work records, maintained regression tests and traceability, and
affected implementation. The resulting delta records what it preserves,
changes, supersedes, and leaves unaffected without copying the baseline.

The command fragments require independent `audit-spec`, `audit-design`,
`audit-tests`, and `audit-code` effective PASS verdicts between stages. An exact
PROVISIONAL condition receipt matures to effective PASS without another model
audit. The main authoring context remediates current-phase blocking findings and
dispatches fresh audits for at most five attempts before returning for operator
sign-off. The shared contract is `~/.agents/sdlc/AUDITS.md`.

These staged transitions do not apply to an explicitly selected paired change.
That path follows `~/.agents/sdlc/PAIRING.md`, including its user-validation and
change-scoped audit contract.

Remove the development preset with:

```bash
specify preset remove sdlc-standards
```
