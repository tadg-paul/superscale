# UI Contract: Save All

## Eligibility

Save All is available when the active workspace has a base image and no conflicting local or provider operation owns the workspace.

## Population and Order

One invocation exports each distinct item in this order:

1. Held-chain entries in their stored order, beginning with the initial source.
2. Any promoted minimum-resolution raise in its chain position, labelled `prepared`.
3. Locked filtered iterations, labelled `iteration`.
4. Current unlocked filtered candidate, when distinct, labelled `candidate`.

Temporary render caches, abandoned outputs, session metadata, and assets from other sessions are excluded.

## Output

- Destination: configured writable output directory.
- Format: PNG.
- Sizing: stored size when scale is off; each source multiplied independently for a preset scale; with custom stretch off, the selected defining dimension plus that source's own aspect ratio; with custom stretch on, the selected absolute width and height for every source.
- Limits: the existing per-image 8x dimension cap and output-area ceiling are re-evaluated for each source, with each reduction retained for the summary.
- Processing: sequential, on-device, subject to the existing output-area ceiling.
- Rendering source: every scaled item runs directly through the coordinator and never reuses the display rendering cache.
- Naming: descriptive source, role, and sequence stem; numeric suffix on collision.
- Overwrite: never.
- Interaction: no per-file panel or confirmation.

## Progress and Completion

- Progress names the current item and position in the batch.
- The canvas badge exposes `batchSaveProgress` with a `current of total` accessibility value.
- Existing size-reduction notices remain available in the final result.
- The status and notice area exposes `batchSaveSummary` with successful, failed, and unattempted counts plus safe per-item failure details.
- Cancel Save All is available while a batch is active. Cancellation stops the current pipeline, preserves successful files already written, starts no remaining item, and reports saved, failed, and unattempted counts.
- Successfully written source URLs become saved for the unsaved-work warning.
- Failed source URLs remain unsaved.
- Cancelled and therefore unattempted source URLs remain unsaved.
- The existing warning population remains locked iterations only; save bookkeeping for source and unlocked-candidate roles does not widen it.
- A stale or unwritable destination stops the batch before the first write and routes the user to Settings.

## Failure Safety

- Destination paths are reserved before use and constrained to the configured directory.
- Each output is created atomically with a no-overwrite option. A destination occupied after reservation fails that candidate rather than replacing the file.
- An encode, processing, or write failure for one candidate does not stop later candidates.
- No partial or failed output is reported as saved.
- No output operation sends image data to an external provider.
