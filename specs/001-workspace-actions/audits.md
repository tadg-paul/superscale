# Audit Record: Reliable Workspace Actions

## Specification Audit

**Audit**: `audit-spec`
**Provider**: `nous`
**Model**: `z-ai/glm-5.3-flash`

### Attempt 1

**Artefact revision**: Initial specification draft
**Verdict**: FAIL
**Superseded by**: Attempt 2 after specification revision

1. **Blocking**: Search-focus behaviour did not explicitly preserve existing query text.
2. **Blocking**: Save All's non-overwrite rule conflicted with its no-dialog rule.
3. **Advisory**: Test-method constraints belonged outside functional requirements.
4. **Advisory**: Paste types needed explicit traceability to the existing import contract.
5. **Advisory**: Diagnostic redaction needed a generalized requirement.

### Attempt 2

**Artefact revision**: Revised after Attempt 1
**Verdict**: FAIL
**Superseded by**: Attempt 3 after specification revision

1. **Blocking**: Occupied-canvas Paste was not required to be visibly disabled or re-checked at execution time.
2. **Blocking**: Category-chip state was not explicitly required to match the catalogue narrowing actually in effect.
3. **Advisory**: Save All's effect on unsaved-work state was undefined.
4. **Advisory**: Save As behaviour for a vanished configured directory was undefined.
5. **Advisory**: Documentation reconciliation was not explicit.

### Attempt 3

**Artefact revision**: Revised after Attempt 2
**Verdict**: PROVISIONAL
**Superseded by**: Attempt 4 because the corrected revision also incorporated advisories

1. **Condition**: Scenario keywords had to use unbolded `GIVEN`, `WHEN`, and `THEN` on separate lines.
2. **Advisory**: The late-paste scenario should state observable behaviour rather than an internal check.
3. **Advisory**: The invalid-directory Save As requirement should be split into independently verifiable requirements.
4. **Advisory**: The blank-generation sizing consequence from migrated ticket #148 should be cited.

**Condition evidence**: `rg` reported zero bold scenario keywords after the formatting correction.

### Attempt 4

**Artefact revision**: SHA-256 `cc147b1462722883371fce4fc15d91fa394fbed3e0d637343db531780479a142`
**Verdict**: PASS

1. **Advisory retained for planning**: Define blank canvas as the drop-target state.
2. **Advisory retained for verification**: Include the maintained filter-panel regression pack in the final evidence.
3. **Advisory retained for design**: Specify Save As encode and write failure behaviour consistently with Save All.
4. **Advisory retained as a decision**: PNG is the fixed Save All output format unless the human changes that scope decision.

## Controller Notes

- Three auditor responses were rejected by the controller as malformed and therefore carried no verdict.
- One audit worker exceeded the controller's 15-minute timeout and therefore carried no verdict.
- These tool failures did not alter the candidate or replace any valid audit attempt.

## Design Audit

**Audit**: `audit-design`
**Provider**: `nous`
**Model**: `z-ai/glm-5.3-flash`

### Attempt 1

**Artefact revision**: Initial plan and Phase 0/1 design set
**Verdict**: FAIL
**Superseded by**: Attempt 2 after design revision

1. **Blocking**: Export membership did not account for a promoted minimum-resolution raise in the held chain.
2. **Blocking**: Paste type eligibility was stated but not assigned to an execution-time boundary or failure behaviour.
3. **Advisory**: Focus forwarding needed to be limited explicitly to Copy and Paste.
4. **Advisory**: The vulnerability gate needed a fail-closed rule for a missing Xcode lockfile.
5. **Advisory**: GUI generation evidence needed to record upload calls as well as the submitted request.
6. **Advisory**: Save All needed an explicit cancellation policy.

### Attempt 2

**Artefact revision**: Revised after Attempt 1
**Verdict**: FAIL
**Superseded by**: Attempt 3 after design revision

1. **Blocking**: Save All did not freeze every reactive processing and graph mutation sharing the batch's coordinator and snapshot.
2. **Blocking**: The inherited folder fallback discarded the raw stale setting needed to prevent silent Save All redirection.
3. **Advisory**: Custom sizing needed deterministic per-image semantics.
4. **Advisory**: Folder warnings, batch progress, and batch summary needed named presentation surfaces and ordering.
5. **Advisory**: New controls and states needed accessibility identifiers and values.
6. **Advisory**: Final atomic writes needed a no-overwrite guarantee, not reservation alone.
7. **Advisory**: GUI upscale-completion helpers needed proof that Save As state was not their oracle.
8. **Advisory**: Dependency-lock agreement needed a deterministic policy; the revision instead scans both committed graphs independently because they currently resolve different versions.

### Attempt 3

**Artefact revision**: Revised after Attempt 2
**Verdict**: FAIL
**Superseded by**: Attempt 4 after design revision

1. **Blocking**: The plan and UI contract disagreed about `Cmd+S` while editable text has focus.
2. **Advisory**: Save bookkeeping for source and candidate roles needed to preserve the existing locked-iteration-only warning population explicitly.
3. **Advisory**: Scaled batch export needed to bypass the display rendering cache so open defect #106 could not reach saved files.

### Attempt 4

**Artefact revision**: Revised after Attempt 3
**Verdict**: FAIL
**Superseded by**: Attempt 5 after design revision

1. **Blocking**: Duplicate custom Copy and Paste key equivalents could still swallow native text shortcuts or be swallowed by the standard menu group, depending on enabled state and ordering.
2. **Blocking**: The Save All freeze omitted Open Recent, the canvas Clear Image action, and the base-versus-candidate display toggle.
3. **Blocking**: Generation routing omitted the existing identical-held-result short circuit, which must make no upload and no provider request.
4. **Advisory**: The 25-image performance validation scale sounded like a workspace cap.
5. **Advisory**: The vulnerability gate needed an explicit invocation point in release flows.
6. **Advisory**: Provider success with unreadable image data needed a defined failure transition.

### Attempt 5

**Artefact revision**: Design-set manifest SHA-256 `c85be4d844e9ec3d974efee9a42980d320db048ddeaf374576a34732ca8e9110`
**Verdict**: FAIL
**Handback**: Fifth failed design attempt; operator decision required

1. **Blocking**: FR-015 requires category choice to clear search text, while maintained GUI regression RT-141.7 expects search text to survive a category choice. The plan must record that FR-015 supersedes that clause and must relocate RT-141.7's focus-preserves-text assertion to a blur and refocus path with no category choice.
2. **Blocking**: The plan used `savableImage` as the Copy source, but FR-003 and AC144.2 require the pixels currently displayed. Copy must write `displayedImage`, using `savableImage` only for eligibility, with GUI evidence for copying the raw base while scale is selected and the base is shown.
3. **Advisory**: Save All eligibility must state whether an in-flight upscale or provider operation blocks batch start or is awaited before the snapshot.
4. **Advisory**: Batch progress must preserve the single `workingIndicator` element required by AC128.5 and expose `current of total` through that element rather than implying a second indicator identifier.
5. **Advisory**: The plan and documentation reconciliation must name FR-014 as a second saved-state route extending AC143.6 while preserving its displayed-picture Save As route.
