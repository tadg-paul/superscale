# Integration Contract: Grok Prompt Routing

## Route Selection

| Workspace state | Operation | Reference count | Reference identity | Result role |
|---|---|---:|---|---|
| No base; drop target visible | Default Grok generation | 0 | None | Source |
| Base present; identical held result | Local adoption | 0 | None | Candidate |
| Base present; no identical held result | Default Grok edit | 1 | Current base | Candidate |

## Blank-Canvas Generation

- Requires a configured FAL generation credential and non-whitespace prompt.
- Uses the MVP default model identifier without the `/edit` suffix.
- Performs no reference upload and sends no reference field.
- Retains the generation operation's supported sizing behaviour.
- A successful image enters the ordinary new-source workflow with no parent or lock chain.

## Non-Empty-Canvas Edit

- Before upload, an identical held result for the same base, model, and prompt as sent is adopted locally as the candidate. That branch performs no upload and submits no provider request.
- Only the absence of an identical held result enters the provider edit route.
- Uses the MVP default model's `/edit` operation.
- Uploads exactly the current graph base.
- Does not substitute a displayed candidate, locked selection's upscale, or render cache.
- Omits sizing where the edit operation does not accept it.
- A successful image becomes the current candidate and keeps its base parent.

## Failure and Evidence

- Failure leaves the graph and canvas's prior picture intact.
- A provider success response whose image cannot be decoded is treated as failure and creates neither a source nor a candidate.
- Safe diagnostics contain neither credentials nor image payloads.
- Package tests prove request construction and endpoint choice.
- GUI tests capture upload calls and submitted requests at the controlled generation-service seam. Blank-canvas Apply proves zero upload calls and zero references; populated-canvas Apply without a matching held result proves one base upload and exactly that base reference; repeated identical Apply proves no additional upload or request.
- Automated tests never contact FAL. Any real-provider verification is a separately recorded, bounded user test.
