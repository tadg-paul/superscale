# Handover --- Superscale v2, updated 2026-08-27

Written by the outgoing session for the incoming one. **This file is a
snapshot and goes stale; the tickets do not.** Where this file and a ticket
disagree, the ticket wins. Where design and code disagree, the order of
authority is: `docs/ACs.md` (criteria) -> `docs/IMPLEMENTATION_GUIDE_v2.md`
(design of record; **start at section 8**) -> `docs/ARCHITECTURE.md`
(as-built) -> everything else.

## Read this first: the history rewrite

The repository's history was rewritten with `git filter-repo` on 2026-08-25
(erasing a tracked build log and EXIF GPS data) and force-pushed. Every commit
SHA changed. Consequences:

- Any SHA cited in an issue comment written before the rewrite **will not
  resolve** in your clone. That is expected, not corruption. Open tickets have
  been annotated in place (`` `new` (pre-rewrite `old`) ``); older comments
  have not. The full old->new table is a comment on #99 titled "commit SHA
  translation table".
- Where a stale SHA has no annotation, search `git log` for the commit
  subject quoted beside it --- the messages survived the rewrite unchanged.
- Never merge a pre-rewrite clone. Discard it or hard-reset to
  `origin/master`.

## Where the build stands

The v2 MVP is delivered and running: one workspace, 86 filters through
`xai/grok-imagine-image/edit`, asset graph with base/candidate/lock chain,
native local upscaling under a 32-megapixel area ceiling. Master #79 carries
the delivery; master #99 carried the post-delivery defect closure; master
#114 carried the post-MVP verification and defect clearance. All of #99's
children (#100--#103, #105) are closed, and so are all twelve of #114's.

**The verification debt is discharged.** The 2026-08-26 note below said the
owed full-suite run was the incoming session's first action. It was run on
2026-08-27 and recorded on #99 and #114:

| Command | Baseline | 2026-08-27 |
|---|---|---|
| `make test` | 533 / 6 skipped / 0 failures | **556 / 6 skipped / 0 failures** |
| `make test-gui` | 101 / 0 failures | **141 / 0 failures** |

An earlier attempt on 2026-08-26 gave 101 executed with **6 failures**. That
was recorded as a failure rather than banked, diagnosed to #115 and #116, and
both were ticketed and closed. The run above is the same command against the
repaired tree.

**Both masters have DELIVERY EXIT records posted and are awaiting their gate
keywords.** Those are the human's, as is every user-test verdict. Nothing
automatable is outstanding.

The cloud path is **live-proven**, not just stubbed: OT-107.1--107.4 ran the
real wire protocol (storage initiate, CDN round trip, grok generation,
decodable image) on 2026-08-25. Evidence on #107.

## Next actions, in order

**There is no executable engineering work queued.** Every automated blocker
is cleared. What remains is human judgement, and an agent must not act on it.

1. **Author-pending items** (these are the human's, not yours):
   - Gate keywords for masters **#99** and **#114**, both of which have
     DELIVERY EXIT records posted.
   - User tests transferred to #114: **UT-66.1** to **UT-66.4** (the divider
     line and circle handle against bright and dark regions) and **UT-119.1**
     (the centred progress indicator, worded without a preferred answer).
   - UT re-offers on #79, all now unblocked: UT-94.1, UT-93.1 (was #108),
     UT-95.1 (was #109 and #110), UT-89.1 (was #111 and #112), UT-96.1
     (was #112). Empty arrows in `ut-human-tests-2026-08-25.md` at the repo
     root.
   - UT-69.1 (README logo/trademark wording) --- #69 is otherwise done.
   - `APPROVED 79` once every rolled-up UT has a human result.

2. **#106 is the only open defect ticket, and deliberately so.** Choosing a
   scale after a completed run can serve the previous scale's cached rendering
   under the new scale's label (the `willSet` trap). The three-line fix is
   reverted: it changes run-versus-cache timing that three closed tickets' GUI
   tests encode. Five-step procedure on the ticket, starting with the failing
   test. **#119 added a second consequence**: the GUI suite cannot start real
   work by changing presets, which makes a class of test unwritable. RT-119.4
   is the first casualty; its sequence and reasoning are preserved in place in
   `SuperscaleAppUITests.swift` for reinstatement with #106.

3. **The 2026-08-26 defect queue, for the record.** Every ticket below is
   **closed**; the column says what each turned out to be, because in three
   cases the ticket's own hypothesis was wrong and that is the reusable part.

   | Ticket | Closed as |
   |---|---|
   | #108 | Info panel did its own scale arithmetic (`InfoPanel.swift:76`). Now derived through `SizingLine` from `ScaleReadout` and `UpscaleCeiling.decide`. |
   | #109 | **Not** the absence of verification, which was deliberate and stays. The badge read the *text field*, so it flipped to "stored" on the first keystroke and the press had no state change left to make. |
   | #110 | A `ProgressView` and a status badge swapped straight into the row's `HStack`; differing intrinsic widths resized the stack, the field, then the form's label column. Fixed-width slot. |
   | #111 | The view treated a locked iteration being *viewed* as a new import. |
   | #112 | `derivedImage` was bound to `viewModel.result` alone, so the curtain was offered only after an upscale --- and the raise to the filterable minimum turns the scale off. |
   | #113 | **Reached no surface at all**, not merely the wrong one: nothing observed `.failed`; the caption showed it only because `statusText` reads the phase on every redraw. Also exposed that RT-98.14 had only ever exercised the *upload* route. |
   | #66 | Dark outlines via `strokeBorder`, not `stroke` --- `stroke` centres on the path and grew the handle from 28pt to 29.5pt. |
   | #115 | `AssetGraph` allocated beneath a directory nothing created; it worked only while `GenerationCoordinator` made it as a side effect. |
   | #116 | The GUI suite redirected the coordinator and history to its test root but not the workspace's asset graph, so UI tests wrote into the author's real Application Support. |
   | #117 | The suite's completion signal was a control #112 changed. The canvas now reports what it displays, in its **label** --- four measurements showed SwiftUI carries no *value* on a `children: .contain` container. |
   | #118 | **Not a defect in this project.** An external managed installer was taking first responder. |
   | #119 | A change of intent, not a regression. The horizontal centring **never failed**: `workingIndicator` matched several elements and `firstMatch` was measuring the spinner at the badge's left edge. |

## GUI test run rules (violating these produces fake failures)

- **The machine to itself.** No concurrent builds, no package suite
  alongside. An overlapped run took 1450s against 956s alone and reported
  starvation as a timeout. Do not rebuild the bundle mid-run.
- **Display awake and unlocked for the whole run.** A screensaver or lock
  engaging mid-run makes accessibility calls fail in ways that read as
  element timeouts. Wrap runs in `caffeinate`:

  ```
  caffeinate -dims make test-gui &
  TEST_PID=$!
  while kill -0 $TEST_PID 2>/dev/null; do caffeinate -u -t 1; sleep 300; done
  ```

  Before trusting a full run on a new machine, probe: start the keepalive,
  touch nothing past the screensaver interval, confirm no lock. Lid open, on
  mains.
- **Judge runs by `Executed N tests`, not by the absence of a failure
  section.** A killed or wedged run has neither; report it INCONCLUSIVE,
  never green.
- xcresult bundles: `xcrun xcresulttool get test-results summary --path
  <bundle>` gives failure text; `test-details --test-id` gives per-test
  narrative. Some bundles from killed runs lack `Info.plist` and are
  unreadable --- that is the run's fault, not yours.
- Xcode scheme is `SuperscaleWithTests` (there is no `Superscale` app
  scheme). Build with `build-for-testing`, run with `test-without-building`.

## Test doctrine (the short version; guide section 7 is the long one)

- `make test` is hermetic: stub transports, no credentials, no network.
  Every GUI test launches the app with `UITestCredentialStorage` and stubbed
  services (`SuperscaleApp.swift`, DEBUG block).
- **Live one-offs are not repeated.** OT-107.x passed once; the grok call
  costs real money. There is deliberately no make target; the only entry
  point is `scripts/run-live-ot.sh`, which **sources** `.env` (`FAL_KEY`,
  `FAL_ACCOUNT_KEY`) --- never parse `.env`. Keychain fallback:
  service `org.tigoss.superscale.generation`, account `fal-generation`.
- Tests never pass by grepping source or documentation. Structural claims
  (a type absent, one function only, no global actor) are confirmed by
  `audit-code`, not by tests --- there are four precedents in `docs/ACs.md`.
- Scale buttons are a **toggle group**: clicking the active scale turns
  upscaling off. Use the suite's `selectScale(_:)` helper, which asserts
  before clicking and waits for the request to register.

## Traps that bit this codebase (all now guide rules; numbers are guide 3.x)

- **`@Published` publishes in `willSet`** --- inside a sink, the property still
  holds the old value. Take the value as a parameter. Bit twice in one file,
  three lines apart, the second directly under the comment warning about the
  first (#104/#106).
- **A control that accepts a click must cause something or say it did not**
  (#104, #109, #113 are all this shape).
- **SwiftUI accessibility hides state four ways**: a container with an
  identifier absorbs its children (needs `.accessibilityElement(children:
  .contain)` --- found six times, rule 3.9/D-2); state expressed only as
  colour; `Circle`/`Rectangle` never enter the tree; a value the tree does
  not carry (set label *and* value).
- **Measuring a picture must not decode it** --- `ImageDimensions.pixelSize`
  reads the header; `NSImage.size` reports DPI-adjusted points and caused a
  months-long defect. One measuring function exists; do not add a second.
- **Failure has one owner**: `UpscaleViewModel.errorMessage` is
  `private(set)`; `report`/`dismissError` are the only ways in. **Read that
  guarantee narrowly.** It stops a path writing the message *somewhere else*.
  It does nothing about a path that never reports at all, which is exactly what
  #113 was: no code wrote `errorMessage`, the guarantee held perfectly, and the
  provider's error reached the user as caption text at the foot of the window.
  `ARCHITECTURE.md` now spells out the distinction beside the claim.
- **A test can pass by not running.** RT-90.49 asserted a clause #119 had
  superseded, against an indicator that had been moved, and stayed green: it
  sits behind a `guard indicator.waitForExistence(timeout: 3) else { return }`
  and the suite's fixture is small enough that the work usually outruns the
  poll. Several assertions in this suite sit behind such guards. A green result
  from one of them is weaker evidence than it looks.
- **When a measurement disagrees with the code, measure what is being
  measured.** #119 spent four remediation cycles moving a layout that was
  already correct, because `workingIndicator` matched several elements and
  `firstMatch` was returning the spinner at the badge's left edge. Putting the
  frames into the assertion message produced the answer in one run. An
  identifier applied to a plain container reaches its children; if a test reads
  `.frame` from such a query it is measuring something it did not name.
- **Stubs rehearse belief.** The storage `storage_type` was wrong for the
  entire delivery and no stubbed test could know (#107). Any protocol change
  re-proves through a live OT before the stubs are trusted again.

## Process rules the author enforces (learned, not theoretical)

- **Log a defect ticket before working on it.** No exception for defects
  found mid-verification. Tickets carry repro, violated AC, and procedure.
- **Never mark a user test passing or failing** --- only the author does.
  Present UTs with concrete steps and judging notes; transcribe the author's
  verdicts verbatim onto #79's roll-up.
- **Never delete recorded information** --- supersede in place, struck
  through, with the reason and date.
- **Assertions require evidence in the same breath.** Two diagnoses in this
  delivery were wrong because they were plausible; the fix both times was
  instrumenting the system to report its own state. Diagnostics before
  explanations, and one correction is a signal to isolate, not to guess
  again.
- Both machines push as the same GitHub identity --- the events API cannot
  tell the sessions apart. Say which session did a thing in the comment
  itself, because nothing else records it.
- AC/test record formats, gate keywords, and closure rules are in the SDLC
  documents loaded at session start; follow them, not memory of them.

## Repo miscellany

- `docs/ACs.md`: 118 criteria, per-test status marks. #102's RT-102.x rows
  are ✅ against `FalStorageClientTests` 19/0.
- `docs/E2E_DESIGN.md`, `docs/v1/`, `docs/proposal/`: historical, bannered
  as such; do not implement from them.
- `ut-human-tests-2026-08-25.md` at the repo root is the author's live
  answer sheet (two verdicts pending). Leave it alone.
- Homebrew: formula sha256 was refreshed after the rewrite (tap commit
  `eeb2a83`); the cask points at release *assets*, which were unaffected.
  The formula's source URL uses a redirecting old account name --- known,
  deliberate, low priority.
- The author's local tap repo has an unrelated diverged state
  (`first-folio.rb`); not this project's concern.

## Verification quick reference

| Command | Baseline | Notes |
|---|---|---|
| `make test` | 533 executed, 6 skipped, 0 failures | ~6 min; hermetic |
| `make test-gui` | 101 executed, 0 failures | ~30 min; exclusive machine, display awake |
| `make test-ssim` | all ≥ 0.90 | required only when the v1 pipeline core changes |
| `make test-one-off` | layout tests only | skips `LiveTests` by design |
