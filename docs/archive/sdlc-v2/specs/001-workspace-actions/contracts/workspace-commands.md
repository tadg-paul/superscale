# UI Contract: Workspace Commands

## Command Matrix

| Command | Shortcut | Blank canvas | Picture loaded | Editable text owns focus |
|---|---|---|---|---|
| Copy | `Cmd+C` | No image action | Copy displayed picture | Copy selected text |
| Paste | `Cmd+V` | Import supported clipboard image | Picture-level action disabled; workspace unchanged | Paste into text |
| Save As | `Cmd+S` | Disabled | Open Save As at valid configured directory | Open Save As from application text; an active modal system panel retains native handling |
| Save All | None | Disabled | Export all eligible workspace images; Cancel Save All while active | Unchanged |
| New | `Cmd+N` | Clear remains a no-op | Use existing unsaved-work guard | Unchanged |
| Open | `Cmd+O` | Open image chooser | Use existing unsaved-work guard | Unchanged |

## Active Save All

- While a batch is active, New, Open, Open Recent, the canvas Clear Image action, drag and drop, picture Paste, Save As, Apply, Lock, iteration selection, the base-versus-candidate display toggle, scale, model, face enhancement, and repeated Save All are disabled.
- The corresponding handlers re-check batch activity, including shortcut and accessibility entry points that could bypass a disabled control.
- A shortcut received for a disabled action changes nothing and is not queued for later execution.
- Cancel Save All remains available.
- Search, prompt editing, comparison, and Settings remain available because the batch uses a configuration and membership snapshot.

## Clipboard Contract

- The standard pasteboard command group retains the native `Cmd+C` and `Cmd+V` key equivalents.
- An editable text responder handles native Copy or Paste before the workspace responder; only an unhandled selector reaches the workspace image action.
- Canvas interaction makes the workspace responder current, and a blank workspace uses it by default when no editor or modal panel owns focus.
- Separate `Copy Image` and `Paste Image` menu items remain discoverable and accessible but have no duplicate key equivalents.
- Copy places the currently displayed image on the general pasteboard in a representation another Mac application can consume.
- On a blank canvas, Paste remains available without pre-validating the current clipboard.
- At execution time, the paste path inspects advertised pasteboard types before decoding and accepts PNG, JPEG, TIFF, and HEIC.
- An advertised image type outside that set, including PDF, leaves the graph unchanged and uses the existing error surface.
- Paste imports through the ordinary source path and starts a new empty lock chain.
- Picture-level Paste is visibly unavailable while a picture exists.
- A late paste request cannot replace a workspace that became populated after the key event.
- Unreadable image contents leave the graph unchanged and use the application's existing error surface.

## Save As Contract

- Eligibility is identical for the File command and canvas control: `savableImage` exists.
- Prompt, search, and Settings text focus does not suppress `Cmd+S`; those controls have no standard Save command.
- An active modal system panel handles its own keys and does not permit a nested Save As panel.
- The save panel starts in the configured writable directory.
- If that directory is stale, the panel starts in resolved Downloads. After the panel closes, `outputFolderWarning` appears in the workspace notice area with an `openOutputFolderSettings` link.
- Cancel writes nothing and changes no saved state.
- Encode or write failure uses the existing error surface and does not mark the source saved.
- A successful save marks the displayed source saved for the clear-workspace warning.

## Accessibility and Discoverability

- File and Edit menu entries retain stable accessibility identifiers.
- Disabled state is observable through the menu item, not inferred from a silent shortcut.
- Category chip accessibility values continue to say whether each chip is narrowing.
- Save All exposes `saveAllCommand` and `saveAllButton`; cancellation exposes `cancelSaveAllButton`.
- Batch progress exposes `batchSaveProgress` with a `current of total` value, and completion exposes `batchSaveSummary` with saved, failed, and unattempted counts.
