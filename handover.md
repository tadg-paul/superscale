# Handover --- Superscale v2, 2026-08-26

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
the delivery; master #99 carried the post-delivery defect closure. All of
#99's children (#100--#103, #105) are closed.

**One debt outstanding, and it is your first action** (next section): the
#99 children were closed ahead of the delivery's own gate, so the full-suite
verification is owed but not run.

The cloud path is **live-proven**, not just stubbed: OT-107.1--107.4 ran the
real wire protocol (storage initiate, CDN round trip, grok generation,
decodable image) on 2026-08-25. Evidence on #107.

## Next actions, in order

1. **Run the owed delivery-level verification and record it on #99.**
   - `make test` --- baseline to match: **533 executed, 6 skipped, 0 failures**
   - `make test-gui` --- baseline: **101 executed, 0 failures**; read the GUI
     run rules below first, they are load-bearing
   - Post both results on #99. Green satisfies the "full regression suite"
     line of #99's completion matrix; anything else is a defect to ticket
     **before** touching it (see process rules).
2. **#99's exit gate** --- after the verification is recorded. The gate
   decision and wording are governed by the SDLC; the human decides delivery
   acceptance.
3. **The open defect tickets.** Every one carries its reproduction, violated
   AC, and a staged debugging/fix procedure written to be executed cold ---
   start from the ticket, not from this summary:

   | Ticket | One line |
   |---|---|
   | #106 | Choosing a scale after a completed run can serve the previous scale's cached rendering under the new scale's label (`willSet` trap). Deliberately unfixed; the three-line fix breaks three closed tickets' GUI tests that encode the defect's timing. Five-step procedure on the ticket, starting with the failing test. |
   | #108 | Info panel does its own scale arithmetic (`InfoPanel.swift:76`), contradicting the status bar and the ceiling. Failed UT-93.1. |
   | #109 | Account/admin key row accepts a click and shows nothing. The *no-verification* stance is deliberate and stays; the silent control is the defect. |
   | #110 | Settings fields resize and the form jumps while typing a credential. Diagnose before fixing; likely unreserved status-slot space. |
   | #111 | Opening a locked iteration hides the lock chain, making other iterations unreachable. Failed UT-89.1. |
   | #112 | A filter result offers no comparison curtain. Blocks UT-96.1; with #111 re-offers UT-89.1. |
   | #113 | A failed generation request lands only in the status-bar caption, never on the one failure surface (AC98.5). Repro stub exists: `SUPERSCALE_UI_TEST_FAIL=provider`. |
   | #66 | Pre-v2: comparison divider invisible over bright regions. Paint only --- do not touch geometry; UT-90.1 was just re-passed on it. |

4. **Author-pending items** (do not act on these; they are the human's):
   - UT-94.1 and UT-96.1 verdicts (empty arrows in
     `ut-human-tests-2026-08-25.md` at the repo root)
   - UT re-offers gated on fixes: UT-93.1 (#108), UT-95.1 (#109+#110),
     UT-89.1 (#111+#112), UT-96.1 (#112)
   - UT-69.1 (README logo/trademark wording) --- #69 is otherwise done
   - `APPROVED 79` once every rolled-up UT has a human result

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
  `private(set)`; `report`/`dismissError` are the only ways in. #113 is the
  one known path that bypasses the surface.
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
