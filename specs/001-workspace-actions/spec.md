# Feature Specification: Reliable Workspace Actions

**Feature Branch**: `master`

**Created**: 2026-09-04

**Status**: Draft

**Input**: User description: "Deliver working Cmd+C and Cmd+V image actions, make Cmd+S open Save As for one displayed file, add one-click Save All for the existing images represented by locked panels using a configured default directory and no new rendering or upscaling, clear search text when a filter category is chosen, and route an empty-canvas prompt through the default Grok generation operation while every non-empty-canvas prompt remains an edit of the base image."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Dependable Mac File Actions (Priority: P1)

A user can copy, paste, and save the image by using the standard Mac keyboard shortcuts. The same shortcuts continue to edit text when a text field has focus.

**Why this priority**: These are standard Mac interactions. Their presence in a menu is not sufficient when the keyboard action does not reach the image.

**Independent Test**: With an image on the canvas, use `Cmd+C` and paste into another application, then use `Cmd+S` and verify that a Save As dialog opens. Clear the canvas, place an image on the clipboard, and use `Cmd+V` to import it.

**Acceptance Scenarios**:

1. GIVEN a picture is displayed and no editable text has focus
   WHEN the user presses `Cmd+C`
   THEN the displayed picture is placed on the clipboard in a form another Mac application can paste.
2. GIVEN the canvas is blank and the clipboard contains a readable picture of a type accepted by drag and drop
   WHEN the user presses `Cmd+V`
   THEN the picture is imported as a new source and starts an empty iteration chain.
3. GIVEN the canvas already contains a picture
   WHEN the user views Paste or a previously accepted paste command arrives late
   THEN the action is visibly unavailable and the existing workspace remains unchanged.
4. GIVEN editable text has focus
   WHEN the user presses `Cmd+C` or `Cmd+V`
   THEN the shortcut applies to the selected text or insertion point and does not copy or replace the canvas picture.
5. GIVEN any picture is saveable, including a picture with scaling turned off
   WHEN the user presses `Cmd+S`
   THEN a Save As dialog opens at the configured default save directory for that one displayed picture.
6. GIVEN a Save As dialog is open
   WHEN the user cancels it
   THEN no file is written and the workspace is unchanged.
7. GIVEN the canvas is blank
   WHEN the user presses `Cmd+C` or `Cmd+S`
   THEN no image is copied and no save dialog opens.

---

### User Story 2 - Save Every Locked Panel Once (Priority: P1)

A user can save the existing image represented by every panel in the locked-image strip with one Save All action instead of selecting and saving each panel separately.

**Why this priority**: The locked panels represent work the user deliberately kept and may have paid to produce. Repeated Save As dialogs make preserving that work slow and error-prone.

**Independent Test**: Build a locked-image strip containing several panels, retain an existing upscale for one panel but not another, and leave an unlocked candidate on the canvas. Invoke Save All once and verify that one file per locked panel is written to the configured directory, the existing upscale is used where present, the stored filtered image is used otherwise, the unlocked candidate is excluded, and no rendering or upscaling begins.

**Acceptance Scenarios**:

1. GIVEN a configured, writable default save directory and several panels in the locked-image strip
   WHEN the user invokes Save All from its button or presses `Cmd+Shift+S`
   THEN the image represented by every locked panel is saved once without individual save dialogs.
2. GIVEN a locked panel has an already-produced upscale matching the current display configuration
   WHEN Save All runs
   THEN that existing upscaled rendition is saved for the panel.
3. GIVEN a locked panel has no already-produced upscale matching the current display configuration
   WHEN Save All runs
   THEN the panel's stored filtered image is saved at its existing resolution.
4. GIVEN one or more locked panels lack an existing upscale
   WHEN Save All runs
   THEN no rendering or upscaling starts and no image represented by a panel is changed.
5. GIVEN a proposed output name already exists
   WHEN Save All runs
   THEN the existing file is not overwritten and the new output receives a distinct descriptive name.
6. GIVEN one image cannot be encoded or written
   WHEN Save All runs
   THEN the application continues with the remaining images and reports which outputs succeeded and which failed.
7. GIVEN there are no panels in the locked-image strip
   WHEN the user looks for Save All
   THEN the action is unavailable and writes nothing.
8. GIVEN the configured directory has become unavailable or unwritable
   WHEN Save All is requested
   THEN no output is silently redirected and the user receives a useful error with a route to Settings.
9. GIVEN an upscale, filter, generation, edit, or prior Save All operation is active
   WHEN the user views the Save All button or command or presses `Cmd+Shift+S`
   THEN the button and command are disabled and no Save All operation starts.
10. GIVEN Save All exports some images successfully and others fail
   WHEN the final summary appears
   THEN successfully exported images count as saved and failed images remain unsaved for the existing clear-workspace warning.

---

### User Story 3 - Mutually Exclusive Filter Narrowing (Priority: P2)

A user narrows the filter catalogue either by search text or by category, never by an accidental combination of both.

**Why this priority**: A hidden second narrowing makes filters appear to be missing and leaves the visible controls describing a state that is not actually in effect.

**Independent Test**: Enter a search query, choose a category, and verify that the query clears before the category result count is shown. Then focus the search field and verify that the selected category clears.

**Acceptance Scenarios**:

1. GIVEN the search box contains any text
   WHEN the user chooses any category, including All
   THEN the search text clears before the category filter is applied.
2. GIVEN a category is active and the search box contains text
   WHEN the user focuses the search box
   THEN the category clears, the existing search text remains, and search covers the whole catalogue.
3. GIVEN neither a category nor search text narrows the catalogue
   WHEN the panel is shown
   THEN all available filters are listed.
4. GIVEN the whole catalogue is being searched or listed
   WHEN the category controls are displayed
   THEN no specific category chip appears active.

---

### User Story 4 - Generate on Blank, Edit Otherwise (Priority: P1)

A user can type a prompt on a blank canvas and generate a new source picture. Once any picture exists, prompt submission always edits the workspace's base picture.

**Why this priority**: The product already presents the prompt and Apply interaction on a blank canvas. The request route must match that visible promise and must not confuse generation with editing.

**Independent Test**: Submit a prompt on a blank canvas and verify that the default Grok generation operation receives no reference image. Then submit a different prompt after a picture is present and verify that the Grok edit operation receives the current base image, not a candidate or upscaled rendering.

**Acceptance Scenarios**:

1. GIVEN an empty canvas, a non-empty prompt, and a configured generation credential
   WHEN the user applies the prompt
   THEN the default Grok generation operation is used without an edit suffix and without uploading or attaching a reference image.
2. GIVEN the blank-canvas generation succeeds
   WHEN the result arrives
   THEN it becomes the source picture for an otherwise ordinary workspace.
3. GIVEN any source picture is present
   WHEN the user applies any prompt
   THEN the default Grok edit operation receives the existing base picture as its reference.
4. GIVEN an unlocked candidate or an upscaled rendering is displayed
   WHEN the user applies another prompt
   THEN the edit still uses the base picture rather than the displayed derivative.
5. GIVEN an empty canvas and an empty or whitespace-only prompt
   WHEN the user views Apply
   THEN Apply is unavailable and no provider request is made.
6. GIVEN an empty canvas without a configured generation credential
   WHEN the user views the prompt controls
   THEN Apply is unavailable and Settings remains reachable.
7. GIVEN a generation or edit request fails
   WHEN the error is reported
   THEN the workspace remains intact and no credential or image payload appears in the diagnostic.

### Edge Cases

- Clipboard contents can advertise an image while still being unreadable. The canvas remains unchanged and a useful error is shown.
- A clipboard shortcut received after canvas state changes is checked against the current state before any import occurs.
- Save All follows the locked-image strip's stable panel order and writes each represented image once.
- A current unlocked candidate is not included until the user locks it and it becomes a panel.
- Save All may finish too quickly for progress to be visible. If saving remains visible, it uses the existing single working indicator rather than adding a second progress element.
- Search text containing only whitespace is cleared in the same way as visible search text when a category is chosen.
- Provider success with an unreadable result is treated as a failed generation and does not create a source.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The application MUST bind `Cmd+C`, `Cmd+V`, and `Cmd+S` to the image actions described in User Story 1 when editable text does not own the command.
- **FR-002**: The application MUST preserve standard `Cmd+C`, `Cmd+V`, Cut, and Select All behaviour inside editable text controls.
- **FR-003**: Image copy MUST use the image currently displayed on the canvas, including its current upscale when one is displayed.
- **FR-004**: Image paste MUST be visibly unavailable while the canvas contains a picture. Paste MUST be accepted only while the canvas is blank, MUST accept the same PNG, JPEG, TIFF, and HEIC image types as drag and drop, and MUST enter the same new-source workflow as other imports. Eligibility MUST be re-checked against current canvas state immediately before import.
- **FR-005**: `Cmd+S` MUST open Save As for the one image currently displayed whenever the existing Save As control can save it.
- **FR-006**: Save As MUST start in the configured default save directory without bypassing the user's final filename and location choice.
- **FR-007**: If the configured default save directory is no longer available or writable when Save As opens, Save As MUST start in the resolved Downloads directory.
- **FR-008**: When Save As falls back from an invalid configured directory, the application MUST report the invalid setting with a route to Settings.
- **FR-009**: The existing configured output-folder preference defined by AC73.2 and AC95.4 MUST also serve as Save As's initial directory and Save All's destination. Settings MUST continue to expose and persist that one non-secret folder choice, existing stored choices MUST carry forward unchanged, and a new installation MUST default it to the user's resolved Downloads directory.
- **FR-010**: Save All MUST save, in one invocation and without per-file dialogs, one file for each image represented by a panel in the locked-image strip, in panel order. It MUST exclude an unlocked candidate and every other image not represented by a locked panel.
- **FR-011**: For each locked panel, Save All MUST use an already-produced upscale matching the current display configuration when one exists and MUST otherwise use the panel's stored filtered image at its existing resolution. Save All MUST NOT start rendering, filtering, generation, editing, or upscaling.
- **FR-012**: Save All MUST NOT overwrite an existing file. A colliding output MUST receive a distinct descriptive name derived from the image's role and chain position, without interrupting the batch for a choice.
- **FR-013**: Save All MUST attempt every eligible image after an individual output failure and MUST report a final saved-and-failed summary.
- **FR-014**: Each image that Save All exports successfully MUST count as saved for the existing unsaved-work warning; each image whose export fails MUST remain unsaved.
- **FR-015**: Choosing any filter category MUST clear the filter-search text before recalculating the visible catalogue.
- **FR-016**: Focusing the filter-search field MUST continue to clear the active category while preserving any text already entered in the field.
- **FR-017**: A specific category chip MUST appear active only while that category actually narrows the catalogue. When the whole catalogue is listed or searched, no specific category chip may appear active.
- **FR-018**: Blank-canvas prompt submission MUST use the MVP's default Grok generation operation and MUST send no reference image.
- **FR-019**: Non-empty-canvas prompt submission MUST use the MVP's default Grok edit operation and MUST send exactly the current base image as its reference.
- **FR-020**: A successful blank-canvas generation MUST become a source image, with no parent and no pre-existing lock chain.
- **FR-021**: Blank-canvas generation MUST require a non-empty prompt and a configured generation credential.
- **FR-022**: Existing `Cmd+N`, `Cmd+O`, scale-toggle, face-enhancement, unsaved-work warning, progress presentation, locking, comparison, and single-image Save As behaviour MUST remain unchanged except where this specification explicitly changes Save As command eligibility.
- **FR-023**: Provider-failure diagnostics MUST NOT contain credentials or image payloads.
- **FR-024**: Save All MUST be available from one visible button and from `Cmd+Shift+S`. The button, command, and shortcut MUST be unavailable while an upscale, filter, generation, edit, or previous Save All operation is active.
- **FR-025**: Save All MUST use the existing single working indicator if its file-writing activity remains visible long enough to present progress. It MUST NOT add a second simultaneous working indicator.
- **FR-026**: When the configured default save directory is unavailable or unwritable, Save All MUST perform no writes, MUST NOT silently redirect output, and MUST report a useful error with a route to Settings.

### Validation Constraints

- **VC-001**: Automated validation must exercise the keyboard shortcuts themselves; invoking only their menu items is not sufficient evidence for `Cmd+C`, `Cmd+V`, or `Cmd+S`.
- **VC-002**: Automated validation of provider routing must use controlled local substitutes. A real metered generation, if performed, remains a bounded one-off user test rather than a persistent regression test.

### Key Entities

- **Default save directory**: The existing configured output-folder preference from AC73.2 and AC95.4, used unchanged as Save As's initial location and Save All's direct output destination.
- **Locked-panel image**: The stored source, promoted minimum-resolution raise, or filtered image represented by one panel in the locked-image strip, together with any already-produced upscale that matches the current display configuration.
- **Base image**: The model-resolution image from which every non-empty-canvas prompt edit derives, regardless of which derivative is currently displayed.
- **Prompt operation**: Either a reference-free generation on a blank canvas or a base-referenced edit on a non-empty canvas.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In keyboard-driven acceptance tests, `Cmd+C`, `Cmd+V`, and `Cmd+S` each complete their specified image action on the first invocation in every eligible canvas state.
- **SC-002**: One Save All invocation saves exactly one file for every locked panel, saves no unlocked candidate, opens no additional dialog, and preserves every pre-existing file in the destination.
- **SC-003**: In a workspace with 25 locked panels, Save All requires one user action, reports 25 successful files when all writes succeed, and starts zero new image-processing operations.
- **SC-004**: Choosing a category after entering a search query leaves the search field empty and produces the same visible result set as choosing that category from a fresh panel.
- **SC-005**: Every controlled blank-canvas request contains zero reference images and targets the default generation operation; every controlled non-empty-canvas request contains exactly the base-image reference and targets the edit operation.
- **SC-006**: Existing automated checks for new-workspace clearing, unsaved-work warnings, progress display, scale shortcuts, face enhancement, text editing, image iteration behaviour, and the unchanged filter-panel search and category rules continue to pass.

## Assumptions

- "All files" means every image represented by the panels currently visible in the locked-image strip. This includes a source panel when the strip presents one. An unlocked candidate, temporary file, and session metadata are excluded.
- Save All reuses a matching upscale already held for a panel. It does not produce a missing upscale; that panel is saved from its stored filtered image instead.
- PNG is the Save All output format because it is lossless and needs no per-file format decision. Save As continues to offer PNG and JPEG.
- Save All writes directly to the configured default save directory. Save As uses that directory only as the dialog's starting location.
- Downloads remains the safe first-run default because the application already resolves and validates that folder without assembling a private machine path.
- No additional model picker is introduced. Both prompt operations use the existing MVP Grok default; canvas state selects generation or edit.

## Brownfield Authority and Scope

- **Requirement authority**: `docs/ACs.org`, including the existing search, copy and paste, saveability, keyboard, output-folder, and prompt-only acceptance records. FR-015 adds category-choice clearing on the route formerly used to set up RT-141.7, while FR-016 retains AC141.1 and RT-141.7's focus-only protection: focus clears the category without clearing existing search text. AC73.2 and AC95.4's existing persisted output-folder preference becomes Save As's initial directory and Save All's destination without a second setting or migration. Clipboard import retains the image types established by Guide 2.2 and migrated ticket #144.
- **Design authority**: `docs/IMPLEMENTATION_GUIDE_v2.md`, especially sections 2.2, 2.4, 2.6, 2.7, and 3.6.
- **Generation sizing context**: Migrated ticket #148 records that the reference-free Grok operation accepts output sizing while the edit operation does not; blank-canvas routing intentionally retains that distinction.
- **Current behaviour considered**: the application commands, filter panel, workspace state, generation request construction, settings, and their maintained tests.
- **Extended saved-state authority**: FR-014 adds Save All as a second route by which a locked iteration counts as saved. AC143.6's displayed-picture Save As route remains unchanged.
- **Superseded evidence**: Menu-item tests that do not press `Cmd+C`, `Cmd+V`, or `Cmd+S` do not establish shortcut delivery. RT-141.7's focus-preserves-text protection remains authoritative, but its former category-choice setup conflicts with FR-015 and must be replaced by blur and refocus without choosing a category. Tests of request construction alone do not establish that the blank-canvas user journey reaches that request.
- **Scope boundary**: This feature changes current-workspace interaction and export only. It does not add formats, models, history browsing, multi-window workspaces, or automatic background saving.
- **Documentation duty**: Delivery must reconcile `docs/IMPLEMENTATION_GUIDE_v2.md`, `docs/ACs.org`, and any current architecture or release-scope statement that would otherwise contradict the delivered paste, Save All, and generation-routing behaviour.
