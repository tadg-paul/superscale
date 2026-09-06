# Data Model: Reliable Workspace Actions

## Workspace Export Candidate

Represents one distinct active-workspace image eligible for Save All.

- **asset reference**: Stable graph identity.
- **source URL**: File containing the model-resolution pixels.
- **graph role**: Source, raised to minimum, or filtered.
- **export label**: Source, prepared, iteration, or candidate.
- **chain position**: One-based stable export order.
- **descriptive stem**: Human-readable filename basis derived from source and provenance.
- **pixel size**: Stored dimensions used to plan the current scale choice.

### Validation

- Each asset identity appears once.
- Ordering follows the held chain, oldest to newest, then a distinct unlocked candidate.
- A promoted `raisedToMinimum` chain entry is included and receives the `prepared` export label.
- The URL must refer to a readable supported image before processing begins.
- A candidate with the same identity as a chain entry is not appended again.

## Export Configuration

Captures the user-owned choices applied consistently across one batch.

- **destination directory**: Current configured writable output folder.
- **format**: PNG.
- **scale selection**: Off, preset scale, or custom dimensions.
- **custom-sizing interpretation**: Defining dimension with per-source aspect preservation, or absolute width and height when stretch is on.
- **upscale model**: Current local model choice.
- **face enhancement**: Current eligible setting.
- **size ceiling**: Existing output-area limit.

### Validation

- The destination must exist, be a directory, and be writable at action time.
- Preset scale is applied independently to each source.
- With stretch off, the chosen custom defining dimension is applied to each source and the other dimension is derived from that source's aspect ratio.
- With stretch on, the chosen custom width and height are applied to every source.
- The existing 8x dimension cap and output-area ceiling are re-evaluated for each source; each reduction remains reportable.
- The configuration is snapshotted at batch start so mid-run UI changes cannot produce mixed outputs.

## Output Folder State

Preserves both the user's stored choice and the operational fallback.

- **stored URL**: Raw configured path, when one exists.
- **effective URL**: Writable configured path or resolved Downloads fallback.
- **status**: Default, valid configured, or stale configured.

### State Rules

- First launch has default status and resolved Downloads as the effective URL.
- A valid user selection has valid configured status and the same stored and effective URL.
- A vanished or unwritable stored URL has stale configured status, retains that raw URL for reporting and Settings, and uses Downloads only where the Save As fallback is explicitly allowed.
- Save All rejects stale configured status before reserving any destination.
- Saving a new writable selection replaces the stale state.

## Reserved Export Destination

Represents an output path allocated without overwriting either an existing file or another item in the same batch.

- **candidate**: The export candidate being named.
- **suggested filename**: Descriptive PNG name.
- **resolved URL**: First available destination after collision suffixing.

### Validation

- Every resolved URL is beneath the configured destination directory.
- No two candidates share a resolved URL.
- An existing filesystem item is never selected.

## Batch Export Result

Records the outcome of every attempted candidate.

- **successes**: Candidate source URL and written output URL.
- **failures**: Candidate source URL and safe diagnostic.
- **unattempted**: Candidate source URLs not started because the user cancelled the batch.
- **reductions**: Existing size-cap notices associated with successful outputs.
- **cancelled**: Whether cancellation ended the batch before all candidates reached a terminal result.

### State Transitions

```text
eligible -> reserved -> processing -> written -> saved
                              |
                              +-> failed
eligible --------------------------> unattempted
```

- A write becomes saved only after atomic output succeeds.
- A failed candidate remains unsaved.
- An unattempted candidate remains unsaved.
- One failure does not prevent later eligible candidates from entering processing.
- Cancellation stops the current pipeline and prevents later candidates from entering processing.
- While processing, every action that can change graph membership, image processing configuration, or displayed source is unavailable; attempted shortcuts are discarded rather than deferred.

## Workspace Command Request

Extends the existing monotonic application command channel.

- **copy request count**: Existing counter.
- **paste request count**: Existing counter.
- **save-all request count**: New counter.
- **text responder ownership**: Evaluated at command execution and not persisted.
- **batch activity**: Idle or saving, with current and total positions.

### State Rules

- Repeated keyboard events remain distinguishable because counters only increase.
- Paste eligibility is re-checked against the current graph before import.
- Text responder forwarding does not increment a canvas command counter.
- Batch activity disables workspace mutation except cancellation; it does not queue later mutations.

## Prompt Operation

The operation selected from current workspace state.

- **prompt**: Trimmed, non-empty user text.
- **model**: Existing MVP Grok default.
- **base reference**: Absent for generation; exactly one current base for edit.
- **operation**: Generation when the graph has no base; local adoption when an identical held result exists; edit otherwise.

### State Transitions

```text
blank + prompt + credential -> generation -> new source
base  + matching held result -> local adoption -> candidate
base  + no matching held result + prompt + credential -> edit -> candidate
```

- A displayed candidate or upscale never replaces the base reference used for edit.
- Local adoption performs no upload and submits no provider request.
- A failed operation leaves the prior graph state intact.
- Provider success with unreadable image data is a failed operation and creates neither a source nor a candidate.
