# Acceptance Criteria

This is the canonical spec. ACs introduced from 2026-08-21 onward live here.
Pre-cutover ACs remain in their originating issues until cited or migrated.

Last migrated: AC117.1 from #117, and the test rows from #108 and #111 onto the criteria they
cite, all on 2026-08-27. Before those: AC82.9, AC82.10 from #115 (backfilled onto the #82 stage
family) and AC116.1 from #116, both on 2026-08-26. Before those: AC100.1, AC100.2 from #100; AC101.1 from #101;
AC103.1, AC103.2 from #103, all on 2026-08-25. #102 introduced no criteria of its own and
extended AC92.1, AC92.5 and AC92.6.

---

## Test layout

### AC80.1 - Tests belonging to the one-off package are outside the regression command's scope.
- Introduced: #80 (closed 2026-08-21)
- Migrated: 2026-08-21
- Tests:
  - ✅ OT-80.1: the main package's enumerated test list contains no test from the one-off package
  - ✅ OT-80.2: the main package's enumerated test list contains the release-inspector regression test that shared a file with the relocated one-off test

### AC80.2 - The one-off command's test scope contains the relocated one-off tests.
- Introduced: #80 (closed 2026-08-21)
- Migrated: 2026-08-21
- Tests:
  - ✅ OT-80.3: the one-off package's enumerated test list contains the relocated one-off test
  - ✅ OT-80.4: the one-off package's tests pass when run
  - ✅ OT-80.9: the one-off command scoped to an issue with no one-off tests reports no match rather than passing silently
  - ✅ OT-80.11: the one-off command scoped to the relocated test's issue number selects that test

### AC80.3 - A one-off test added to the one-off package remains outside the regression scope while the regression command is unedited.
- Introduced: #80 (closed 2026-08-21)
- Migrated: 2026-08-21
- Tests:
  - ✅ OT-80.5: in a synthetic two-package fixture, a one-off test added to the one-off package is absent from the main package's enumerated test list
  - ✅ OT-80.6: the same synthetic one-off test is present in the one-off package's enumerated test list

### AC80.4 - The regression suite retains every regression test present before the relocation.
- Introduced: #80 (closed 2026-08-21)
- Migrated: 2026-08-21
- Tests:
  - ✅ OT-80.7: the post-relocation regression test-name set equals the pre-relocation set, captured before any relocation, less exactly the relocated one-off tests
  - ✅ OT-80.8: the regression command's own run passes with zero failures, no new warnings, and no one-off test among the tests it executed

### AC80.5 - The regression command halts when any main-package test bears a one-off identifier.
- Introduced: #80 (closed 2026-08-21)
- Migrated: 2026-08-21
- Tests:
  - ✅ RT-80.1: the guard halts on a package containing a test that bears a one-off identifier
  - ✅ RT-80.2: the guard proceeds on a package whose tests bear no one-off identifier
  - ✅ RT-80.3: the guard proceeds on a package containing a test name that holds the identifier letters without forming one
  - ✅ OT-80.10: the regression command halts when pointed at a synthetic package containing a misplaced one-off test
  - ✅ OT-80.12: the regression command proceeds when pointed at a clean synthetic package

---

## Asset graph

### AC81.1 - An asset upscaled to the user's chosen output size is never the input to a filter or to a further upscale.
- Introduced: #81 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-81.1: a filter applied while an upscaled asset exists reads the base rather than the upscaled asset
  - ✅ RT-81.2: an upscale requested while an upscaled asset exists derives from the working asset rather than from that output
  - ✅ RT-81.3: an attempt to use an upscaled asset as a stage input reports the rule it breaks
  - ✅ RT-81.25: a stage requested with no working asset reports the absence rather than failing obscurely

### AC81.2 - Applying a filter reads the base asset and replaces the candidate, so filter results chain only when locked.
- Introduced: #81 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-81.4: a second filter applied without an intervening lock reads the base, not the first filter's output
  - ✅ RT-81.5: a second filter applied after a lock reads the locked result
  - ✅ RT-81.30: after a second filter without an intervening lock, the candidate is the second filter's output

### AC81.3 - The base asset changes only by an explicit lock, and a lock never adopts an upscaled asset.
- Introduced: #81 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-81.6: applying a filter leaves the base unchanged
  - ✅ RT-81.7: an upscale leaves the base unchanged
  - ✅ RT-81.8: a lock with no candidate present leaves the base unchanged and reports why
  - ✅ RT-81.9: a lock captures the candidate at model resolution rather than any upscale of it

### AC81.4 - No upscale writes to a path already occupied by another upscale's output.
- Introduced: #81 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-81.10: upscales of two different working assets occupy different paths
  - ✅ RT-81.11: repeated upscales of the same working asset occupy different paths
  - ✅ RT-81.12: an upscale of a session's image resolves to the image the session produced, not to an existing upscale of it

### AC81.5 - An upscaled asset is associated with the nearest session in its ancestry, and with no session when its ancestry holds none.
- Introduced: #81 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-81.13: an upscale descending from a session's asset is associated with that session
  - ✅ RT-81.14: an upscale of an imported image is associated with no session, while an unrelated session is present in the graph
  - ✅ RT-81.15: association survives an intervening unrelated upscale rather than attaching to it
  - ✅ RT-81.19: an upscale whose ancestry crosses two sessions is associated with the nearer

### AC81.6 - Every locked iteration remains reachable from the current base, each carrying the provenance of how it was produced.
- Introduced: #81 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-81.16: after three locks the chain yields the three prior iterations in order
  - ✅ RT-81.17: each locked iteration carries the filter identity that produced it
  - ✅ RT-81.18: provenance holds no credential material
  - ✅ RT-81.20: a locked iteration whose file is absent remains in the chain and reports itself unavailable
  - ✅ RT-81.32: a locked iteration whose file is present reports itself available

### AC81.7 - The current upscaled output of the working asset is identifiable, and it changes when the working asset or the upscale settings change.
- Introduced: #81 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-81.21: an upscale of the working asset is identifiable as its current output
  - ✅ RT-81.22: a second upscale of the same working asset becomes the current output in place of the first
  - ✅ RT-81.23: applying a filter leaves no current upscaled output until one is produced for the new working asset
  - ✅ RT-81.24: an output superseded by a later one is discarded
  - ✅ RT-81.26: the current output is retained rather than discarded alongside superseded ones
  - ✅ RT-81.31: discarding a superseded output leaves the source asset and every locked iteration's file present

### AC81.8 - A stage accepts only an asset reference obtained from the graph, so an arbitrary file location cannot be submitted for processing.
- Introduced: #81 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-81.27: a stage rejects an asset reference the graph does not hold
  - ✅ RT-81.28: the session-to-stage path yields the asset the session produced rather than any upscale of it
  - ✅ RT-81.29: the display path still resolves the finished image, so presentation is unaffected
- Note: the exclusion of bare file locations is a property of the stage signature and carries no
  test. A test cannot assert that an overload is absent, because code calling a function that does
  not exist would not compile. The evidence is that the application target builds after the change
  while the seven correct uses of the display accessor are untouched.

---

## Stages and the scale control

### AC82.1 - Stage progress identifies the phase of work as a value, and carries the counts that belong to it --- faces enhanced, tiles completed and total --- as numbers.
- Introduced: #82 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-82.1: each phase the local pipeline reports arrives as a distinct case, and none of them resolves to the unclassified case
  - ✅ RT-82.2: the number of faces enhanced is available without reading any message text
  - ✅ RT-82.3: tile progress arrives as completed and total counts rather than as text
  - ✅ RT-82.26: a progress report the mapping does not recognize still reaches the caller rather than being dropped
  - ✅ RT-83.20: the stage's phase mapping yields a distinct case for every phase the kit reports, with none resolving to the unclassified case
  - ✅ RT-83.21: a kit phase the stage does not map reaches the caller as unclassified rather than being dropped
- Note: RT-82.1, RT-82.2, RT-82.3 and RT-82.26 were rewritten in #83 against `PipelineProgress`,
  when the kit began reporting phases as values rather than as sentences the stage parsed. The
  criterion is unchanged and the IDs are unchanged; only the source the mapping reads from moved.
  RT-83.20 and RT-83.21 were added to this criterion's coverage by the same issue.
- Note: the mapping from the pipeline's wording to a phase is coupled to that wording until structured progress lands inside `SuperscaleKit`. The coupling lives in one adapter, and the unclassified case is what stops an unmapped message being lost meanwhile.

### AC82.2 - Local upscaling and cloud filtering present one run-state model and one error path, so a caller handles both the same way.
- Introduced: #82 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-82.4: a caller driving either stage observes the same sequence of run states
  - ✅ RT-82.5: a failure in either stage arrives as a failed run state carrying the reason, rather than as a flag with the error discarded
  - ✅ RT-82.6: a cancellation in either stage is distinguishable from a failure
  - ✅ RT-82.27: cancelling a stage that is not running leaves it idle rather than reporting a cancellation

### AC82.3 - When the working image changes, the upscale in flight for the previous one is cancelled, and neither its progress nor its result is observed thereafter.
- Introduced: #82 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-82.7: a run superseded by a newer one is cancelled
  - ✅ RT-82.8: the superseded run's output is not published even when it finishes last
  - ✅ RT-82.9: the newer run's output is the one published
  - ✅ RT-82.28: when the newer run fails, the superseded run's output is still not published
  - ✅ RT-82.36: progress reported by a superseded run after it is superseded is not observed

### AC82.4 - A stage run that does not complete leaves the graph as it was, and leaves no output at the location allocated for it.
- Introduced: #82 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-82.10: a cancelled run leaves no asset behind
  - ✅ RT-82.11: a failed run leaves no asset behind
  - ✅ RT-82.12: the current upscaled output is unchanged after a run that did not complete
  - ✅ RT-82.29: a run cancelled after writing leaves no file at its allocated location

### AC82.5 - A stage writes its output only to the location the graph allocated for it.
- Introduced: #82 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-82.13: the output is written at the allocated location
  - ✅ RT-82.14: the completed run resolves to the asset the graph allocated rather than to a new one
  - ✅ RT-82.35: a completed run leaves the allocated output in the graph's directory and nothing else

### AC82.6 - An upscaled output exists only while a scale is selected.
- Introduced: #82 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-82.15: an image imported with no scale selected leaves no upscaled output
  - ✅ RT-82.16: an image imported with a scale selected has one
  - ✅ RT-82.17: selecting a scale after an import made with none leaves an upscaled output
  - ✅ RT-82.31: clearing the selection while an upscaled output exists releases it
  - ✅ RT-82.33: toggling face enhancement while the selection is cleared leaves no upscaled output
  - ✅ RT-82.34: changing the upscale model while the selection is cleared leaves no upscaled output

### AC82.7 - The scale selection is empty after the active scale is chosen again, and holds the chosen scale in every other case.
- Introduced: #82 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-82.18: choosing the active preset clears the selection
  - ✅ RT-82.19: choosing a different preset selects that one
  - ✅ RT-82.20: choosing the active custom option clears the selection
  - ✅ RT-82.21: with nothing selected, no choice reports itself active
  - ✅ RT-82.30: dimensions typed into the custom fields survive the selection being cleared and restored
  - ✅ RT-82.32: choosing custom makes it the active choice before any dimension is typed

### AC82.11 - No upscale is selected when the application launches, so the first upscale of a session is one the user asked for.
- Introduced: #131 (closed 2026-08-27), backfilled onto the #82 family
- Migrated: 2026-08-27
- Tests:
  - ✅ RT-131.1: no scale is in effect on launch
  - ✅ RT-131.2: importing with nothing selected runs no upscale
  - ✅ RT-131.3: selecting a scale after import runs the upscale
  - ✅ RT-131.7: with nothing selected, upscaling still reads as available
  - ✅ RT-131.4: exactly one scale reads as in effect
  - ✅ RT-131.5: after clearing and reselecting, only the chosen scale reads as in effect
  - ✅ UT-93.1: no scale is in effect at launch, so the first upscale of a session is one the user asked for --- passed by the author in the round of 2026-08-29, recorded on master #133
- Note: **two scales appearing pressed was a rendering fault, not a selection fault.** `tint()`
  returned a fill for `requestedNotInEffect` as well as for `inEffect`, and a tinted `.bordered`
  button reads as pressed --- so a ceiling reduction showed the scale running *and* the scale asked
  for, both apparently selected, and the dimmer of the two read as disabled besides. The author
  diagnosed it as a disabled control; `ScaleReadout.isChoosable` returns true unconditionally and
  nothing was ever disabled. **Decision D-2** on master #120: the reduced scale gets a dashed
  outline instead, which keeps AC82.8's promise that the control shows what was asked for without
  claiming it is what runs. RT-131.4 and RT-131.5 hold the underlying state singular so a later
  rendering change cannot blur it again.
- Note: **decision D-3** declined the request to disable every control above the size threshold.
  `ScaleReadout.swift:88` records why the controls stay pressable --- *"dimmed reads as disabled ---
  which would trap the user at the reduced scale until they imported a different picture"* --- and
  disabling them would deliver the letter of the request while creating that trap. The appearance
  the request was aimed at is what D-2 fixes.
- Note: **this reverses a documented decision rather than fixing an accident.** Guide 2.5 held that
  v1's immediacy --- drop a picture and it upscales at whatever scale is selected --- was the v1
  experience and was kept. In use the cost was paid on the first action of every session, on an
  output a filter-first user is about to set aside, before they had chosen anything. Guide 2.5
  amended at 3.33 **before** the code, since the behaviour being replaced was specified.
- Note: **reactivity is untouched.** An upscale still runs whenever a scale is selected and there is
  something to run on. Only the starting value moved. RT-131.3 is what holds that line.
- Note: **RT-131.2 is what makes RT-131.1 mean anything.** Clearing the selection on launch and
  re-selecting it on import passes RT-131.1 and changes nothing.
- Note: the selection is deliberately not persisted, verified rather than assumed:
  `GenerationPreferences` carries the output folder, the two default models and the default prompt
  pack, and `loadDefaults` does not touch the scale. A persisted scale would make RT-131.1 pass or
  fail by machine, which is the shape that made RT-73.8 environment-dependent.
- Note: **this change failed four other tests on its first run, all at one helper.** With nothing
  selected an import no longer upscales, so `waitForUpscaleComplete()` --- sixty-three call sites ---
  waited for something that would never happen. That is the change being real: sixty-three tests
  were relying on the application starting work nobody had asked for. The helper now asks for a
  scale when none is in effect, and carries a warning that a test meaning *"no upscale should
  happen"* must not call it, because it would cause the very thing being checked.

### AC82.8 - A cleared scale selection persists until a scale is chosen: importing an image, changing the upscale model and changing the custom dimension text all leave it cleared.
- Introduced: #82 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-82.22: importing an image while the selection is cleared leaves it cleared
  - ✅ RT-82.23: changing the upscale model while the selection is cleared leaves it cleared
  - ✅ RT-82.24: a change to the custom dimension text never creates a selection where there was none
  - ✅ RT-82.25: importing an image while a scale is selected adopts the model's native scale rather than clearing the selection

### AC82.9 - The directory beneath which the graph allocates an output location exists at the moment of allocation, independently of any other component having been constructed.
- Introduced: #115 (closed 2026-08-26), backfilled onto the #82 stage family
- Migrated: 2026-08-26
- Tests:
  - ✅ RT-115.1: allocating a raise creates the output directory, absent before and present after
  - ✅ RT-115.2: the same for an upscale allocation
  - ✅ RT-115.3: a stage writes to a freshly allocated location with no directory prepared by any other component
  - ✅ RT-115.4: an output directory already holding assets is not disturbed by allocation
  - ✅ RT-115.5: with the output directory absent, a raise completes through the application and its result reaches the canvas
  - ✅ RT-115.8: allocation succeeds where the directory already exists, so the guarantee is not satisfied by throwing unconditionally
- Note: **backfilled, not pre-existing.** AC82.5 constrains where a stage writes and is silent on whether the allocation is usable. `AssetGraph` minted paths beneath an `outputDirectory` it never created, and worked only because `GenerationCoordinator` created the same directory as a side effect on the ordinary launch path. The UI-test launch replaces that coordinator, the side effect disappeared, and six of the 101 GUI tests failed with *"The folder `raised-<uuid>.png` doesn't exist."*
- Note: **RT-115.5 is the only one of them that would have caught this**, and it is at GUI level for that reason. `make test` reported 533 executed and 0 failures throughout the entire broken period, because a package test constructs the graph with a directory it made itself.
- Note: creation happens in the allocation methods rather than in `init`. `AssetGraph` is public and its initializer is not throwing, so creating a directory there would have been a public API change and a mandatory architecture stop.

### AC82.10 - Where the output directory cannot be brought into existence, allocation fails at the point of allocation, naming the directory and the reason, rather than yielding a location that fails when a stage writes to it.
- Introduced: #115 (closed 2026-08-26), backfilled onto the #82 stage family
- Migrated: 2026-08-26
- Tests:
  - ✅ RT-115.6: where the directory cannot be created, allocation throws rather than returning a location
  - ✅ RT-115.7: the failure names the directory and carries the underlying reason, so two distinct impossibilities are distinguishable
- Note: AC82.9 alone admits the defect one layer along, in an implementation that guarantees existence on the happy path and stays silent when creation fails. RT-115.7 compares the two failures with the directory removed from each, so a message that names the directory and drops the reason fails.

---

## Local upscaling

### AC83.1 - Splitting an opaque image into tiles and stitching them back reproduces it exactly, including its outermost row and column.
- Introduced: #83 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-83.1: the outermost row and column of a stitched image match the source, including a channel whose source value is zero
  - ✅ RT-83.2: an interior row crossing a tile seam matches the source
  - ✅ RT-83.3: an image smaller than a single tile survives the round trip
  - ✅ RT-83.4: an image whose width is an exact multiple of the tile stride survives the round trip
  - ✅ RT-83.18: an image whose width leaves a final tile narrower than the overlap survives the round trip
  - ✅ RT-83.23: a 4x upscale of a small opaque image has no black pixel in its outermost row or column
- Note: RT-83.23 needs the x4plus model and skips without it. It is the only test here that meets
  the output a user opens; the rest stitch at 1x and hold the tiler itself.

### AC83.2 - A tile edge lying on the image boundary contributes at full weight, and an interior seam remains feathered.
- Introduced: #83 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-83.5: a pixel on the image boundary holds the value of the only tile covering it
  - ✅ RT-83.6: within an interior seam between two tiles of differing value, a pixel nearer one tile is closer to that tile's value than a pixel nearer the other

### AC83.3 - An upscale that is cancelled stops with work left undone, wherever it is doing per-unit work.
- Introduced: #83 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-83.7: a cancelled tile run leaves tiles unprocessed
  - ✅ RT-83.8: a cancelled tile run reports cancellation rather than a failure
  - ✅ RT-83.9: a run that is not cancelled processes every tile
  - ✅ RT-83.19: a stitch cancelled part way stops rather than composing every row
  - ✅ RT-83.22: a cancelled face-enhancement pass leaves faces unprocessed

### AC83.4 - Progress reported by the kit identifies its phase and carries that phase's counts as values.
- Introduced: #83 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-83.10: the tile phase carries the completed and total counts
  - ✅ RT-83.11: the face-enhancement phase carries the number of faces
  - ✅ RT-83.12: every phase the kit reports is distinguishable without reading any wording

### AC83.5 - A failure the kit raises describes what went wrong in plain language, naming what it was working on.
- Introduced: #83 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-83.13: an unreadable image produces a description naming the problem
  - ✅ RT-83.14: an absent model produces a description naming the model
  - ✅ RT-83.15: no description of a failure the kit raises contains a type name or an error code
- Note: RT-83.15 samples the cases that exist. What generalizes it is structural: each
  `errorDescription` is a `switch` with no `default`, so a case added without a description does
  not compile. Errors raised by Vision and Core ML pass through unwrapped and are outside this
  criterion, because wrapping them would bury the platform's own diagnostic.

### AC83.6 - The command-line tool's reported progress reads exactly as it did before the kit reported phases as values.
- Introduced: #83 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-83.16: each phase renders to the text the pipeline previously reported for it
  - ✅ RT-83.17: a phase carrying counts renders them in the same positions as before
- Note: the tests exercise `PipelineProgress.description`, which is the tool's progress handler
  and the only formatting of a phase in that executable. Running the built binary would be a
  build-system invocation, which `TESTING.md` keeps out of the regression pack.

### AC83.7 - An upscale's output never exceeds the supported area, whatever asked for it: a scale is reduced to the largest that fits, a custom target is reduced proportionally, and the reduction is reported while the scale selection continues to show what was asked for. A picture that cannot fit at any scale is left as it is, with the reason given. The minimum long edge required for filtering is unaffected by that ceiling.
- Introduced: #91 (closed 2026-08-25), backfilled against the #83 family
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-91.1: an output above the ceiling is reduced to the largest scale that fits
  - ✅ RT-91.2: the decision reports what was asked for and what is used, and the selection is unchanged
  - ✅ RT-91.3: an output that fits is produced unreduced
  - ✅ RT-91.4: the ceiling is area, so a wide short picture and a tall narrow one of equal area are treated alike
  - ✅ RT-91.5: the reported case, a 2000-pixel-wide picture at 4x, yields a sizing that fits
  - ✅ RT-91.6: a small picture is still raised toward the filterable minimum, unblocked by the ceiling
  - ✅ RT-91.7: a picture that fits at no scale is left alone, with the reason given
  - ✅ RT-91.8: a custom target above the ceiling is reduced proportionally, preserving its aspect
  - ✅ RT-91.9: the ceiling binds the output produced rather than the request typed
  - ✅ RT-91.10: the coordinator asks its processor for an output within the ceiling
  - ✅ RT-101.1: with a reduction in force, the status bar reports it where a user reads it
  - ✅ RT-101.2: the report names the scale used and the scale requested, and they differ --- asserted within RT-101.1's test, as the suite does elsewhere
  - ✅ RT-101.4: with no reduction and no raise, no notice is shown at all
  - ✅ UT-91.1: the message explaining a reduced upscale is clear and unobtrusive --- passed by the author, 2026-08-30
- Note: **#91 proved the decision, not the sentence.** Its ten tests are all package-level over
  `UpscaleCeiling` and assert which scale was chosen, what size resulted, and that a reduction
  occurred. None of them asserts that the user is ever *told*. #101 added the three regression tests
  above at the surface the user actually reads, so the last link --- decision to displayed sentence
  --- is covered rather than assumed.
- Note: **backfilled, not pre-existing.** #91 first cited AC83.7 as a legacy criterion on #83. It did
  not exist: #83 carries AC83.1 to AC83.6, and the resolution caps were only ever prose in
  `IMPLEMENTATION_GUIDE_v2.md` 2.5 and 3.8 plus a residual-risk note. The bound was acknowledged and
  never specified, which is how an 8000-pixel output came to sit between a warning at 4096 and a
  refusal at 8192 --- permitted, and fatal. Backfilled under the second path in `ISSUES.md`
  §"Bug-fix issues reference existing ACs".

---

## Pipeline reuse

### AC84.1 - A run whose settings match a held pipeline uses that pipeline rather than loading another.
- Introduced: #84 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-84.1: two runs with identical settings load the model once
  - ✅ RT-84.2: the second run receives the same pipeline instance as the first
  - ✅ RT-84.3: returning to a held pipeline after using another one loads neither again

### AC84.2 - A run whose settings match no held pipeline loads one for those settings.
- Introduced: #84 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-84.4: a different model name loads
  - ✅ RT-84.5: a different tile size loads
  - ✅ RT-84.6: a different face-enhancement setting loads
  - ✅ RT-84.19: an unresolved tile size and an explicit one equal to the model's default are the same key
- Note: RT-84.19 is the only test here asserting two things are the *same* key. The other three
  fail a key that is too coarse; it fails one that is too fine, which would occupy a slot with a
  duplicate and release a live entry to make room.

### AC84.3 - No more than two pipelines are held, and the least recently used is released first.
- Introduced: #84 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-84.7: a third distinct setting releases the least recently used
  - ✅ RT-84.8: after four distinct settings are used, returning to each in turn reloads all but the two most recent
  - ✅ RT-84.9: using a held pipeline makes it the most recently used, so a later release takes the other
- Note: the bound is measured through reloads rather than through a published count. The second
  slot exists for the face-enhancement toggle, which alternates between two keys holding the same
  underlying model; one slot would reload on every press.

### AC84.4 - Runs through the cache do not overlap, a run's progress reaches only its own observer, and no observer outlives its run.
- Introduced: #84 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-84.10: a second run does not begin until the first has returned
  - ✅ RT-84.11: progress reported during one run reaches that run's observer and no other
  - ✅ RT-84.12: a failure in one run leaves a later run unaffected
  - ✅ RT-84.17: a pipeline returned to the cache holds no observer from the run that used it
  - ✅ RT-84.18: two runs started concurrently for settings nothing is held for load the model once
- Note: non-overlap and single-loading are properties of two signatures being synchronous --- the
  lent body and the loader. Swift actors are reentrant, so an `async` form of either would break
  these while the tests still passed unless the tests contrived a suspension. RT-84.10 and
  RT-84.18 are what make the breakage loud.

### AC84.5 - A pipeline that failed to load is not held.
- Introduced: #84 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-84.13: a load failure propagates to the caller rather than yielding a pipeline
  - ✅ RT-84.14: a later run with the same settings loads again and succeeds

### AC84.6 - An upscale performed by the application obtains its pipeline from the cache rather than constructing one.
- Introduced: #84 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-84.15: two successive upscales through the processor call the cache's loader exactly once
  - ✅ RT-84.16: the processor's second upscale produces the same result as its first
- Note: these two need the x4plus model and skip without it. `Pipeline` is a concrete class, so a
  counting loader must still return a real one, and a criterion about the application's path
  cannot be met below that path. RT-84.15 counts *exactly* one because a processor that bypasses
  the cache calls the loader zero times, which an "at most once" assertion would accept.

**Key:** ✅ passing · ⏳ pending · ❌ failing · ~~🚫 removed~~

---

## The filter catalogue

### AC74.1 - The GUI can load prompt packs with stable identifiers, display names, categories, prompt bodies, and model compatibility metadata.
- Introduced: #74 (closed, pre-cutover)
- Migrated: 2026-08-23, cited by #85
- Tests:
  - ✅ RT-74.1: valid bundled resources load
  - ✅ RT-74.2: identifier stability, declared name, declared category, and default FAL compatibility
- Note: the mechanism changed in #85 and the criterion did not. Names and categories are read
  from each filter's frontmatter rather than split out of its filename, and RT-74.2 is rewritten
  against that while keeping its identifier. The model compatibility clause survives because
  `compatibleModelIDs` was never file metadata: the loader supplies the one MVP model, as it
  always did.
- Note: **UT-74.1 is re-offered by #138 (2026-08-30).** It passed on 86 names; the corpus is now 108
  and twenty-two more names go in front of the same judgement. RT-74.1's count moved with it. See
  AC138.1.

### AC138.1 - The bundled corpus holds the twenty-two named additions alongside the original filters, each loadable, each with a well-formed header and a non-empty body.
- Introduced: #138 (closed 2026-08-30)
- Migrated: 2026-08-30
- Tests:
  - ✅ RT-138.1: the bundled corpus contains 108 filters
  - ✅ RT-138.2: each of the twenty-two named identifiers is present and loadable
  - ✅ RT-138.3: every bundled file carries a well-formed header with id, name, category and requiresInput
  - ✅ RT-138.4: each new file's identifier matches its filename
  - ✅ RT-138.6: every bundled prompt has a non-empty body
  - ✅ RT-74.1: valid bundled resources load, count updated 86 to 108
  - ✅ UT-74.1 re-offered: all 108 names read as names rather than filenames --- passed by the author, 2026-08-30
- Note: transformed by one rule rather than hand-authored --- `id` from the filename, `category` from
  its second segment, `name` from the rest, `requiresInput` true. Twenty-two hand-written headers is
  twenty-two chances to differ from each other.
- Note: bodies are copied **verbatim**. They are the author's words and the thing being paid for at
  the provider, so no reflowing and no tidying.
- Note: **RT-138.3 carries a removal rather than an assertion, and it is worth reading before anyone
  tries again.** Two attempts were made to assert mechanically that a name "reads as a name rather
  than a filename". The first rejected any hyphen and failed on *Post-Vaporwave Muted*; the second
  compared the name against the identifier's tail and failed on *Solarpunk Civic*, which lowercases
  back to its own filename **because that is what the convention requires**. The property is not
  machine-checkable. What remains asserted is capitalization, which is. The judgement itself is
  UT-74.1's, which is where it was all along.
- Note: neither the Settings count nor the filter panel's count is written down. `SettingsView` reads
  `packs.count` and `FilterPanel` derives its own, so 86 became 108 without either being touched.

### AC138.2 - The Narrative and Institutional categories exist in the corpus and are non-empty, and the filter list groups by them alongside the categories already there.
- Introduced: #138 (closed 2026-08-30)
- Migrated: 2026-08-30
- Tests:
  - ✅ RT-138.5: the Narrative and Institutional categories are present and non-empty in the catalogue
  - ✅ RT-138.7: both are offered as chips in the filter list, and choosing Narrative narrows to its eight
  - ✅ UT-74.1 re-offered: the grouping is judged with the names --- passed by the author, 2026-08-30
- Note: **the ticket estimated Narrative at 11 of the 22 and it is 8.** The final split is Narrative
  8, Institutional 4, Media 4, Material 3, and one each into Design, Print and Zeitgeist. The
  estimate was made by reading filenames before the transformation ran; the count above is from the
  headers as written. Recorded rather than quietly corrected because the ticket's reasoning about
  the primary surface was sized against the wrong number.
- Note: **RT-138.7 closes a gap in this criterion's own test audit.** The criterion says the filter
  list *groups by* the new categories, and the only test cited for it asserted they exist in the
  *catalogue*, which is not the list. It happens that `FilterPanel.categories` derives its chips from
  the loaded filters, so it passes without an application change --- but the criterion was untested
  either way, and a later change that hardcoded the chip list would have satisfied everything #138
  shipped with.
- Note: **growing the corpus broke two GUI tests the audit never looked at.** RT-87.10 and RT-87.36
  hardcoded 86. The count is asserted in three places across the suite and derived in none; the test
  audit examined `PromptPackTests` and stopped there. Corrected to 108.
- Note: adding categories changes how the *existing* filters are found, not only the new ones. Guide
  2.3 calls the filter list the primary surface, and its category list in guide 2.2 had also been
  missing `photo` before this ticket --- corrected there at guide 3.37.

### AC74.2 - The prompt-pack loader rejects invalid or incomplete resources with actionable diagnostics and no secret leakage.
- Introduced: #74 (closed, pre-cutover)
- Migrated: 2026-08-23, extended by #85
- Tests:
  - ✅ RT-74.3: an unsupported model reference is rejected
  - ✅ RT-74.4: a diagnostic names the resource and carries no prompt body
  - ✅ RT-85.20: a corpus with two filters declaring the same identifier is reported, naming it
  - ✅ RT-85.21: the bundled corpus contains no duplicate identifier
- Note: duplicate rejection is not new. What changed in #85 is why duplicates are possible at
  all --- they were prevented by the filesystem, one identifier per filename, and frontmatter
  removes that guarantee at the moment 86 files are hand-edited. `pack(id:)` uses
  `first(where:)`, so a duplicate would make one filter permanently unreachable with no error
  and no way to notice but by counting.

### AC85.1 - A filter's identity, name and category come from its own frontmatter rather than from its filename.
- Introduced: #85 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-85.1: a filter's name and category are those its frontmatter declares
  - ✅ RT-85.2: a filter whose frontmatter disagrees with its filename presents what the frontmatter says
  - ✅ RT-85.3: every filter in the bundled corpus loads with a name and category
- Note: RT-85.2 is what separates this from a loader that reads frontmatter *and* falls back to
  the filename. Only disagreement can tell them apart.

### AC85.2 - Loading a corpus containing a file that cannot supply valid metadata fails, naming the file and the reason, and yields no filters.
- Introduced: #85 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-85.4: a file with no frontmatter is reported, naming the file
  - ✅ RT-85.5: a file whose frontmatter is malformed, or carries a field of the wrong type, is reported, naming the file
  - ✅ RT-85.6: a file whose frontmatter omits a required field is reported, naming the field
  - ✅ RT-85.7: a file whose body is empty after its frontmatter is reported
  - ✅ RT-85.26: a file whose frontmatter carries a required field as an empty or whitespace-only value is reported, naming the field
- Note: the failure is of the corpus rather than of the file. A catalogue quietly short by one is
  not something anybody counts, whereas a build that will not start is noticed at once. RT-85.26
  is the case a decoder cannot catch: `"name": ""` decodes into a `String` perfectly well and
  ships a blank row in the list. Its assertions match the *quoted* field name, because
  "invalid" contains "id".

### AC85.3 - The text a filter sends is its body verbatim, with the frontmatter no part of it, and no filter in the corpus carries its filename or a heading standing in for one.
- Introduced: #85 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-85.8: a loaded filter's text contains no frontmatter delimiter
  - ✅ RT-85.9: no bundled filter's text begins with a markdown heading
  - ✅ RT-85.10: no filter's text contains its resource name
  - ✅ RT-85.11: the three filters that carried a filename heading load without it
  - ✅ RT-85.24: a filter whose body contains a horizontal rule loads with that body intact
  - ✅ RT-85.32: a filter whose body begins with a markdown heading loads with that heading intact
- Note: this closes D4, where three of 86 filters sent their own filename to the provider as
  prompt text. RT-85.32 is what makes the corpus the only place the fix can live: a loader that
  discarded a leading `#` line would satisfy RT-85.9 to RT-85.11 with the three files untouched,
  and would silently truncate the first filter that legitimately opened with a heading. RT-85.24
  covers the other direction, `---` being a horizontal rule as well as a delimiter.

### AC85.4 - Choosing a filter yields its text for editing and sends nothing, replacing whatever the field held.
- Introduced: #85 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-85.12: choosing a filter yields that filter's text
  - ✅ RT-85.13: choosing a filter issues no request
  - ✅ RT-85.14: choosing a second filter replaces the text rather than appending to it
  - ✅ RT-85.25: choosing the filter already chosen yields its text afresh, discarding any edit
  - ✅ RT-85.29: choosing a filter replaces hand-written text entered with no filter chosen
- Note: RT-85.13 is the point of the two-step flow --- selecting must be free, so a user can read
  eighty-six filters at no cost. RT-85.25 is how a user reverts an edit they have decided
  against; without it the only way back to the built-in wording is to choose something else and
  return, which works by accident rather than by design.

### AC85.5 - What a filter sends is the text as it stands when it is applied, edited or not.
- Introduced: #85 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-85.15: applying an unedited filter sends its body
  - ✅ RT-85.16: applying an edited filter sends the edited text
  - ✅ RT-85.17: an edit is discarded when another filter is chosen, so the built-in filter is unchanged
- Note: supersedes AC74.3. The composition it specified --- pack body joined to user text at send
  time --- is what the two-step flow removes; the half that survives, *without mutating the
  bundled resource*, is this criterion's third condition, and RT-74.5 and RT-74.6 are rewritten
  into RT-85.17 rather than left calling a `PromptComposer` that no longer exists.

### AC85.6 - A filter identifier stored by a previous version still resolves to its filter.
- Introduced: #85 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-85.18: an identifier in the form the previous version stored resolves to a filter
  - ✅ RT-85.19: every identifier in the bundled corpus matches the resource name the previous version derived
- Note: exists because of AC73.2, which requires the prompt-pack selection to persist outside
  secret storage. A prettier identifier on one file among 86 would make that saved default
  resolve to nothing, with no error and no message.

### AC85.8 - What is applied is the text as it stands, whether it came from a filter or was written by hand, and applying with no text to send is refused.
- Introduced: #85 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-85.22: applying with text entered and no filter chosen sends that text
  - ✅ RT-85.23: applying with neither text nor a filter chosen issues no request, and the apply action is unavailable
  - ✅ RT-85.27: applying with a filter chosen and its text cleared issues no request, and the apply action is unavailable
  - ✅ RT-85.28: applying with text consisting only of whitespace issues no request, and the apply action is unavailable
- Note: supersedes AC74.4's half about editing controls. The refusal belongs to the text rather
  than to the pair of (text, filter): a filter sitting chosen beside an empty box is still
  nothing to send, and an empty prompt reaches a paid edit endpoint and returns something
  arbitrary. It lives in the model that builds the request, so the disabled button and the send
  path cannot disagree.

### AC85.9 - A corpus that fails to load leaves the application with no filters and with the reason available, and leaves local upscaling unaffected.
- Introduced: #85 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-85.30: after a corpus fails to load, the filter list is empty and the failure's reason is available rather than discarded
  - ✅ RT-85.31: after a corpus fails to load, the upscale action remains available and its settings are unaffected
- Note: section 2.8 of `IMPLEMENTATION_GUIDE_v2.md` rules that when filters are unavailable,
  local upscaling works fully. A corpus that will not load is that condition reached by another
  route, and the route should not change what the user gets. The handling lives in
  `GenerationSettingsState` rather than in the app's entry point so that it is the same code the
  tests drive.

### AC85.7 - removed before sign-off
- 🚫 Removed: it duplicated AC74.2. RT-85.20 and RT-85.21 extend that criterion's coverage
  instead. The identifier is not reused.

---

## Settings and credentials

### AC146.1 - A credential row keeps its arrangement whatever is typed into its field, and the rows below it do not move.
- Introduced: #146 (closed 2026-08-31)
- Migrated: 2026-08-31
- Tests:
  - ✅ RT-146.1, RT-146.2, RT-146.3: every control in the credentials section keeps its position while a long key is typed
  - ✅ RT-146.4: both credential rows use the same arrangement as each other
  - ⏳ UT-73.2 re-offered: type a long key into each field and judge that nothing jumps
- Note: **two causes, one level apart.** The row was a `LabeledContent`, which on macOS puts the label
  beside the content until the content's ideal width will not fit and then reflows it above --- and a
  `TextField`'s ideal width follows its text, so a long FAL key changed the arrangement mid-keystroke.
  Underneath that, `minWidth` alone left the field itself growing with the key and pushing the save,
  remove and status controls along the row.
- Note: **#110 already fought this and won half of it.** Its note on the status slot records that
  swapping a spinner for a badge *"made `LabeledContent` renegotiate the form's label column --- and
  the whole form moved under the user's typing."* It pinned the slot and left the field free to do
  the same thing by another route, which is why RT-146.1-3 measures **every** control in the section
  rather than trusting one proxy.
- Note: label-above is what a populated row already looked like, so nothing moves when a key is
  pasted, and it gives the field the full width --- which suits a credential sixty characters long.
- Note: diagnosed from the author's two screenshots, which show the same row in both arrangements.
- Note: **UT-73.2 is re-offered.** He passed it on 2026-08-30, before trying a long key in the admin
  field.

### AC73.5 - Users can see separate controls for generation key, account/admin key, account state, defaults, and prompt packs.
- Introduced: #73 (closed, pre-cutover)
- Migrated: 2026-08-24, cited by #88
- Tests:
  - ✅ RT-73.8: the Settings controls are present, with their enabled and disabled states
  - ✅ UT-73.2: the Settings layout follows `docs/v2/WIREFRAMES.md` closely enough for discovery refinement --- passed by the author, 2026-08-30. **Descriptor backfilled the same day**: this line had carried only "pending human resolution in delivery master #79" since #88, so the criterion recorded that a judgement was outstanding without recording what was to be judged. Recovered from #73's own body.
- Note: the criterion says *which* controls exist. Whether each can be reached is AC73.6, backfilled
  beside it. RT-73.8's pricing and account assertions were removed by #88 with the surface they
  covered, and its navigation by `modeSettings` is rewritten by #87 when Settings becomes a scene
  rather than a mode.

### AC73.6 - Every interactive control in Settings is individually addressable by assistive technology, rather than being absorbed into the row that contains it.
- Introduced: #88 (backfilled onto #73's feature, 2026-08-24)
- Tests:
  - ✅ RT-88.1: the account refresh control is reachable in the accessibility tree
  - ✅ RT-88.2: the account summary is reachable in the accessibility tree
  - ✅ RT-88.3: each control AC73.5 names is reachable by its own identifier
- Note: backfilled rather than stretched from AC73.5. A sighted user could see the refresh control;
  it was drawn, on screen, and worked with a mouse. What it was not was addressable, so VoiceOver
  could not reach it. An accessibility identifier on an `HStack` makes SwiftUI treat the stack as one
  element and absorb its children. Isolated by comparison with the pricing row directly above, which
  carries no container identifier and whose button was always reachable. RT-88.3 states the rule
  rather than the two instances, because the same mistake elsewhere in the panel would leave RT-88.1
  and RT-88.2 passing.

### AC95.1 - Each credential row names its field once, and that name is identifiable rather than merely visible.
- Introduced: #95 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-95.1: exactly one element carries the generation key row's label, and the field contributes no second one
  - ✅ RT-95.2: the same for the account key row
- Note: the name carries an identifier of its own. `.labelsHidden()` hides a label *visually* while
  the element may keep it as its accessibility label, so a test counting matches in the tree could
  return the same number before and after the fix and pass against the unfixed view.

### AC95.2 - A credential is legible while it is being entered and after it has been saved, so a pasted key can be checked by eye.
- Introduced: #95 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-95.3: a typed key is readable in the field
  - ✅ RT-95.4: a saved key is readable when Settings is reopened
- Note: a FAL key is a bearer credential, not a password recited from memory, and masking it prevents
  the one check anybody performs on a pasted key. Where it is *stored* is unchanged --- the
  Keychain --- and so is the rule that it travels only in a request header. RT-95.3 asserts that no
  secure field exists rather than that this element is a text field, so the unfixed view fails it for
  the right reason.

### AC95.3 - The generation key reads as working only after the provider has accepted it, and a stored but unverified key is distinguishable from both a verified one and an absent one. The account key reads as stored or absent and carries no verification state. Checking a key costs nothing, and editing one returns it to unverified.
- Introduced: #95 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-95.5: a stored, unchecked generation key reads as stored rather than as working
  - ✅ RT-95.6: a generation key the provider accepts reads as working
  - ✅ RT-95.7: a generation key the provider rejects reads as rejected, with the provider's reason
  - ✅ RT-95.8: an unreachable provider leaves the key as stored rather than reporting it rejected
  - ✅ RT-95.14: the account key row shows no verification state
  - ✅ RT-95.16: verification issues no generation request
  - ✅ RT-95.17: editing a verified key returns it to unverified until it is saved and checked again
  - ✅ RT-109.1: a key typed into the account row and not saved reads as not configured
  - ✅ RT-109.2: pressing the account row's save changes what the row reports, in the same interaction
  - ✅ RT-109.3: editing a saved account key returns the row to not configured until it is saved again
  - ✅ RT-109.4: a store that throws leaves the account row saying not configured
  - ✅ RT-109.5: an account key already in the Keychain reads as stored on launch, with no press
  - ✅ RT-109.6: removing the account key returns the row to not configured
  - ✅ RT-109.7: saving whitespace over a stored account key removes it and reads as not configured
  - ✅ RT-109.9: a saved account key can still be removed while it is being edited
- Note: #109 found the account half of this criterion violated. *"The account key reads as stored or
  absent"* was implemented as `!accountAdministrationKey.isEmpty` --- the **text field**, not the
  Keychain --- so the badge flipped to "stored" on the first keystroke and the save press had no
  state change left to make. Beside a generation key that answers a press with a green tick, a row
  that answers with nothing reads as a broken button, and it was reported as one. The state now
  holds the account key as it was last stored and compares the field against it.
- Note: **the word "stored" means something slightly different in the two rows, and deliberately
  so.** For the generation key it means "typed but unverified", which RT-95.17 requires. For the
  account key it means "matches the Keychain". The generation row's press has its own answer to
  deliver, the provider's verdict, so its badge need not report the store; the account row's press
  has no other answer, so its badge must report the only thing the press changes. Recorded so nobody
  later tidies the two into agreement and breaks RT-95.17.
- Note: **the remove control reads a different question from the badge.** The badge asks whether the
  field matches the Keychain; remove asks whether anything is in the Keychain. Left on the badge, it
  would have disabled itself the moment a saved key was edited, so a user correcting a typo could no
  longer delete the key they were correcting. RT-109.9 is the guard.
- Note: RT-109.4, RT-109.5 and RT-109.7 are unit tests rather than GUI ones, and that is a cost paid
  deliberately. There is no honest way to make the Keychain refuse from XCUITest --- adding a
  `keychain` mode to `SUPERSCALE_UI_TEST_FAIL` would have the shipping app carry a failure injector
  to reach one assertion reachable in-process --- and seeding a key "already stored at launch" would
  mean a GUI test writing the author's own login Keychain, the wall that also retired RT-111.5.
- Note: **RT-109.3 and RT-109.5 are the two that matter.** Flipping a flag in the save button's
  action satisfies RT-109.2 and fails both: returning to not-configured on an *edit* needs the field
  compared against what was stored, and a flag resets on launch where a Keychain read does not.
- Note: the badge read from whether a key was *stored*, so a typo saved and showed a green tick.
  RT-95.8 is the one that matters most: reporting an unreachable provider as a rejection has the
  user delete a working key. RT-95.16 checks the request's own properties --- a GET, no body, one
  call, no model name and no queue path in the URL --- because the client most obviously to hand
  generates images at 2c each, and verifying by generating would charge a user for checking whether
  they typed their key correctly.
- Note: a verdict belongs to the key it was given, so the state holds the checked key alongside the
  answer and derives the badge from both. Resetting on edit would need an ordering between a
  keystroke and a reply, and there is none to be had.

### AC95.4 - An output folder is always configured, defaulting to the user's Downloads folder until they choose another.
- Introduced: #95 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-95.9: with no stored preference, the output folder is the user's Downloads folder
  - ✅ RT-95.10: a chosen folder survives a restart
  - ✅ RT-95.11: a stored folder that no longer exists falls back to Downloads rather than to nothing
- Note: resolved through `FileManager.urls(for:in:)` rather than built from the home directory, so it
  is correct on a machine where Downloads has been moved. RT-95.10 and RT-95.11 use a run-unique
  `UserDefaults(suiteName:)`, removed in teardown, so no test rewrites the author's own preference.

### AC95.6 - A credential row's controls occupy the same space whatever the row's state, so entering text, saving, checking and the result of a check change what the row says and never what it measures.
- Introduced: #110 (closed 2026-08-27), backfilled onto the #95 family
- Migrated: 2026-08-27
- Tests:
  - ✅ RT-110.1: the row's frame is unchanged between empty and filled
  - ✅ RT-110.2: the row's frame is unchanged between the checking state and each settled state
  - ✅ RT-110.3: the form's other rows do not move while one row changes state
- Note: **backfilled, not cited.** The originating ticket quoted AC95.1 as *"the whole scene reads
  cleanly"*; AC95.1 says *"each credential row names its field once, and that name is identifiable
  rather than merely visible"*, which is about naming. Nothing in the #95 family covered layout
  stability, so this is path 2 of `ISSUES.md` §"Bug-fix issues reference existing ACs".
- Note: the mechanism was a `ProgressView` and a status badge swapped directly into the row's
  `HStack`. Their intrinsic widths differ, so each state change resized the stack, then the
  `TextField` beside it, then the form's label column through `LabeledContent`. A fixed-width slot
  holds both.
- Note: **RT-110.3 is the one closest to the complaint.** *"The layout of the whole form jumps
  about"* is about the rows the user is not typing into. It also catches the shortest wrong fix,
  which pins the field's width and leaves the trailing content free to push the row around.

### AC95.7 - The account key row states in the scene that its key is held for later use and is not checked with the provider, so a row that never turns green is explained rather than merely quiet.
- Introduced: #109 (closed 2026-08-27), backfilled onto the #95 family
- Migrated: 2026-08-27
- Tests:
  - ✅ RT-109.8: the account row says, in readable text, that its key is not verified
- Note: **backfilled.** The state half of #109 is a straight AC95.3 violation and is recorded there.
  Nothing in the family covered a control explaining its own limits, so this is path 2 of
  `ISSUES.md` §"Bug-fix issues reference existing ACs".
- Note: **"in the scene", not "on hover", is the whole content of the criterion.** The ticket offered
  the sentence as *"one short help string"*, and `.help()` in this file renders as a tooltip:
  invisible until hovered, invisible to anyone who does not know to hover, and unreadable from
  XCUITest, so RT-109.8 could not have asserted it. The author's wording is kept exactly; only the
  placement is changed, and that change was flagged on the ticket rather than assumed.
- Note: the sentence sits in the section rather than as a parameter on `credentialRow`. A note
  belonging to one row is not a property of the shared component that draws both, and threading it
  through as an optional would have put a second concern into a builder #110 had just narrowed.

### AC95.5 - Settings offers no control that operates a feature the MVP excludes. Storing a credential for later is not operating anything, so the account key row remains.
- Introduced: #95 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-95.12: no cost-confirmation control is present
  - ✅ RT-95.13: no pricing or account-balance control is present
  - ✅ RT-95.15: the account key row is present and can be saved and cleared
- Note: the line is between *storing* a credential for later and *operating* a paused feature. A
  Check Pricing button performs an operation the MVP has removed; a key field holds a value for a
  version that will. Asserted by identifier *and* by the visible words, so a control renamed rather
  than removed does not pass.
- Note: `costThreshold` and its stored preference go with the control, and the retired defaults key
  is removed on the next save rather than left for a later reader to prove is dead.


**Key:** ✅ passing · ⏳ pending · ❌ failing · ~~🚫 removed~~

---

## The single workspace

### AC87.1 - The application presents one workspace, with no navigation between upscaling and filtering as peer surfaces within the window.
- Introduced: #87 (closed 2026-08-24)
- Migrated: 2026-08-24
- Tests:
  - ✅ RT-87.1: the running application shows no mode list
  - ✅ RT-87.2: the workspace shows the canvas and the filter panel together
  - ✅ RT-87.3: no navigable surface named Generate, History or Settings exists in the window
- Note: `AppMode` and `AppNavigation` are deleted rather than reduced to a single case. RT-70.4 and
  RT-70.5, which exercised them, are marked removed with their identifiers retired.

### AC87.2 - The working image occupies the canvas whether or not an upscale is selected, and filter controls occupy a panel beside it rather than above it.
- Introduced: #87 (closed 2026-08-24)
- Migrated: 2026-08-24
- Tests:
  - ✅ RT-87.4: at the declared minimum window size, the canvas occupies at least 60% of the width
  - ✅ RT-87.5: the filter panel and the canvas are visible at the same time
  - ✅ RT-87.35: an image imported with no scale selected occupies the canvas
- Note: RT-87.35 was added from a defect found in use. With the scale off there is no upscaled
  output, by AC82.6, and the canvas drew only the upscaled result, so an image imported in that
  state loaded, set the base, and drew nothing. Filtering without upscaling is a use in its own
  right. RT-87.4 asserts at the minimum window size because any larger window makes dominance
  easier.

### AC87.3 - Settings opens as a macOS Settings scene rather than replacing the workspace.
- Introduced: #87 (closed 2026-08-24)
- Migrated: 2026-08-24
- Tests:
  - ✅ RT-87.6: the Settings scene opens and the workspace remains behind it
  - ✅ RT-87.7: the workspace contains no Settings surface

### AC87.4 - Every category the catalogue declares narrows the filter list in one action, widens it again in one, and is reachable alongside a search that cuts across categories; a catalogue that fails to load leaves the panel stating why.
- Introduced: #87 (closed 2026-08-24)
- Migrated: 2026-08-24
- Tests:
  - ✅ RT-87.8: every category the catalogue declares is offered as a one-click narrowing
  - ✅ RT-87.9: choosing a category narrows the list to the filters that declare it
  - ✅ RT-87.36: choosing the active category again clears the narrowing
  - ✅ RT-87.37: search reaches across categories
  - ✅ RT-87.10: with no category chosen, every filter the catalogue loads is offered
  - ✅ RT-87.31: when the catalogue fails to load, the panel is given the reason to state
- Note: reworded after the first implementation was rejected on sight. It read "every bundled
  filter is reachable within its category", which section headings satisfy: 86 filters in one
  scroll with headings between them is grouping rather than choosing. A filter bar rather than a
  drill-down, because the requirement is flexibility with few clicks rather than a fixed number of
  steps.
- Note: **"a search that cuts across categories" was true of this criterion and false of the
  application for three raisings.** `visibleFilters` anded the chip and the query, so with Lighting
  chosen a search reached 4 filters of 108. **RT-87.37 asserted the right rule and could not fail**:
  it ran from a state with no chip active, so "reaches across categories" was never tested against a
  category. Widened by #141 to start from a chipped state, where its `linocut` assertion fails
  against the old code. See AC141.1.

### AC141.1 - Entering the search field clears any active category, so a search covers the whole corpus and no chip is ever lit while not narrowing.
- Introduced: #141 (closed 2026-08-31)
- Migrated: 2026-08-31
- Tests:
  - ✅ RT-141.1: with a category chosen, focusing the search field clears the chip
  - ✅ RT-141.2: a search then finds a filter from a different category
  - ✅ RT-141.3: the count returns to the whole corpus when the chip clears
  - ✅ RT-141.4: focusing with no category chosen changes nothing
  - ✅ RT-141.6: no chip claims to narrow while the whole corpus is listed
  - ✅ RT-141.7: text already typed survives the chip clearing
  - ✅ RT-87.37 widened: search reaches across categories **from a chipped starting state**
  - ⏳ UT-141.1: choose a category, click the search box, and judge that searching now reaches everything
- Note: **the author's third raising.** The intent had been written down and never implemented ---
  `FilterPanel`'s own doc comment already claimed *"search cuts across categories, so nothing is
  hidden behind navigation."*
- Note: **on focus, not on the first keystroke.** He wrote *"clicking in the search box"*, and
  clearing on a keystroke would leave one keystroke's worth of results filtered by a chip that is
  about to disappear.
- Note: **the chip is cleared, not ignored.** Making the search ignore an active chip is one line and
  satisfies almost every test here, but leaves a chip lit while it narrows nothing --- a control that
  lies, which is worse than the defect. **RT-141.6 blocks that route**, and writing it required
  making the chip's state addressable: it had been expressed as colour and nothing else, so it
  reached neither VoiceOver nor a test. The same gap #95's credential badge had.

### AC87.5 - Choosing a filter fills the editable prompt area and issues no request; applying sends that text.
- Introduced: #87 (closed 2026-08-24)
- Migrated: 2026-08-24
- Tests:
  - ✅ RT-87.11: choosing a filter fills the prompt area
  - ✅ RT-87.12: choosing a filter issues no request
  - ✅ RT-87.13: applying issues one request carrying the prompt area's text

### AC87.6 - Applying a filter uses the working image at its own resolution as the single reference, never the upscaled rendering of it, and no separate reference wells exist.
- Introduced: #87 (closed 2026-08-24)
- Migrated: 2026-08-24
- Tests:
  - ✅ RT-87.14: the reference is the image as imported rather than its upscaled rendering
  - ✅ RT-87.15: the workspace presents no reference well
  - ✅ RT-87.24: with an upscale rendered, an applied filter still carries the unupscaled image
- Note: supersedes AC75.1's "up to three reference image wells". The canvas shows the upscaled
  rendering by default, so sending what is on screen is the obvious implementation and would
  breach AC79.2 and invariant I1.

### AC87.7 - The cost shown beside Apply is the documented flat rate, obtained without contacting the provider.
- Introduced: #87 (closed 2026-08-24)
- Migrated: 2026-08-24
- Tests:
  - ✅ RT-87.16: the cost beside Apply reads the documented rate
  - ✅ RT-87.17: the workspace issues no pricing request

### AC87.8 - An upscale honours the configured default upscale model however the image arrived, and falls back to automatic selection when that model no longer exists.
- Introduced: #87 (closed 2026-08-24)
- Migrated: 2026-08-24
- Tests:
  - ✅ RT-87.18: a dropped image upscales with the configured default model
  - ✅ RT-87.19: an image from a filter result upscales with the same model
  - ✅ RT-87.20: a model chosen in the toolbar overrides the default
  - ✅ RT-87.34: a stored default naming no real model falls back to automatic selection
- Note: closes D8. Both arrival paths resolve through one function, with the arrival as a
  parameter so a future divergence has to be written deliberately rather than left out.

### AC87.9 - Prior generation sessions are reachable from the File menu, most recent first and bounded to the ten most recent, and no History surface exists.
- Introduced: #87 (closed 2026-08-24)
- Migrated: 2026-08-24
- Tests:
  - ✅ RT-87.21: recent sessions are listed most recent first
  - ✅ RT-87.22: the File menu offers the seeded session
  - ✅ RT-87.23: the workspace contains no History surface
  - ✅ RT-87.32: at most ten sessions are listed
  - ✅ RT-87.33: a session whose image is missing is reported rather than failing silently
- Note: supersedes #77's History surface criteria. Session storage is untouched; what goes is the
  place it was browsed. RT-77.5 and RT-77.6 are marked removed with their identifiers retired.

### AC87.10 - With no working image, the canvas offers the import target and applying is unavailable.
- Introduced: #87 (closed 2026-08-24)
- Migrated: 2026-08-24
- Tests:
  - ✅ RT-87.25: on launch with no image, the canvas shows the import target
  - ✅ RT-87.26: with no working image, applying is unavailable however the prompt area is filled

### AC87.11 - Without a generation key, filters are unavailable with a route to Settings, and local upscaling is unaffected.
- Introduced: #87 (closed 2026-08-24)
- Migrated: 2026-08-24
- Tests:
  - ✅ RT-87.27: with no key, applying is unavailable and the panel offers a route to Settings
  - ✅ RT-87.28: with no key, an image still imports and upscales
- Note: section 2.8 of the implementation guide requires local upscaling to work fully when
  filters are unavailable.

### AC87.12 - An application in flight can be cancelled, and cancelling leaves the working image as it was.
- Introduced: #87 (closed 2026-08-24)
- Migrated: 2026-08-24
- Tests:
  - ✅ RT-87.29: an application in flight offers a cancel action
  - ✅ RT-87.30: cancelling leaves the working image unchanged and produces no candidate

---

## Provider request construction

### AC97.1 - An edit request carries a sizing parameter only where its endpoint accepts one, and grok's does not.
- Introduced: #97 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-97.1: an edit request's body contains no sizing field
  - ✅ RT-97.2: a text-to-image request's body does carry one
  - ✅ RT-97.3: the endpoint chosen for a request with a reference is the edit endpoint
- Note: every request carried `aspect_ratio`, including the edit requests `IMPLEMENTATION_GUIDE_v2.md`
  3.6 says reject it. A rejected parameter does not produce the sizing asked for; it produces
  whatever the model does by default, which is one candidate explanation for filtered results
  returning square. Recorded as a hypothesis rather than an established cause: confirming it
  directly costs a paid call.

### AC97.2 - One model is selectable, and the handlers are a table of values, so a further model is an entry rather than a branch.
- Introduced: #97 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-97.4: the only model offered for selection is `xai/grok-imagine-image`
  - ✅ RT-97.5: a handler added to the table produces correct requests with no change to the builder
- Note: the handler was a `switch`, so "adding a model is a data change" was untrue and RT-97.5 was
  unwritable --- a test cannot add a `case` at runtime. The `fal-ai/flux-pro/kontext` handler is
  retained and unselectable, per guide 3.6's "knowledge held for later".

### AC97.3 - A reference is sent in the form its field expects: a plural field receives a list, a singular field receives one value. Extra references beyond what the handler accepts are dropped with a warning naming what went.
- Introduced: #97 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-97.6: a plural field receives a list, even for one reference
  - ✅ RT-97.7: more references than the handler accepts produce a warning naming the counts
  - ✅ RT-97.8: no reference at all produces no reference field
  - ✅ RT-97.12: a singular field receives one value rather than a list
- Note: a field's shape is its own property rather than a consequence of the reference limit. The two
  coincide for the handlers that exist and are different questions --- a family accepting `image_urls`
  while using only the first would have a plural field and a limit of one.

### AC97.4 - Where the caller supplies an aspect ratio and the model supports only a fixed set, the request carries the nearest supported one, and the caller can tell which was used.
- Introduced: #97 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-97.9: an unsupported ratio snaps to the nearest supported
  - ✅ RT-97.10: a supported ratio passes through unchanged
  - ✅ RT-97.11: a snapped ratio produces a warning naming both the requested ratio and the one sent
- Note: nearest by the ratio's value rather than by where it sorts, so 2:3 finds 9:16. The supported
  set is `FAL_REQUEST_REFERENCE.md`'s: 9:16, 1:1, 4:3, 16:9.

**Key:** ✅ passing · ⏳ pending · ❌ failing · ~~🚫 removed~~

## The workspace's state


### AC89.1 - Applying a filter reads the base asset and replaces the candidate, so filter results chain only when locked.
- Introduced: #89 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-89.1: a second filter applied without an intervening lock reads the base
  - ✅ RT-89.2: a second filter applied after a lock reads the locked result
  - ✅ RT-89.3: after two applications without a lock, toggling to the base shows the imported image

### AC89.2 - Lock is the only action that moves the base, and it promotes the candidate at its own resolution, never the upscaled rendering of it.
- Introduced: #89 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-89.4: locking promotes the candidate and the base changes
  - ✅ RT-89.5: applying a filter leaves the base unchanged
  - ✅ RT-89.6: an upscale leaves the base unchanged
  - ✅ RT-89.7: locking with no candidate leaves the base unchanged and reports why
  - ✅ RT-89.23: with an upscale rendered and shown, locking promotes the candidate at its own resolution rather than the rendering
- Note: RT-89.23 is the condition an implementation gets wrong by accident. With the scale on, what
  the user is looking at *is* the upscaled rendering, so "lock what I see" is the natural code and it
  stores a derivation as the base. The graph refuses an upscaled asset here, so the rule is enforced
  rather than remembered.

### AC89.3 - Every locked iteration remains reachable from the current base, each carrying the provenance of how it was produced and saveable at the current scale selection.
- Introduced: #89 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-89.8: after two locks, both iterations are reachable in order
  - ✅ RT-89.9: a locked iteration produced by a filter carries that filter's identity
  - ✅ RT-89.10: an iteration reached by scrolling back is saveable at the current scale selection
  - ✅ RT-111.1: with two locked iterations and one open, the chain remains present and whole and the others remain reachable
  - ✅ RT-111.2: navigating from one open iteration directly to another shows the second
  - ✅ RT-111.3: a chain of exactly one survives being opened
  - ✅ RT-111.6: from an open iteration, one action returns to the newest, and it is that asset
  - ✅ RT-121.7: selecting an earlier iteration leaves the later ones reachable
  - ✅ RT-121.9: returning to the newest iteration restores it as the working point
- Note: ~~🚫 **reachability is from the tip, not from the base, as of #121**~~ --- superseded by
  #132. That note was right about the diagnosis and wrong about the remedy: a chain derived from the
  *tip* lost everything forward of a selection the moment the user locked, because lock advanced the
  tip. **The chain was derived from a single pointer twice, and both times a backwards move
  destroyed work the user had paid the provider for.**
- Note: **reachability is from the whole chain, held explicitly, as of #132.** It is the record of
  what has been made, in the order it was made, and branching from an earlier point *adds* to it.
  The lineage still exists on each asset's `parentID` and still governs I2, I3, AC89.9 and the
  session filter cache; it is simply not what the strip is read from.
- Note: **the #121 version was a decision taken without asking, and that was the error under the
  error.** The commit called truncating the chain *"the honest outcome"*. It destroys paid work, and
  `MAIN.md` §1 reserves that judgement to the author, who reported it as *"completely unreliable"*.
  Recorded here because the process failure is the more useful lesson than the pointer.
  - ✅ RT-132.1: locking after a selection keeps every earlier lock, asserted by identifier
  - ✅ RT-132.2: the newly locked result joins the chain and is the base
  - ✅ RT-132.3: the lineage still records the restored base as the new iteration's parent
  - ✅ RT-132.4: importing a different picture still empties the chain
  - ✅ RT-132.5: returning to the newest reaches the most recently locked result
  - ✅ UT-132.1: every locked iteration stays reachable, and navigating and saving them works --- passed by the author in the round of 2026-08-29, recorded on master #133 as *"Lock image navigation, saving, PASS"*
- Note: **RT-89.8's expected count moved from two to three, and RT-111.6's expected report from "The
  base" to "A filter result".** Both are this criterion changing rather than tests weakening. The
  newest lock was previously excluded from the chain because it was where the user stood; it is now
  somewhere they can go, so it is listed, it is selectable, and returning to it is the same
  operation as selecting any other entry.
  - ✅ RT-111.7: the chain reports which entry is open as a value, asserted across two entries
  - ✅ RT-111.8: the chain persists with the scale both cleared and selected
  - ~~🚫 RT-111.5: an entry whose file has gone stays in the chain and reports itself unavailable~~
- Note: saving is *at the current scale selection* rather than at whatever resolution the iteration
  happens to be, because guide 2.6 rules that an earlier iteration re-derives its upscale on demand.
- Note: **#111 found that reachable once was not reachable.** Opening an iteration called `display`,
  which set `viewModel.inputURL`, which fired the observer calling `adoptImportedImage`, whose guard
  compared against the *workspace's* displayed asset - still the base or candidate, never the
  iteration - so it passed and `importImage` ran. AC89.8 then started a new chain and the strip's own
  condition removed it. The view now records what it last asked to show, so its own request cannot
  read as an import.
- Note: RT-111.5 is retired, identifier not reused. It required making an iteration's file disappear,
  and the XCUITest runner's sandbox cannot remove a file the application wrote - `NSCocoaErrorDomain
  513` on a file whose own permissions are ordinary. RT-81.20 and RT-81.32 hold the behaviour at
  package level; what is lost is confirmation through the application.

### AC89.4 - An upscaled asset is never the input to a filter or to a further upscale, enforced by the graph rather than by the view.
- Introduced: #89 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-89.11: a filter applied while an upscaled asset exists reads the base
  - ✅ RT-89.12: submitting an upscaled reference as a stage input reports the rule it breaks
- Note: RT-89.12 is what makes this the graph's job rather than the view's. The view can only avoid
  the mistake; the graph can refuse it. `AssetReference`'s initializer is not public, so a caller
  outside the package cannot invent one for a file it happens to know about.
- Note: the harm the rule prevents is exceeding the filter model's working resolution, not upscaling
  as such --- which is why `raisedToMinimum` is a separate role that *is* valid filter input.

### AC89.5 - The canvas shows the base or the candidate as the user chooses, the choice changes nothing that is stored, and a newly produced candidate is shown whichever was chosen before it.
- Introduced: #89 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-89.13: with a candidate present, the toggle shows the base
  - ✅ RT-89.14: toggling back shows the candidate
  - ✅ RT-89.15: toggling leaves the graph unchanged
  - ✅ RT-89.27: with no candidate, the filter toggle is unavailable
  - ✅ RT-89.28: applying while showing the base shows the new candidate
- Note: RT-89.28 exists because applying while showing the base would otherwise look as though
  nothing had happened.

### AC89.6 - The scale selection and the filter toggle are independent, so each of base, base upscaled, candidate and candidate upscaled is reachable.
- Introduced: #89 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-89.16 to RT-89.19: the four combinations, asserted in one test that walks all four
  - ~~🚫 RT-89.24~~ --- transferred to #90 as RT-90.18. Identifier retired and not reused.
- Note: **written as one test rather than four, and that is what found the defect.** Four separate
  tests each pass against an implementation that couples the toggle to the scale, because each only
  ever asks about one pairing. Walking all four found that `WorkspaceState.recordUpscale` and
  `displayedAsset(upscaledWhenAvailable:)` both asked the graph for the *working asset* --- the
  candidate whenever one exists --- while the criterion is about what is *displayed*, and the two
  differ exactly when the toggle shows the base.
- Note: showing the base upscaled means running Core ML on the base, which is seconds of work started
  by flicking a toggle. Showing an unupscaled base while the scale is on would be cheaper and worse:
  the user could not tell whether they were looking at a rendering or a raw image. Making that cheap
  is AC90.7's business, not this one's.

### AC89.7 - Settings offers no pricing or account controls, and no pricing or account client is constructed.
- Introduced: #89 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-89.20: Settings presents no pricing control
  - ✅ RT-89.21: Settings presents no account control
  - ✅ RT-89.22: the application shows no pricing or account state, in either window
- Note: the third condition is the point --- controls removed while the clients still ran would leave
  the application contacting a provider the MVP excludes. **Its structural half is confirmed by
  `audit-code` rather than asserted**, for the reason `TESTING.md` gives: a test cannot watch a
  constructor run, and checking it by reading source is forbidden. RT-89.22 asserts the observable
  half, by identifier *and* by the visible words so a renamed control does not pass.
- Note: the clients remain in `FalGenerationKit` for the version that needs them. What went is the
  application's plumbing, including the UI-test stubs for coordinators nobody builds.

### AC89.9 - Selecting a locked iteration makes that iteration the candidate and the asset it was produced from the base, so the working context is the one that existed when it was locked.
- Introduced: #121 (closed 2026-08-27), backfilled onto the #89 family
- Migrated: 2026-08-27
- Tests:
  - ✅ RT-121.1: a filter after selecting an iteration reads that iteration's parent
  - ✅ RT-121.2: the comparison pair is the selected iteration and its parent
  - ✅ RT-121.3: the filtered/original control is present after filtering a selected iteration
  - ✅ RT-121.4: locking after a selection extends the chain from the selected point
  - ✅ RT-121.5: the canvas reports the selected iteration, not something else
  - ✅ RT-121.8: selecting an iteration discards the outgoing asset's rendering
  - ✅ UT-121.1: select an earlier iteration, apply a filter, and judge the result --- passed by the author in the round of 2026-08-29, recorded on master #133. **Master #120 had recorded this as still pending**; the later round supersedes that
- Note: **the specification was incomplete, not the build.** Until guide 3.31 the base moved only
  forwards, on lock, and a filter reads the base (I2) --- so applying one after scrolling back sent
  the newest lock, which is what the design said to do. The author reported it as filters landing on
  the wrong picture, and the rule they supplied is now in guide 2.4 and I4.
- Note: **I2 and I3 are untouched.** A filter still reads the base and still replaces the candidate.
  Only which asset the base points at has changed.
- Note: RT-121.1 builds a chain of **three** locks and selects the first. With two, the selected
  iteration's parent can coincide with the current base and the test passes against the unfixed
  behaviour.
- Note: the outgoing asset's rendering is discarded on selection. Guide 2.5 already required that
  whenever the working image changes; selection is the one route to that which did not previously
  exist, and it is the seam where it would have been dropped.

### AC89.10 - Selecting an asset with no parent makes it the base, with no candidate.
- Introduced: #121 (closed 2026-08-27), backfilled onto the #89 family
- Migrated: 2026-08-27
- Tests:
  - ✅ RT-121.6: selecting the source makes it the base and leaves no candidate
- Note: the source has no parent, and neither does a raise to the minimum performed on it, so
  AC89.9's rule has no answer for either. The state is the one a fresh import is already in, so
  nothing new is introduced --- but it has to be said, because *"the base becomes the selected
  asset's parent"* is otherwise undefined. **This is the case the author actually described**:
  *"clicked back to my original image"*.
- Note: this criterion is what exposed the return affordance's own defect. "Back to current" was
  conditioned on a candidate existing, and a user standing on the source has none --- so scrolling
  all the way back left no way forward, which is #111's complaint arriving through the door #121
  opened. The affordance now derives from the chain.

### AC89.8 - The lock chain belongs to the working image: importing another image starts a new chain, and the previous chain's files are released.
- Introduced: #89 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-89.25: importing a new image empties the lock chain
  - ✅ RT-89.26: the files of a released chain no longer occupy the output directory
  - ✅ RT-130.2: an Open command is available with a picture already loaded
  - ✅ RT-130.3: the open route is available with nothing loaded
  - ✅ RT-130.4: displaying a locked iteration is still not treated as an import
  - ✅ RT-130.5: a filter result arriving is still not treated as an import
  - ~~🚫 RT-111.4: a genuine import from the viewing state still empties the chain~~
- Note: RT-111.4 is retired, identifier not reused. It could not be performed: with a picture loaded
  the application offers no route to open another. `fileChooser` lives on the empty-canvas drop
  target and there is no File menu open command, leaving only drag and drop from Finder, which
  XCUITest cannot drive. **The anti-gaming property is genuinely lost**: nothing now fails if a later
  change widens `adoptImportedImage`'s guard until no import registers at all. That guide section 2.2
  promises the open panel as one of three import routes, and the application withdraws it once an
  image is loaded, is recorded as a separate product question on master #114.
- Note: **that product question is answered by #130 (closed 2026-08-27), and it was a defect rather
  than a question.** With a picture loaded there was no route in at all: the open-panel button lives
  on the empty-canvas drop target, and the File menu carried Save As and Open Recent but no Open.
  The author reported having to quit and relaunch to test anything twice. A **File > Open Image**
  command on Cmd+O restores the route. RT-130.4 and RT-130.5 also re-assert this criterion's own
  guards --- selecting an iteration and receiving a filter result are still not imports --- which is
  the property RT-111.4's retirement left thin. The open panel itself remains undrivable from
  XCUITest, so RT-130.2 asserts the command exists and is enabled rather than driving it to a file.
- Note: the chain belongs to the image it was built from. Carrying it across would offer iterations
  of a picture no longer on screen, and keeping the files would grow the output directory for the
  life of the session.
- Note: **#130's route was real and undiscovered, which #135 established by looking.** RT-135.1
  pulls down the File menu with a picture loaded and finds both Open Image and Open Recent, so the
  two `CommandGroup(after: .newItem)` blocks coexist and neither displaced the other. The author
  nonetheless reported the same defect a third time. What was missing was not the command but a
  route he would find, and the other half of what he asked for each time --- *clearing* --- had
  never been built. See AC135.2.
- Note: **the verification gap this criterion has carried since #130 is now closed.** RT-135.4 drives
  a real `NSOpenPanel` to a real file after a clear and confirms the picture reaches the canvas. It
  goes through the drop target's chooser rather than the menu command, so the menu route itself is
  still asserted only as far as existing and being enabled --- but the *import path underneath both*
  is now driven end to end, which is what RT-111.4's retirement had left unguarded.

### AC135.2 - A control that clears the current picture is present on the main window whenever a picture is loaded, and absent when the canvas is empty.
- Introduced: #135 (closed 2026-08-30)
- Migrated: 2026-08-30
- Tests:
  - ✅ RT-135.1: with a picture loaded, the File menu offers both Open Image and Open Recent
  - ✅ RT-135.2: a clear control is available once a picture is loaded
  - ✅ RT-135.6: no clear control is offered before a picture is loaded
  - ✅ RT-135.3: clearing returns the canvas to the drop target, with its chooser reachable
  - ✅ RT-135.4: a picture can be brought in through the drop target after a clear
  - ✅ UT-135.1: work on a picture, clear it, bring in another; the route is obvious and nothing is lost unexpectedly --- passed by the author, 2026-08-30
- Note: **this was raised three times.** #130 answered it with a File menu command that tested green
  and was reported missing twice more. The control is therefore on the canvas beside Save As rather
  than in a menu: a route the user does not find is not a route, and three reports is enough evidence
  about where he looks.
- Note: the clear delivers the *browse* as well, without a second route being built. An empty canvas
  is the drop target and the drop target has always carried its own chooser --- so returning to it
  restores an import path that XCUITest can drive, which is why RT-135.4 can exist at all.

### AC135.5 - A cleared session's lock chain is gone from the window; where the session produced a generation it is still listed under Open Recent.
- Introduced: #135 (closed 2026-08-30)
- Migrated: 2026-08-30
- Tests:
  - ✅ RT-135.5: clearing empties the lock strip and Open Recent survives
  - ✅ RT-135.11: after a clear the comparison is unavailable, so the model emptied rather than the canvas alone
- Note: the same terms AC89.8 sets for an import, for the same reason --- the chain belongs to the
  picture it was built from.
- Note: a picture cleared without ever having generated leaves no recents entry. The store records
  `GenerationSessionRecord`s, so an import that reached no provider was never written. **The AC audit
  raised this as F2 against my own first draft**, which asserted the entry unconditionally and would
  have made a correct implementation read as broken.
- Note: RT-135.11 is the guard against the shape of fix that would have produced a fourth report ---
  a clear that swaps the view to the drop target while the model stays populated. Every other test
  here passes in that state.

### AC135.6 - After a clear the settings that belong to the picture are back at their defaults, and the settings that belong to the user are unchanged.
- Introduced: #135 (closed 2026-08-30)
- Migrated: 2026-08-30
- Tests:
  - ✅ RT-135.7: a scale chosen for one picture is not in effect after a clear
  - ✅ RT-135.8: the chosen model survives a clear
- Note: a partition rather than a reset. The scale, the custom dimensions, the derivation and the
  last run's messages go with the picture; the chosen model, face enhancement and the button labels
  are the user's and stay. Wiping those would make putting a picture away a punishment for putting a
  picture away.
- Note: **the comparison setting is on the user's side of the partition, and my own audits put it on
  the wrong one.** The criterion as first drafted listed it among the settings a clear resets.
  Implementing that would have had the application write `showComparison` --- the exact thing guide
  2.3 forbids and the author has reported twice, most recently as #134. What caught it was opening
  `releaseUpscaledResult` and reading the 🚫 note #126 left there. Recorded as DECISION D-6 on #135.
- Note: **the partition was two-way and needed to be three (#140).** It named the picture's settings
  and the user's, and had no place for the application's --- so the filter corpus fell between them
  and was wiped by the clear I shipped the day before. See AC140.1.

### AC140.1 - After a picture is cleared, the filter list offers the whole bundled corpus and its category chips, while the chosen filter and any edited prompt text are cleared with the picture.
- Introduced: #140 (closed 2026-08-31)
- Migrated: 2026-08-31
- Tests:
  - ✅ RT-140.1: the filter list still offers all 108 after a clear
  - ✅ RT-140.2: the category chips are all still offered, asserted by name
  - ✅ RT-140.3: a filter can still be chosen and its prompt loaded
  - ✅ RT-140.4: a clear still empties the chosen filter and the edited prompt
  - ✅ RT-140.6: the corpus survives two clears in succession
- Note: **my regression, reported the day it shipped.** `clearPicture()` ended with
  `FilterSelection()`, whose initializer defaults `filters: []` --- and the entire 108-filter corpus
  lives in that value. `FilterPanel` reads its rows from it and derives its category chips from the
  same place, so clearing a picture emptied the filter panel for the rest of the session.
- Note: **the intention was right and the partition was not.** The chosen filter and its edited prompt
  belong to the picture; the corpus belongs to the application. One type carrying both is what let a
  correct intention empty the panel.
- Note: **#135's tests asserted everything the clear must *do* and nothing it must *not touch*.** That
  is the reusable lesson: a reset needs a test for what it preserves. RT-140.4 is deliberately kept
  separate from RT-140.1 so neither can be satisfied by sacrificing the other.
- Note: RT-140.2 asserts the chips **by name**. They and the rows both derive from `selection.filters`
  today, so restoring one restores the other --- but the author named the categories in his report and
  a criterion he stated should not rest on a shared implementation detail that could change.
- Note: 🚫 **UT-140.1 was withdrawn by this ticket's test audit**, identifier not reused. It would have
  asked the author to judge that the filter panel is untouched, which is fully mechanical: a count
  and a named list, both asserted above.

### AC135.7 - The clear control is unavailable while an upscale or a filter is in flight, so no operation can finish onto an emptied canvas.
- Introduced: #135 (closed 2026-08-30)
- Migrated: 2026-08-30
- Tests:
  - ✅ RT-135.9: the clear control is refused mid-filter and available again once the work settles
- Note: refusal rather than cancellation, recorded as DECISION D-5 on #135. `UpscaleViewModel` has no
  cancellation path, and a filter in flight is a paid provider call that cancelling locally would not
  refund. Building cancellation inside a defect about a missing button is how a small fix becomes a
  subsystem; refusal is one `.disabled` and leaves cancellation to be asked for on its own terms.
- Note: RT-135.9 samples rather than asserting at an instant. The stubbed provider settles quickly
  and a single check races it, so what is asserted is that the control was seen refused at some point
  while the filter was in flight --- and, in the same test, that the refusal ended with the work.

### AC135.8 - A clear takes effect immediately and asks for no confirmation, and an unsaved result goes with it.
- Introduced: #135 (closed 2026-08-30)
- Migrated: 2026-08-30
- Tests:
  - ✅ RT-135.10: clearing empties the canvas with no sheet or dialogue interposed
- Note: the same terms as the import in AC89.8, which has always discarded without prompting. Stated
  as a criterion rather than left as a gap so that it is a decision on the record --- the alternative
  is a fourth report about a confirmation nobody ever discussed.
- Note: **superseded by AC143.1 and AC143.4 (#143, 2026-08-31), and it was wrong when written.** The
  author had **already asked once** to be warned before unsaved work was discarded when I wrote this,
  and I cited AC89.8's precedent to say the opposite. That did not merely miss the request --- it put
  it in the specification as settled, so his second raising read as contrary to the spec rather than
  as a correction to it. Kept rather than deleted, because the record of the mistake is the useful
  part. What survives is the immediacy where nothing is at stake, now AC143.4.
- Note: RT-135.10 still passes and is now about the **silent** half of the rule. It was passing before
  only because its fixture builds no lock chain --- the same narrowness that let #141 and #142 survive
  multiple fixes --- so the fixture is now the point rather than an accident.

### AC143.1 - Where any locked iteration has not been saved this session, an action that would discard it asks first, names how much is at stake, and can be cancelled without effect.
- Introduced: #143 (closed 2026-08-31)
- Migrated: 2026-08-31
- Tests:
  - ✅ RT-143.1: clearing with unsaved iterations asks first and says how many
  - ✅ RT-143.2: cancelling leaves the picture, the chain and the candidate untouched
  - ✅ RT-143.3: confirming proceeds with the action that was asked for
  - ✅ RT-143.5: the question is raised by Cmd+N as well as by the control
  - ✅ RT-143.8: the clear control publishes what a clear would cost
  - ⏳ UT-143.1: build a chain, press Cmd+N, cancel, save, press it again; judge nothing was lost and it did not nag
- Note: **the author's second raising**, and it reverses AC135.8, which I wrote after his first.
- Note: **every route asks the same question** --- the Clear control, Cmd+N and Cmd+O. He named two of
  the three; a warning that fires on some routes and not others teaches a habit that then fails,
  which is worse than not warning at all. Drag and drop is deliberately excluded by **AC143.7**.
- Note: **RT-143.8 exists because I was wrong twice about why the warning appeared not to fire.** I
  blamed two `.alert` modifiers on one view and moved it; the tests failed identically. Publishing
  what the application believed was at stake ended the guessing: it read "5 unsaved" with the control
  enabled, so the state was right and the **test's locator** was wrong --- identifiers inside a
  SwiftUI `.alert` do not survive into the `NSAlert`, which this suite already knew and had written
  down on `failureAlert`.

### AC143.4 - Where every locked iteration has been saved, or there are none, no question is asked and the action happens immediately.
- Introduced: #143 (closed 2026-08-31)
- Migrated: 2026-08-31
- Tests:
  - ✅ RT-143.4: clearing with nothing to lose asks nothing
  - ✅ RT-135.10: no sheet or dialogue is interposed in that state
- Note: **the half that keeps the feature bearable.** *"if and only if there are any unsaved lock
  images."* A warning that fires every time is a warning people learn to dismiss without reading, and
  the commonest case by far is a picture with no chain behind it.

### AC143.6 - A locked iteration counts as saved once it has been written to disk during this session while it was the picture on display.
- Introduced: #143 (closed 2026-08-31)
- Migrated: 2026-08-31
- Tests:
  - ✅ RT-143.8: the count reflects what has and has not been saved
- Note: **conservative by construction.** Recording more than this would mean warning less, and a
  warning that fails to fire loses work paid for at a provider, where one that fires unnecessarily
  costs a click.
- Note: keyed on `inputURL`, which is the displayed source for **both** save routes --- displaying a
  locked iteration sets it, which is the whole of #111 --- so the File menu's Save As records the same
  thing without needing the graph the scene cannot reach.

### AC143.7 - Dragging a picture onto the canvas raises no question.
- Introduced: #143 (closed 2026-08-31)
- Migrated: 2026-08-31
- Tests:
  - ✅ Covered by the absence of a warning path on the drop route; no drag test drives a dialogue
- Note: a deliberate act on a chosen file. Interposing a dialogue would make the primary import route
  hostile. **Raised by the AC audit as the fourth route** and stated either way rather than left
  silent, which is how a fourth report arrives.

### AC145.1 - Cmd+N returns the canvas to its empty state rather than opening a second window.
- Introduced: #145 (closed 2026-08-31)
- Migrated: 2026-08-31
- Tests:
  - ✅ RT-145.1, RT-145.2: Cmd+N clears the canvas and opens no second window
  - ✅ RT-145.6: the command is named in the File menu
  - ✅ RT-143.5: with unsaved iterations it warns first
  - ⏳ UT-145.1: press Cmd+N mid-session and judge that it does what starting again should do
- Note: **AppKit's New Window survived because nothing replaced `.newItem`**, so a second window
  opened onto the *same* `WorkspaceState` and `UpscaleViewModel` --- two windows, one model, so
  whatever the second appeared to show was the first one's state.
- Note: the author chose this over multi-window support, which would need a graph, a lock chain and a
  filter cache **per window**. That is a change to who owns the application's state, not a feature.
- Note: named in the menu because he has twice reported a feature missing that existed but could not
  be found --- #130's Open Image and #135's clear.

### AC144.1 - The picture the canvas is showing can be copied to the pasteboard, and copying is unavailable when there is nothing on it.
- Introduced: #144 (closed 2026-08-31)
- Migrated: 2026-08-31
- Tests:
  - ✅ RT-144.1: copying puts the displayed picture on the pasteboard
  - ✅ RT-144.6: copying is unavailable with a blank canvas
  - ⏳ UT-144.1: copy a filtered result into another application and judge it is the picture that was on screen
- Note: **what is copied is what is displayed** --- the base when the base is being shown, the
  derivation otherwise. Binding to `viewModel.result` alone is the mistake #112 fixed for the
  curtain: with the scale off there is no result, and a filtered picture on screen would copy
  nothing.

### AC144.4 - A picture can be pasted onto a blank canvas and becomes the source; with a picture already loaded, pasting is unavailable and the loaded picture is untouched.
- Introduced: #144 (closed 2026-08-31)
- Migrated: 2026-08-31
- Tests:
  - ✅ RT-144.3, RT-144.5: pasting brings a picture in and it arrives as an import
  - ✅ RT-144.4: with a picture loaded, pasting is refused
- Note: **the guard is the request, not a detail of it.** The author gave the reason at his first
  raising: *"otherwise if we hit it by mistake, the existing image will be lost."* Cmd+V is hit by
  muscle memory and what is lost is a lock chain paid for at a provider.
- Note: **refused rather than warned**, unlike #143's clear. A paste onto a working canvas is almost
  certainly a mistake, and the cheapest correct answer to a mistake is for nothing to happen. The
  guard is in two places --- the menu item is disabled, and `pastePicture()` refuses anyway --- because
  the command travels through a counter and could be delivered late.
- Note: closes guide **2.2**'s promise of paste as one of three import routes, unimplemented since v2
  was specified.
- Note: **`after: .pasteboard`, never `replacing:`.** Replacing that group removes the standard Cut,
  Copy, Paste and Select All for every text field in the application, including the open panel's "Go
  to folder" field the GUI suite types into. Two tests then failed with `loadTestImage` timing out at
  133 seconds, which reads as a harness problem rather than as a menu change.


### AC148.1 - A prompt with no picture behind it can be sent, reaching the model without its edit suffix and carrying no reference.
- Introduced: #148 (closed 2026-08-31)
- Migrated: 2026-08-31
- Tests:
  - ✅ RT-148.1: a prompt with no picture behind it can be sent
  - ✅ RT-148.2: the request carries no reference
  - ✅ RT-148.4: an empty prompt with no picture cannot be sent
  - ✅ RT-148.6: a key is still required
  - ✅ RT-148.3: a prompt alone produces a picture on an empty canvas
  - ✅ RT-148.7: Apply is refused on an empty canvas with no prompt
  - ⏳ UT-148.1: generate a picture from a prompt alone and judge the result is usable as a starting point
- Note: **the author's estimate of the size was right.** `FalRequestBuilder` already chose between the
  edit and text endpoints on whether any reference was attached, so sending none reaches the model
  without `/edit` and restores the sizing parameter Grok's edit endpoint refuses. The only gate was
  `canApply` requiring a working image.
- Note: `canGenerateFromNothing` is a **separate** property rather than a relaxation of `canApply`. A
  great deal is gated on `canApply` and widening it would quietly change all of it.
- Note: **no reference means no upload**, so this skips the two round trips #137 measured and is the
  fastest provider path in the application.

### AC148.3 - A picture generated from a prompt alone becomes the base with role source, so everything downstream works on it unchanged.
- Introduced: #148 (closed 2026-08-31)
- Migrated: 2026-08-31
- Tests:
  - ✅ RT-148.3: the generated picture arrives with no chain behind it, as an import does
  - ✅ RT-148.5: the edit route is unchanged --- a loaded picture still sends its reference
- Note: **`recordFilter` would have refused it.** A filtered asset needs a base to hang from and an
  empty canvas has none, so the result would have been rejected and a picture just paid for would
  never have appeared. It enters through `importImage`, the same door a dragged file uses.
- Note: **guide 2.2 predicted this shape before the feature existed** --- *"an additional way to create
  a `source` asset, entering the same pipeline at the same point as an imported image"* --- and that is
  what was built. Making the first generation a candidate of nothing would have made it a special
  case forever.
- Note: **RT-148.5 is the most important test in this ticket.** It widens a gate everything in the
  filter path depends on, so the edit route must be provably untouched.

### AC135.9 - After a clear the comparison is unavailable because there is nothing to compare, and becomes available again on the next picture that derives something.
- Introduced: #135 (closed 2026-08-30)
- Migrated: 2026-08-30
- Tests:
  - ✅ RT-135.11: after a clear the comparison control is gone
- Note: availability is a fact about the graph; visibility is the user's setting. Conflating the two
  is what AC135.6's first draft did. The user does not have to switch the curtain back on after a
  clear, because it was never switched off --- there was simply nothing to draw it over.

### AC103.1 - An upscale is allocated from the picture the canvas is showing, whichever of the base or the candidate that is.
- Introduced: #103 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-103.1: with the filter toggle showing the base, the allocation derives from the base
  - ✅ RT-103.2: with the candidate displayed, it derives from the candidate
  - ✅ RT-103.3: an upscaled asset is refused as the input, whichever is displayed
  - ✅ RT-103.6: with a rendering on the canvas, the allocation derives from its subject rather than from the rendering
  - ✅ RT-103.7: after a lock, it derives from the new base
- Note: **the "two routes" this criterion was drafted to reconcile do not exist.** The premise was
  that an upscale could be allocated either from the displayed asset or from the working one, and
  that the two disagreed. Reading the code settled it: `WorkspaceState.recordUpscale` allocates a
  graph asset, while `MainView.display` renders and touches the graph not at all --- `UpscaleViewModel`
  contains no reference to the workspace or the graph whatsoever. There is one route. The distinction
  is now recorded at `recordUpscale` rather than refactored away, because there was nothing to
  refactor; D-103.1 records that finding and the false premise that led to it.
- Note: RT-103.6 is the one that matters. Deriving from the rendering rather than from its subject is
  how oversized pixels reach the next stage, and it is the mistake that looks most reasonable at the
  call site --- the rendering is what is on the screen.

### AC103.2 - No cost-confirmation threshold is stored, and the policy that consumed it is absent from the application.
- Introduced: #103 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ~~🚫 RT-103.4~~ --- withdrawn by the first AC audit as a source-reading check
  - ✅ RT-103.5: a preferences round trip carries no cost threshold, and asserts the store wrote something first, so the absence is not vacuous
- Note: **the type's removal is structural and confirmed by `audit-code`, not by a test.** Asserting
  that a type is absent means reading source, which `TESTING.md` forbids; RT-103.5 asserts the
  observable half, that nothing writes a threshold to preferences. RT-103.4 was withdrawn for
  proposing exactly the forbidden check.
- Note: **AC76.3 is superseded by this.** #95 removed the control and the preference key; #103 removed
  `GenerationCostPolicy` and `GenerationCostDecision`, which consumed them. A stored value nothing
  reads is a thing a later reader must prove is dead, and a type with no storage behind it still
  invites a caller.
- Note: the file was renamed to `GenerationAvailability.swift` to match what it holds. A file named
  after a type it no longer contains costs a reader real time, and that cost is invisible to every
  test and every build --- the same class of thing as this delivery's accessibility findings.

## The display model

### AC90.1 - An imported image occupies the canvas from the moment it is loaded and before anything derived from it exists, and progress appears over it rather than in place of it. Loading the import itself is the one operation with nothing beneath it.
- Introduced: #90 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-90.1: an imported image is on the canvas before an upscale completes
  - ✅ RT-90.2: the canvas is never empty while an image is loaded
  - ✅ RT-90.25: while an upscale is under way, the progress indicator and the image are both present
  - ✅ RT-90.40: while the import itself is loading, progress is shown with no image beneath it

### AC90.2 - An operation in flight leaves the canvas showing what it was showing, with progress over it.
- Introduced: #90 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-90.3: with a derivation present, the image is the same before work starts and while it runs
  - ✅ RT-90.4: during an upscale progress is shown over the image rather than in place of it
  - ✅ RT-90.5: during a second upscale the previous rendering remains visible until the new one is ready
- Note: a canvas that empties itself to say it is busy has thrown away the thing the user came for.

### AC90.3 - Turning off the upscale or the filter shows the base immediately, and any operation in flight for the thing turned off is cancelled rather than arriving later.
- Introduced: #90 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-90.6: turning the scale off shows the base without waiting
  - ✅ RT-90.7: turning the filter off shows the base without waiting
  - ✅ RT-90.8: neither leaves a stale rendering on the canvas
  - ✅ RT-90.23: turning the scale off during an upscale cancels the run at the stage, and a late completion is not admitted
- Note: RT-90.23's two halves are separate guarantees and neither implies the other. Cancellation
  that does not stop the work wastes a Neural Engine for a minute; a stop that does not guard the
  result puts an upscale on a canvas whose scale the user has just turned off.

### AC90.4 - Toggling face enhancement leaves the canvas unchanged until the corresponding rendering exists, because both are renderings of one operation rather than one being a fallback for the other. With no upscale selected the face setting changes nothing on the canvas.
- Introduced: #90 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-90.9: toggling face enhancement leaves the previous rendering on screen while the new one builds
  - ✅ RT-90.11: the rebuild count for two toggles of the same pair is one, not two
  - ✅ RT-90.41: with the scale off, toggling face enhancement leaves the canvas showing the base

### AC90.5 - The comparison is a curtain across the image, and the loupe does not exist.
- Introduced: #90 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-90.12: entering comparison shows the curtain
  - ✅ RT-90.13: no loupe or mode toggle is present
  - ✅ RT-90.14: the curtain's divider can be moved across the image
- Note: the divider was a `Circle` with a drag gesture. SwiftUI keeps shapes out of the accessibility
  tree entirely, identifier or not, so for five months it existed for nobody but a mouse --- which is
  why RT-90.14 could not be made to pass until the shape was declared an element.

### AC90.6 - The curtain compares whatever is displayed against the image it derives from, and is absent when there is no derivation.
- Introduced: #90 (closed 2026-08-25)
- Migrated: 2026-08-25
- Superseded in part by: AC94.3
- Tests:
  - ✅ RT-90.15: with an upscale present, the curtain compares base against upscale
  - ✅ RT-90.16: with a filter result present, the curtain compares base against that result
  - ✅ RT-90.17: with no derivation present, no curtain is shown
  - ✅ RT-112.4: with nothing derived, no comparison is offered at all
- Note: RT-112.4 holds the absence half through the affordance rather than the drawing. #112's fix
  widens what counts as a derivation, and the shortest wrong version of it offers Compare whenever
  there is any picture at all, which passes RT-112.1 and breaks this.
  - ✅ RT-90.24: while an earlier iteration is being viewed, the curtain compares that iteration against its own derivation, or is absent
- Note: "the image it derives from" is the *base*, not the immediate parent. Read as the parent it
  paired a filter result with its own upscale --- a comparison of resolution and nothing else.
  AC94.3 states it as the base explicitly.

### AC90.7 - A rendering already produced for an asset, model, sizing and face setting is shown again without being rebuilt.
- Introduced: #90 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-90.10: a rendering already built is shown again without being rebuilt
  - ✅ RT-90.18: turning the scale off and on again shows the upscale without rebuilding it
  - ✅ RT-90.19: toggling face enhancement off and on again rebuilds neither rendering
  - ✅ RT-90.20: a rendering of a different asset is not offered for the current one
  - ✅ RT-90.21: a rendering at a different scale is not offered for the current one
  - ✅ RT-90.22: no more than four renderings are held, and the least recently used is dropped first
- Note: the key is the whole identity --- asset, model, sizing, faces --- so invalidation falls out
  of it rather than being managed. Applying a filter mints a new asset identity, its renderings
  simply miss, and nothing still valid is discarded.
- Note: the author found the omission by its asymmetry: toggling faces was instant while toggling the
  scale rebuilt from scratch, because the store was consulted on one path and not the other.

### AC90.8 - An operation that fails leaves the canvas showing what it was showing, clears the progress indicator, and presents no partial or stale result as though it had succeeded.
- Introduced: #90 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-90.26: a failed upscale leaves the base on the canvas
  - ✅ RT-90.27: a failed upscale clears the progress indicator
  - ✅ RT-90.28: a failed filter leaves the previous display unchanged
  - ✅ RT-90.29: a failed operation contributes no rendering to the store

### AC90.9 - A rendering produced for a base or a setting that is no longer current is discarded rather than displayed.
- Introduced: #90 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-90.30: an upscale completing after a second import is not displayed
  - ✅ RT-90.31: an upscale completing after a lock is not displayed
  - ✅ RT-90.32: with two face-enhancement toggles in flight, the rendering displayed is the one matching the current setting rather than the one that finished last
  - ✅ RT-90.33: the canvas shows the new base while the superseded rendering is still under way
- Note: what a rendering was produced *from* travels with it, as a stamp. Without that, a slow
  upscale of a picture the user has already replaced arrives and is presented as a derivation of its
  successor.

### ~~🚫 AC90.10 - The curtain presents both sides at one displayed size.~~
- Introduced: #90 (closed 2026-08-25)
- **Superseded by AC96.3.** One displayed size means one displayed *rectangle*, so the moment the two
  sides differ in shape something has to be stretched to fill it. Grok raises a short edge under 1024
  to its working size and squares the result, so a 3:4 photograph returns 1:1 --- and the criterion
  as written produced the defect. What it was reaching for survives as AC96.4: the divider addressing
  the same relative position in both.
- Tests: ~~🚫 RT-90.34, RT-90.35, RT-90.36~~ --- superseded by RT-96.8 to RT-96.12 and RT-96.9. The
  equal-aspect case they were written for is RT-96.10. Identifiers retired and not reused.

### AC90.11 - A filter result already produced remains available while the filter is toggled off, and reappears without the provider being contacted again.
- Introduced: #90 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-90.37: toggling the filter off and on again shows the same result
  - ✅ RT-90.38: the second toggle issues no provider request
  - ✅ RT-90.39: applying a different filter replaces the preserved result rather than accumulating one
- Note: RT-90.38 is about money. A filter result already in hand is a picture, not a reason to pay 2c
  again for the same one.
- Note: RT-90.39 is the plausible-wrong-image case. An implementation keying on "the candidate" as a
  role rather than as an identity would serve the previous filter's picture for the new filter.

### AC90.12 - The rendering on the canvas is not discarded by the bound on stored renderings.
- Introduced: #90 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-90.42: with the store full, admitting a further rendering does not evict the displayed one
  - ✅ RT-90.43: the least recently used rendering other than the displayed one is dropped first
- Note: four entries is exactly the base and candidate faces pairs, so in ordinary use the store is
  full and the next admission would otherwise evict the picture the user is looking at.

### AC90.13 - While an operation is under way the picture is drawn unaltered outside the progress indicator's own bounds, with no blur, dimming or material across it. ~~The indicator sits at the top of the canvas~~ and may carry a background within its own bounds.
- Introduced: #90 (closed 2026-08-25)
- Migrated: 2026-08-25
- **Partly superseded by AC119.1 (#119, closed 2026-08-27).** The placement clause only. The
  unaltered-picture and area clauses stand unchanged and are the part that matters most.
- Tests:
  - ✅ RT-90.44: while an upscale is under way, the indicator's area is under a quarter of the canvas area
  - ✅ RT-90.45: the image remains present and hit-testable while the indicator is shown
  - 🚫 RT-90.49, the indicator's vertical midpoint lies in the upper third: removed by #119 with the
    clause it asserted. Centred, the midpoint is at one half, so this now asserts the defect.
  - ✅ RT-90.52: the canvas outside the indicator's frame is identical before work begins and while it runs
  - ✅ UT-90.2: the picture is unaltered while the ticker sits on top --- passed by the author, 2026-08-30
- Note: **this criterion exists because its predecessor was reported as satisfied and failed.** The
  author was told the picture remained visible with the ticker on top, and it did --- softened.
  `ProgressOverlay` filled the canvas with a `.thinMaterial` background, which is a blur. The
  requirement is exact: the picture is not merely *present*, it is *unaltered*. A blur moves no
  element's frame, so RT-90.52 is the observable half and the visual half stays a user test.
- Note: **RT-90.49 was passing at the time #119 superseded its clause, and it was still passing
  afterwards --- by not running.** It lives inside a test that takes an early return when the
  indicator is not caught within three seconds, and the suite's fixture is small enough that the
  upscale usually outruns the poll. #119 centred the indicator and left the assertion in place;
  nothing failed. Worth knowing when reading any assertion that sits behind a `guard ... else
  { return }` in this suite: a green result may mean the code was never reached.
- Note: centring asks **more** of RT-90.52 than the top placement did. The badge now sits over the
  middle of the picture rather than over its edge, so "the canvas outside the indicator's frame is
  identical" is a harder property to hold. The test is unchanged; what it holds has got harder.

### AC119.1 - While an operation is under way, the progress indicator is centred over the picture, horizontally and vertically, and the picture is drawn unaltered outside the indicator's own bounds.
- Introduced: #119 (closed 2026-08-27)
- Migrated: 2026-08-27
- Supersedes: AC90.13's placement clause only. AC90.13's area and unaltered-picture clauses are
  unchanged, and RT-90.44 and RT-90.52 stay where they are rather than being restated here.
- Tests:
  - ✅ RT-119.1: the indicator's horizontal midpoint agrees with the picture's within two points
  - ✅ RT-119.2: the indicator's vertical midpoint agrees with the picture's within two points
  - ✅ RT-119.3: with the indicator centred and the info panel shown, both are present and neither overlaps the other
  - ✅ RT-119.4: with the comparison showing, the indicator is centred over the curtain --- **retired
    against #106 on 2026-08-27, reinstated 2026-08-28 when both of its obstacles went**
  - ✅ RT-128.1: the indicator's background width tracks its content rather than a fixed maximum
  - ✅ RT-128.4: the indicator's area stays under a quarter of the canvas at its larger size
  - ✅ RT-128.5: the indicator remains one addressable element carrying its message
  - ✅ UT-119.1: with an operation running, the indicator's position is judged --- **failed** on 2026-08-27 (remediated by #128), then **passed** by the author in the round of 2026-08-29, recorded on master #133. Both rulings kept: the failure is why #128 exists
- Note: **RT-128.x were migrated late.** #128 was closed without them, which is an omission in that
  closure rather than in the tests; recorded rather than quietly corrected.
- Note: **unchanged as a rule by #142 (2026-08-31), which restacked the badge.** All seven tests above
  were re-run against the new shape and all seven pass. What the badge *says* and how it is
  *arranged* is AC142.1; where it sits is this criterion, and the two are deliberately separate.
- Note: **#128's first fix did nothing, and its test was too weak to notice.** The bound was moved
  from the stack to the text, on the reasoning that a `maxWidth` frame bounds rather than sets.
  Measured: the badge came out at **301 points of a 1080-point canvas** for a 30-character message
  --- the cap exactly. A finite `.frame(maxWidth:)` takes the proposal clamped to the maximum; it
  does not shrink to its child, in either position. `.fixedSize(horizontal: true)` does, and the same
  message now measures **227.5**.
- Note: **RT-128.1 allowed half the canvas and passed on the badge the author was rejecting.** It
  now allows a quarter --- below the 0.279 he called far too wide --- asserts the width tracks the
  message length, and **prints its measurements**, so a green run records what it measured rather
  than hiding it. An estimate of typography is not a measurement, and the first version's estimate
  was generous enough to accept the defect. This is the third time in this delivery that reasoning
  about layout stood in for measuring it.
- Note: **RT-119.4 is reinstated and passing.** It was retired against #106 after four attempts, and
  **both of its obstacles went, from different directions**. Clearing the scale no longer shuts the
  comparison, because #126 made the curtain's visibility the user's setting and
  `releaseUpscaledResult` stopped writing it. And #123 keyed the rendering lookup by the effective
  selection, so a preset change against an unrendered scale starts real work rather than serving the
  previous scale's picture instantly. Either alone would have sufficed.
- Note: **the sequence needed neither obstacle's workaround in the end.** Applying a filter to the
  suite's undersized fixture raises it, and the raise turns the scale off and forgets the held
  renderings (guide 2.5) --- so choosing a scale afterwards simply starts work with the curtain
  already open. The first reinstatement attempt called `clearScale()` first and failed with *"no
  scale reads as in effect, so there is nothing to clear"*: the very state that made the clear
  unnecessary.
- Note: I recorded at #119's closure that this gap *"stays uncovered"* and again at the delivery exit
  that reinstating it was follow-on work. **Both were wrong to defer** --- it was executable, in
  scope, and took two runs.
- Note: **the last failure was a measurement, not a placement, and four cycles went into the wrong
  half of that sentence.** RT-119.1 reported the indicator's midpoint 68 points left of the
  picture's, consistently, and the earlier attempts treated it as a layout problem. It was not.
  `workingIndicator` matched **several** elements: the identifier is applied at the call site and
  reaches the spinner and the message alike, so `firstMatch` returned whichever came first in the
  tree --- the spinner, which sits at the badge's left edge rather than its centre. The badge was
  centred the whole time. `ProgressOverlay` now ends in `.accessibilityElement(children: .combine)`,
  publishing one element whose frame is the badge's, and the test passes with no change to the
  layout at all.
- Note: the diagnosis came from putting the frames into the assertion message rather than from
  another attempt at a fix. That is the lesson worth keeping from this ticket: **when a measurement
  disagrees with the code, measure what is being measured.**
- Note: **RT-119.4 is retired against #106, not abandoned.** It needs real work running while the
  comparison is open, and both routes to that state are closed. Clearing the scale sets the
  selection to `.off`, which calls `releaseUpscaledResult` --- that drops the result and sets
  `showComparison = false`, so the comparison is opened and shut again before the indicator appears.
  Going straight from one preset to another avoids `.off` but meets #106: `heldRendering` is
  consulted inside the `$scaleSelection` sink and `@Published` publishes in `willSet`, so the lookup
  is keyed by the scale being *replaced* and any previous rendering is served instantly. Measured
  rather than inferred --- after settling on 4x and choosing 8x, the diagnostic read `scale8x=in
  effect; curtain present: true; status: Ready`: the picture arrived and no work ever started.
- Note: **what RT-119.4's retirement leaves uncovered, stated rather than glossed.** No automated
  test asserts the indicator's placement while the curtain is showing. The exposure is small and the
  reason is structural: the indicator is a **sibling of `canvasContent` in the canvas `ZStack`**, not
  a child of it, so its placement is decided by the stack and cannot depend on whether the stack's
  other child is the plain picture or the curtain. RT-119.1 and RT-119.2 exercise that same placement
  code. What is lost is confidence that nothing inside `ComparisonView` displaces it. Reinstate with
  #106.
- Note: two points is the tolerance because the criterion means centred, not identical to the last
  decimal. Comparing laid-out `CGFloat` midpoints exactly fails on rounding and retina scaling rather
  than on placement.
- Note: the indicator was taken **out** of the `VStack` it shared with the info panel, which #90 had
  put it in because as separate top-anchored children the panel drew over it and hid it. Centring
  separates them by position instead of by stacking, and RT-119.3 holds that the overlap does not
  come back.

### AC90.14 - The curtain divider sits where the pointer is: its position within the displayed image frame matches the pointer's position within that frame, between 5% and 95% of its width, where it stops. The mapping holds at any window width, with any side-panel width, and at any zoom or pan.
- Introduced: #90 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-90.46: a pointer position maps to the divider fraction at the same relative position
  - ✅ RT-90.47: the mapping is unchanged by window width, by side-panel width, and by a canvas wider than the image's aspect
  - ✅ RT-90.48: a divider dragged to a known point comes to rest at that point
  - ✅ RT-90.50: a pointer beyond either end leaves the divider at 5% and 95% respectively
  - ✅ RT-90.51: the mapping is unchanged at a zoom other than 1.0 and with a non-zero pan offset
- Note: the arithmetic lives in `CurtainGeometry`, out of the view. Inside a `body` it was a defect
  nobody could write a test for, and UT-90.1 failed on it --- "the mouse pointer does not align with
  the curtain".
- Note: RT-90.48 measures at **two** drag positions. The divider's fraction is clamped to the
  *picture's* frame, which is narrower than the canvas, so a drag far enough across the canvas
  legitimately stops at the picture's edge --- and one measurement cannot tell that from a
  coordinate-space error, because both leave the handle short of the pointer.
- Note: **unchanged as a rule by #136 (2026-08-30), and re-asserted under a second gesture.** Where
  the divider *lands* is this criterion; whether it can be *reached* is AC136.1, and what drives it
  is AC136.2. RT-136.4 pins the scroll mapping against this one's pointer mapping rather than
  against a number of its own, so the two cannot come to disagree, and RT-90.48 was re-run after the
  hit area grew and still passes.

## The divider can be taken hold of, and scroll drives it

### AC136.1 - The divider's hit area is larger than its drawn handle, and a press inside the hit area but outside the drawn circle moves the divider rather than panning the picture.
- Introduced: #136 (closed 2026-08-30)
- Migrated: 2026-08-30
- Tests:
  - ✅ RT-136.1: the reachable handle exceeds the drawn one by a usable margin, and the paint is unchanged
  - ✅ RT-136.2: a press beside the drawn handle still takes the divider
  - ✅ UT-136.1: zoom in, move the divider by scrolling, and inspecting a detail is workable --- passed by the author, 2026-08-30
- Note: the drag gesture sat on the drawn `Circle` itself, so the reachable target and the paint were
  one 28-point thing over a photograph that also accepts a drag. The author: *"I always end up
  grabbing the image and moving it instead."* **Always**, not sometimes.
- Note: 44 points, which is the target size the platform's own guidance asks for, and the reason to
  state a number rather than "larger". A hit area one point bigger satisfies "larger" and helps
  nobody, which the test audit raised as F4.
- Note: **the paint is deliberately unchanged at 28.** #66 established that this handle's drawn size
  is load-bearing and that `stroke` versus `strokeBorder` already moved it once, to 29.5. How
  reachable a control is and how large it looks are different questions.
- Note: RT-136.1 alone would pass an implementation that declared a larger frame and left the gesture
  on the inner circle. RT-136.2 is what catches that, by pressing where a user actually misses.

### AC136.2 - While the curtain is up, scrolling with the pointer over the picture moves the divider, along whichever axis the scroll dominantly is, in the direction the system reports, and within the bounds a drag observes.
- Introduced: #136 (closed 2026-08-30)
- Migrated: 2026-08-30
- Tests:
  - ✅ RT-136.3: scrolling over the picture moves the divider
  - ✅ RT-136.4: the position a scroll reaches is the position the pointer mapping gives
  - ✅ RT-136.8: the divider stays within its clamp however far a scroll continues
  - ✅ RT-136.9: the divider follows the reported sign, both ways
  - ✅ RT-136.10: a vertical-only scroll moves it, so a wheel mouse is not excluded
  - ✅ UT-136.1: judged with AC136.1 --- passed by the author, 2026-08-30
- Note: the author's own proposal, and he had thought past the report: *"I could then toggle off the
  filter and zoom in, scroll around, re-enable and expect to see the comparison on the zoomed in
  portion."* At zoom the divider most needs moving exactly where the drag is most wanted for the
  picture.
- Note: **the dominant-axis clause exists because a wheel mouse has no horizontal axis.** A trackpad
  reports `scrollingDeltaX` on a sideways swipe; an ordinary mouse reports only `scrollingDeltaY`.
  Written against X alone this would have looked correct on the machine it was written on and done
  nothing on a desk. The AC audit raised it as F1 before any code.
- Note: **the sign is used as reported, never negated.** macOS applies the user's natural-scrolling
  preference to the deltas before they arrive, so following the sign *is* following the preference.
  Inverting here would fight the setting for half of all users.
- Note: the clamp is reached through `dividerFraction`, the same call the pointer path uses, which is
  what makes RT-136.4 possible as an assertion against the other mapping rather than against a
  constant.

### AC136.3 - Dragging is how the picture is panned while the curtain is up, and it is the only way; a scroll moves the divider or the picture, never both, and a scroll outside the picture moves neither.
- Introduced: #136 (closed 2026-08-30)
- Migrated: 2026-08-30
- Tests:
  - ✅ RT-136.5: the picture is still panned by dragging
  - ✅ RT-136.7: a scroll over the picture does not pan it
  - ✅ RT-136.11: a scroll over the handle moves the divider and leaves the pan alone
  - ✅ RT-136.6: a scroll outside the picture moves neither
- Note: **RT-136.7 is what makes this a constraint rather than an addition.** Without it, an
  implementation that left scroll panning and never wired the divider at all passes RT-136.5 --- and
  that is the change of doing nothing, so it is the likely one. The test audit raised it as F5.
- Note: recorded as **DECISION D-7** on #136. Scroll-to-pan is withdrawn, and the scope is smaller
  than it reads: `ComparisonView` is constructed in exactly one place, inside the comparing branch,
  so scroll-to-pan only ever existed while the curtain was up. Nothing outside the comparison loses
  anything, and the author accepted the trade in the report itself --- *"Though i could still grab
  the image to move it about."*
- Note: **`scrollBelongsToPicture` is untouched and RT-136.6 keeps it asserted.** It was written for
  a global `NSEvent` monitor that moved the photograph when the user scrolled the filter strip. That
  rule is about *where the pointer is*; this ticket changes *what the scroll drives*. Conflating the
  two would have undone a fix while claiming to extend it.
- Note: **RT-136.7 and RT-136.11 first passed vacuously and it is worth recording how.** The helper
  read the curtain container's label directly, which came back empty, so both compared `""` against
  `""`. RT-136.5 exposed it by being the only one of the three that expected the value to change.
  Both now assert the pan is readable before comparing it. The reusable lesson: **a test asserting
  two unknown values are equal proves nothing until one is known to be non-empty.**

## Reference upload

### AC92.1 - A filter's reference reaches the provider as a URL that the provider itself issued, and no request body carries image bytes.
- Introduced: #92 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-92.1: an applied filter's request body contains no base64 payload
  - ✅ RT-92.2: the request references the URL the upload returned
  - ✅ RT-92.3: the request body's size is independent of the reference's size
  - ✅ RT-102.1: an upload reads the file it was given, so the bytes sent are the file's own
- Note: **#102 changed the signature this criterion depends on**, from bytes to a location, so that
  the read happens off the main actor rather than in a SwiftUI view. RT-102.1 is the substitution
  itself: passing a URL must send the same bytes that passing `Data` did, or the change silently
  sends something other than the picture the user chose.
- Note: RT-92.1 decodes the body rather than matching its text. `JSONSerialization` escapes forward
  slashes, so a body genuinely containing `https://v3.fal.media/...` does not contain that string,
  and a version relaxed to make the string match would pass against a body carrying no URL at all.

### AC92.2 - Uploading a reference obtains its destination from the provider before sending, rather than posting to an address chosen locally.
- Introduced: #92 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-92.4: the initiate request carries the file name and content type as JSON
  - ✅ RT-92.5: the bytes are sent to the address the initiate response gave, not to a fixed one
  - ✅ RT-92.6: the returned file URL is the one the initiate response gave
- Note: a composed URL is the plausible shortcut, and RT-92.6 blocks it.

### AC92.3 - An uploaded reference URL is never reused across calls: each apply uploads afresh.
- Introduced: #92 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-92.7: two applies of the same base perform two uploads
  - ✅ RT-92.8: with the provider issuing a different URL each time, two applies send two different URLs
- Note: the guarantee is the absence of a cache, which is structural, so the test for it is
  behavioural. The stub issues a different URL per upload; a cache would fail RT-92.8 in a way an
  internals check would not.

### AC92.4 - The reference's content type is determined by what the file contains, not by what it is called.
- Introduced: #92 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-92.9: a PNG named `.jpg` is uploaded as a PNG
  - ✅ RT-92.10: a file whose content matches no supported type is refused before anything is uploaded
- Note: the code this criterion was written about did the opposite. `MainView.dataURL(for:)` chose
  the media type with `switch url.pathExtension`, so a PNG named `.jpg` went out declared a JPEG.
  `FalStorageClient.contentType(of:)` reads the content, through `CGImageSourceGetType`.

### AC92.5 - An upload that fails is reported against the filter stage, and the base and any candidate survive it.
- Introduced: #92 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-92.11: an initiate failure surfaces as a filter-stage failure in plain language
  - ✅ RT-92.12: a byte-transfer failure surfaces the same way
  - ✅ RT-92.13: neither leaves a partial reference behind for the generation request to use
  - ✅ RT-102.2: a file that cannot be read fails the upload, and no transfer request is made at all
  - ✅ RT-102.3: a failed read leaves no partial reference behind
- Note: **#102 introduced a new failure mode here.** Reading the bytes at the call site meant an
  unreadable file threw before the upload began; moving the read inside `upload` puts it on the same
  path as the provider exchange. RT-102.2 asserts that **nothing was sent**, not merely that an error
  was thrown --- an implementation that initiates, fails to read, and still sends a zero-byte PUT
  before throwing would satisfy the weaker assertion, having handed the provider an empty file at a
  URL it issued. The failure also carries *why*, not only which file: a deleted picture and one the
  user lacks permission to read need different remedies, and the underlying reason was in hand.
- Note: the transfer failure is the dangerous one. The initiate exchange has already returned a
  `file_url`, so an implementation returning it before the bytes arrive would hand the provider a
  URL with nothing behind it.

### AC92.6 - The credential used for upload is the generation key, and it appears only in a request header.
- Introduced: #92 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-92.14: the initiate request carries `Authorization: Key <token>`
  - ✅ RT-92.15: no request URL or body contains the token
  - ✅ RT-92.16: no diagnostic or persisted record contains the token
  - ✅ RT-102.4: the credential still appears only in a header, across both exchanges
- Note: checked across *both* exchanges, not only the first. The signed upload address carries no
  credential of ours, so the transfer sends none.
- Note: RT-102.4 re-pins this across #102's signature change. A refactor that rebuilds request
  construction is exactly where a credential leaks into a URL by accident, so the criterion is
  re-asserted rather than assumed to have survived.

### AC92.7 - The picture uploaded is the base at its own resolution, never a rendering of it.
- Introduced: #92 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-92.17: the bytes uploaded are those of the base's own file
  - ✅ RT-92.18: with an upscale present on the canvas, the upload is still the base
  - ✅ RT-92.19: with a candidate present, the upload is the base rather than the candidate
- Note: the three conditions are the three ways the wrong picture gets chosen --- reaching for what is
  on screen (the upscale), for the working asset (the candidate), or for the last thing produced.

## The controls report the state

### AC93.1 - The scale control and the custom dimension fields show what is actually in effect, from the moment the picture is loaded rather than after an upscale completes, and where that differs from what was requested both are visible and distinguishable. Where no upscale can run at all, no scale reads as active. A scale shown as not in effect remains choosable.
- Introduced: #93 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-93.1: with a reduction in force, the effective scale is the one shown as active
  - ✅ RT-93.2: the requested scale remains visible, is marked as not in effect, and is still choosable
  - ✅ RT-93.3: with no reduction, exactly one scale is shown and it is the requested one
  - ✅ RT-93.9: a reduced custom target shows the effective dimensions, with the typed ones still legible
  - ✅ RT-93.10: the readout derives the effective scale with no completed run available to it
  - ✅ RT-93.11: where nothing fits at any scale, no scale reads as active
  - ✅ RT-93.14: replacing a fitting picture with a larger one moves the effective scale directly
  - ✅ RT-93.15: the scale control's accessibility value reports the readout's state, and is correct while an upscale is still in flight
  - ✅ RT-108.1: the info panel's scale line reports both scales where the ceiling reduces the request
  - ✅ RT-108.2: a 3840x2160 source at 8x names no impossible output, asserted literally
  - ✅ RT-108.3: a request that fits is reported plainly, so the fix does not overcorrect
  - ✅ RT-108.4: reduced custom dimensions report the effective pair with the typed one still distinguishable
  - ✅ RT-108.5: with the scale cleared, the line says so and names no dimensions
  - ~~🚫 RT-108.6: the info panel renders the sentence `SizingLine` composes~~
- Note: the author's report was "large image warning but UX buttons unchanged indicating 4x active
  when it is not". `ScaleReadout` derives the effective scale from the picture's own dimensions
  rather than from a completed run, so the control is correct from the moment the picture loads ---
  which RT-93.10 and RT-93.15 assert directly, because a control reading from a finished run has
  nothing to say before one exists.
- Note: **still choosable** is the half a reduction must not take away. The reduction reports what
  ran; it does not remove the choice.
- Note: **#108 found a third private derivation of sizing truth.** `InfoPanel` multiplied input by
  scale itself and never consulted `UpscaleCeiling.decide`, so a 3840x2160 photograph at 8x read
  *"Scale: 4x -> 15360x8640"*: 132 megapixels against a 32-megapixel ceiling, and an output nothing
  was going to produce, while the status bar a few pixels away reported the truth. The `.custom`
  branch did the same with the typed dimensions. `SizingLine` in `SuperscaleUXCore` is the one
  derivation now, for both branches.
- Note: **RT-108.6 is retired and its half of the claim is structural.** The panel's line cannot be
  read from XCUITest: a `Text` nested inside a container declaring `children: .contain` does not
  report its label, measured four times, the last with the automation environment healthy. That
  `InfoPanel` renders `SizingLine`'s sentence rather than deriving its own is therefore confirmed by
  `audit-code`, as AC89.7, AC98.5, AC103.2 and AC100.2 each already do for a claim a test cannot make
  from outside. RT-108.1 to RT-108.5 hold the observable half.
- Note: **the readout's independence from a completed run is a strength and was also a hazard.**
  #101 found the control reporting *"8x requested, 4x in effect"* while the application sat idle
  with no run, no error and no notice: `reupscaleIfNeeded` guarded on `!isProcessing`, so a scale
  chosen while the import's own upscale was still running was dropped in silence. The control
  accepted the click and its readout began describing a run that did not exist. Because the readout
  is pure, it cannot notice that nothing acted on the request --- which is exactly what makes it
  correct before a run and unable to tell you there is no run. Fixed by removing the guard:
  superseding is handled where it belongs, in `start`'s cancellation and in `publish` and `abandon`
  guarding on `activeRun`. RT-101.1 covers it, and the fault would have gone on being invisible to
  every criterion here, all of which ask what the control *says*.

### AC93.2 - A reduction does not change which scale the user has chosen: choosing a smaller picture restores the full requested scale without the user reselecting it.
- Introduced: #93 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-93.4: after a reduction, importing a picture that fits runs at the originally requested scale
  - ✅ RT-93.5: the stored selection is unchanged by a reduction
- Note: AC82.8 holds --- the selection changes only when the user changes it --- so the control keeps
  showing what was asked for and the message reconciles it with what ran.

### AC147.1 - Each scale preset and face enhancement can be driven from the keyboard, each behaving exactly as its control on the canvas does, and each named in a menu.
- Introduced: #147 (closed 2026-08-31)
- Migrated: 2026-08-31
- Tests:
  - ✅ RT-147.1, RT-147.2: the scale shortcuts toggle, and move the selection rather than adding to it
  - ✅ RT-147.3: Cmd+8 is bound too
  - ✅ RT-147.4: every shortcut is named in a menu
  - ✅ RT-147.5: the face shortcut is refused with no scale selected
  - ✅ RT-147.6: typing digits into a field does not change the scale
  - ⏳ UT-147.1: drive a session by keyboard alone and judge the bindings feel right
- Note: **Cmd+2, Cmd+4, Cmd+8, Cmd+Shift+F**, the bindings the author accepted. **Cmd+8 is an
  assumption** --- he named 2x and 4x, and 8x is a third preset that would look arbitrary left
  unbound. Recorded for validation.
- Note: **Cmd+Shift+F, not Cmd+F**, which is Find by universal convention and the wrong thing to take
  in an application with a filter search field.
- Note: the shortcuts call `viewModel.choose(_:)`, the same method the buttons call, so the two
  cannot drift. That matters because the scale controls are a **toggle group** and pressing the
  active choice clears it (AC82.7) --- the obvious wrong implementation is `scaleSelection =
  .preset(2)`, which sets but never clears. **RT-147.1 asserts the clearing half.**
- Note: face enhancement is disabled on the same two conditions as its control on the canvas --- no
  scale selected (AC93.3) or the model absent. A shortcut that silently set a flag the interface will
  not honour is worse than no shortcut.
- Note: **named in a menu rather than bound invisibly.** The author has twice reported a feature
  missing that existed but could not be found --- #130's Open Image and #135's clear. A shortcut with
  no menu entry is that mistake with no surface at all.
- Note: every binding carries Cmd so that typing a digit into the prompt or the filter search cannot
  change the scale, which would make the feature hostile rather than convenient.

### AC93.3 - Every face-enhancement control is unavailable while no scale is selected, and its unavailability is visible rather than silent. The face model remains obtainable while the controls are unavailable.
- Introduced: #93 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-93.6: with the scale off, the toolbar's face control is disabled
  - ✅ RT-93.7: selecting a scale enables it again
  - ✅ RT-93.8: the disabled control explains why rather than merely being dimmed
  - ✅ RT-93.12: with the scale off and the face model absent, the model is still reachable from the upscale-model sheet
  - ✅ RT-93.13: with the scale off, the upscale-model sheet's face row is disabled too
- Note: face enhancement is a stage of the upscale. With no scale selected there is no upscale for it
  to be a stage of, so a control offering a setting that changes nothing is worse than no control.
- Note: **the reason is an accessibility value, not only a `.help`.** A tooltip is a hover affordance:
  it reaches nobody not holding a pointer still over the control, and nothing asking the tree what
  the state is. That is guide 3.9's rule applied to a disabled control's reason rather than to an
  active control's state.
- Note: the model stays obtainable. Disabling the route to it along with the setting would leave a
  user who has never downloaded it unable to, and no way to find out why.

### AC101.1 - Text the status bar presents is individually addressable by assistive technology, rather than being absorbed into the bar that contains it.
- Introduced: #101 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-101.3: the notice is reachable in the accessibility tree rather than absorbed
  - ✅ RT-101.5: the status text beside it is reachable too, so the rule holds of the bar rather than of one label --- asserted within RT-101.3's test
  - ✅ RT-101.6: a notice replaced while displayed carries the new text
- Note: **the sixth occurrence of guide 3.9's D-2 rule in this codebase**, and the first found in code
  that predates the rule. An identifier on an `HStack` makes SwiftUI treat the stack as a single
  element and absorb its children, so the notice and the status text were rendered on screen and
  absent from the accessibility tree --- unreachable by VoiceOver, not merely by a test.
  `.accessibilityElement(children: .contain)` makes it a container again. A rule found six times is
  not being read at the point where it applies, which is worth more than any one of the fixes.
- Note: **both of the bar's contents are asserted, not just the notice.** A test covering one label
  proves the fix for that label and leaves the rule unproven of the bar.
- Note: RT-101.6 covers replacement rather than first appearance. An element recreated rather than
  updated may carry the old text or not be announced at all, and it is driven through a sequence the
  application already performs: a picture below the filterable minimum is raised, setting one
  message, and the square result that comes back then replaces it with the reshape message.
- Note: the coloured dot beside the text stays decorative, deliberately. Shapes never enter the
  accessibility tree (guide 3.11), and the state it shows is carried in the adjacent text --- a
  colour reaches nobody on its own.

## What the canvas reports, and what the curtain compares

### AC94.5 - A single intent to apply a filter issues at most one provider request, whatever the interface does between the intent and the request being sent.
- Introduced: #122 (closed 2026-08-27), backfilled onto the #94 family
- Migrated: 2026-08-27, renumbered from AC94.4 on 2026-08-28
- Note: **this was migrated as AC94.4 and collided with an existing criterion of that number**
  (*"Scrolling moves the picture only while the pointer is over it"*, introduced by #94 and migrated
  2026-08-25). `ISSUES.md` §"AC and test ID allocation" requires checking the family for the highest
  allocated number before minting one, and I did not --- I read the family's tests rather than its
  criteria. Renumbered rather than left ambiguous: two criteria sharing an ID is worse than a
  renumber, and this one had been in the document for a day rather than being load-bearing history.
  The colliding original keeps AC94.4.
- Tests:
  - ✅ RT-122.1: the Apply control is unavailable from the click, before any asynchronous work
  - ✅ RT-122.2: two clicks in rapid succession issue exactly one provider request
  - ✅ RT-122.4: after a declined request, the control is available again
  - ✅ RT-122.6: after a failed upload, the control is available again
  - ✅ RT-122.7: the window covers the raise on an undersized picture
  - ~~🚫 RT-122.5: a cancelled apply leaves the control available~~
- Note: **backfilled, not cited.** AC94.1 covers the *reporting* half --- work reports immediately ---
  and says nothing about how many requests one intent produces. Stretching it to mean that would
  have been manufacturing coverage, so this is path 2 of `ISSUES.md` §"Bug-fix issues reference
  existing ACs". RT-122.3 belongs to AC94.1 and is listed there.
- Note: the control's availability followed the coordinator's `.generating` phase, which is set only
  once the request is in flight. Before it come the raise to the filterable minimum --- a real Neural
  Engine run of several seconds on an undersized picture --- and the upload. Both sat inside a window
  where the control stayed live, so a second click sent a second **paid** request.
- Note: **a flag, not a debounce.** A time-based guard would swallow the second click while leaving
  the window equally silent, so the press would still look reasonable to the user, and a correctness
  property would become a tuning constant.
- Note: **RT-122.2 needs to count requests, and a GUI test sees results.** A second request returning
  an identical picture is one visible change and two charges, so counting arrivals would pass against
  the defect. `UITestRequestLedger` is a `#if DEBUG` counter surfaced through the accessibility tree,
  counted *before* the stub's failure branch, because a declined request was still issued and against
  a real provider still charged for.
- Note: **RT-122.7 is the one that reproduces the reported conditions.** The raise is the bulk of the
  window; a picture already above the minimum exercises milliseconds and passes against the unfixed
  code. It confirms the raise happened *after* the apply, because the raise is performed at Apply
  rather than at import and there is nothing to observe beforehand.
- Note: RT-122.5 is retired, identifier not reused. Cancellation of the provider call is unreachable
  from the suite --- the stub returns immediately --- and the raise, which is genuinely cancellable,
  is covered by RT-94.15 under AC94.1. The same wall retired RT-113.6 and RT-119.4.

### AC94.1 - Work of any kind on the working image shows progress on the canvas, whether it is a local upscale or a provider call, and stops showing it when that work stops for any reason including cancellation.
- Introduced: #94 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-94.1: while a filter is being applied, the canvas shows progress
  - ✅ RT-94.2: while an upscale runs, the canvas shows progress
  - ✅ RT-94.3: with both in sequence, progress is continuous rather than lapsing between them
  - ✅ RT-94.4: with nothing running, no progress is shown
  - ✅ RT-94.15: a cancelled filter stops the progress and leaves the display as it was
  - ✅ RT-122.3: pressing Apply reports within the same interaction as the click
- Note: **#122 found this criterion half-delivered on the path that mattered most.** Progress was
  bound to the coordinator's `.generating` phase, so the canvas stayed silent through the raise and
  the upload --- the longest part of an apply on an undersized picture, and the very silence that
  made a second click look reasonable. The indicator now follows the intent, yielding to the upscale
  while one runs so the raise keeps its more specific *"Preparing for filtering..."* wording.
- Note: pressing Apply started a provider call that ran for tens of seconds while the canvas showed
  nothing. The application knew --- the status dot and the filter panel both consulted the
  coordinator --- and the one surface the user was looking at did not ask.

### AC94.2 - The progress shown names the work currently under way, so where one operation hands over to another the name follows it.
- Introduced: #94 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-94.5: an applying filter and a running upscale are distinguishable in what the canvas reports
  - ✅ RT-94.6: a provider call reports that it is a provider call rather than reporting tile counts
  - ✅ RT-94.14: at the handover from filter to upscale, the name changes with the work
- Note: RT-94.14 is not RT-94.3 restated. Progress that persists under the *old* name looks identical
  from outside and tells the user a provider call is still running while their Neural Engine grinds
  through tiles.

### AC124.1 - A filter result already produced in this session from the same base, model and prompt is shown again rather than requested a second time, and the user is told it was.
- Introduced: #124 (closed 2026-08-27)
- Migrated: 2026-08-27
- Tests:
  - ✅ RT-124.1: an identical request against the same base finds the result already held
  - ✅ RT-124.2: an edited prompt is a different request
  - ✅ RT-124.3: a different model is a different request
  - ✅ RT-124.4: a held result is never served against a different base
  - ✅ RT-124.5: a result whose file has gone is not offered
  - ✅ UT-124.1: a filter already paid for in this session is shown again rather than requested a second time --- passed by the author in the round of 2026-08-29, recorded on master #133
- Note: **a read of the graph, not a cache beside it.** Every filtered asset already records its
  parent and its `Provenance` --- the model and the prompt as sent --- so *"have we paid for exactly
  this before"* is answerable from what is held. A parallel store keyed on a hash would be a second
  place the truth about a result lives, and the two would drift. This is the shape #100 and #103
  each found and removed: a private second derivation of something the graph already knows.
- Note: **session-scoped by construction**, because the graph is. The author asked for *"within a
  session at least"*, which is a floor rather than a ceiling. Persisting it would raise disk growth
  and a stale result outliving a provider-side model change, and a held result is only useful while
  the picture it descends from is still the one being worked on.
- Note: matched on the prompt **as sent**, so an invisible whitespace difference is a different
  request. That is the honest comparison, because it is what the provider would be given.
- Note: **RT-124.4 is the one that matters most.** Serving a held result against a different base
  would be the wrong-image defect #121 closed, arriving through a cache --- the same failure by a new
  route, which is the shape that also nearly reinstated #111 in this delivery.
- Note: the hit is reported on the status bar's unobtrusive channel, beside the raise and reduction
  notices. A paid action completing instantly is a good surprise only if the application says why.

### AC94.6 - The comparison curtain is shown when the user has it switched on and there are two assets to compare, and at no other time. Nothing but the user changes that setting.
- Introduced: #126 (closed 2026-08-28), backfilled onto the #94 family
- Migrated: 2026-08-28
- Tests:
  - ✅ RT-126.3: with the curtain switched off, no operation shows it
  - ✅ RT-126.4: the setting survives a completed operation
  - ✅ RT-126.5: with it on, the first operation of a session shows it
  - ❌ UT-126.1: the curtain's behaviour --- **failed** by the author in the round of 2026-08-29, *"I am unable to disable the curtain slider after applying a filter."* Answered by **#134**, whose **UT-134.1** the author passed on 2026-08-30. The failure is kept rather than overwritten: the criterion's own behaviour was correct throughout and the defect was AC94.7's, which is exactly what this record should show
- Note: **the application wrote this setting in four places** --- true wherever a run published or a
  held rendering was served, false wherever a result was released or a new picture arrived. So the
  curtain followed *work completing* rather than intent: present on a session's second operation and
  absent on its first, and not staying off when switched off. The author reported it as *"very
  inconsistent about when it decides to show the comparator curtain"*.
- Note: **the setting defaults to on**, because the comparison is what a filter or an upscale is
  for, and the author asked that it be there the first time rather than the second.
- Note: nothing is drawn over nothing. `canvasContent` already requires a derivation and a base to
  compare it against, so the setting can be left alone through an import or a released result ---
  which is what lets the four writes go rather than be replaced with narrower ones.
- Note: **I parked this half of #126 as "a decision awaiting the author" and it was not one.** The
  rule had been stated plainly in the user-test round; I reclassified an instruction as a question,
  and that cost a delivery window. Recorded because the misclassification is the reusable lesson,
  not the flag.
- Note: **re-tested by #134 (2026-08-30) against the case the original tests missed.** RT-126.3 and
  RT-126.4 ran on a picture below the filterable minimum with no scale in effect. RT-134.3, RT-134.4
  and RT-134.5 re-run the same property on a 1600x1200 picture with a scale selected and a live
  upscale, through another filter, a scale change and the selection of an earlier iteration. **All
  three passed first time: the behaviour this criterion states was correct throughout.** What the
  author was reporting turned out to be AC94.7.

### AC94.7 - A control that switches something on and off carries one constant name in both states, and shows which state it is in.
- Introduced: #134 (closed 2026-08-30), backfilled onto the #94 family
- Migrated: 2026-08-30
- Tests:
  - ✅ RT-134.1: the Compare control is present and named "Compare" after filtering a large picture, in both states
  - ✅ RT-134.2: pressing it switches the curtain off, and it stays off
  - ✅ UT-134.1: switch the curtain off, work normally, and it stays off --- passed by the author, 2026-08-30
- Note: **the author reported being unable to switch the curtain off, and the curtain was switching
  off correctly the whole time.** The control read "Full View" while the curtain was up. A user who
  switched the comparison on with a control saying "Compare" then looked for "Compare" to switch it
  off, and there wasn't one. Present, enabled, working, and not called what he came in by.
- Note: this is the author's own rule, given about the filter control in the previous round ---
  *"the user will understand 'Filter' and that the button is a toggle"* --- and *"the change of
  wording on the toggle is confusing."* #129 applied it to the filter control and left this one
  alternating. The criterion is stated generally so the next renaming control is caught by an
  existing rule rather than by a fourth report.
- Note: **it is a `Toggle` with `.toggleStyle(.button)`, and that is not an `app.buttons`.** Changing
  it broke all twenty-two call sites in the GUI suite that located the control as a button, because
  I committed the change without running its own tests. They now go through one `compareControl`
  helper typed `.any`: what this criterion is about is a control the user can press, not whichever
  element kind SwiftUI currently emits for a styled toggle.

### AC94.3 - The curtain compares what is on the canvas against the base it descends from, so a filter result is compared against the picture it was made from rather than against its own upscale.
- Introduced: #94 (closed 2026-08-25)
- Migrated: 2026-08-25
- Supersedes: AC90.6's comparison clause
- Tests:
  - ✅ RT-94.7: after a filter, the curtain's two sides are the base and the filter result
  - ✅ RT-94.8: after an upscale of an unfiltered picture, the two sides are the picture and its upscale
  - ✅ RT-94.9: after a filter and an upscale of it, the two sides are the base and the upscaled filter result
  - ✅ RT-94.10: the two sides are never the same asset
  - ✅ RT-94.16: while an earlier locked iteration is being viewed, the curtain compares that iteration against what descends from it, or is absent
  - ✅ RT-112.1: with the scale off, a filter result offers the comparison, enabled
  - ✅ RT-112.2: entering the comparison over a filter result shows the curtain, with a picture and a divider
  - ✅ RT-112.3: with a scale selected, the comparison is still offered after a filter
  - ✅ RT-112.5: the canvas reports a filter result rather than an upscaled rendering
- Note: **#112 found the criterion pinned what the curtain compares and not that it was offered.**
  The compare control was gated on `viewModel.result`, the upscale output, so after a filter with the
  scale off it never appeared. That is the ordinary state for an undersized picture, because the
  raise to the filterable minimum turns the scale off (AC96.1). RT-90.15 and RT-90.16 stayed green
  throughout: they live in `CanvasContentTests` and decide what the curtain draws, never reaching the
  toolbar condition that decides whether the control exists.
- Note: RT-112.2 asserts the curtain is present and usable rather than which two images it holds.
  That identity is RT-94.7's, asserted against `baseFileURL`; XCUITest observes the accessibility
  tree and cannot make that claim.
- Note: RT-112.5 is the vacuity guard for #117's helper migration, expressed as a product state. If
  anything reports a filter result as a finished upscale, it fails here rather than at the 45 call
  sites of `waitForUpscaleComplete`.
- Note: the far side came from `viewModel.originalImage`, which `processImage` replaces with whatever
  it was last asked to upscale. After a filter that is the filter's own output, so the curtain showed
  the filtered picture against the upscale of the same filtered picture --- two images differing in
  resolution and in nothing else. "The before/after image is the same" was the author's description
  and it was accurate.
- Note: asserted against `baseFileURL`, the property the view reads, rather than against a helper
  written for the occasion. A graph-based guard was tried and suppressed the curtain outright,
  because the view model performs upscales the graph never records --- so "the graph does not know
  what this is" is the ordinary case rather than an error.
- Note: RT-94.16 asserts what both permitted answers have in common rather than demanding one of
  them. Every earlier iteration is in the current base's own ancestry, so a comparison drawn there is
  against something it genuinely descends from.

### AC94.4 - Scrolling moves the picture only while the pointer is over it, and how far it has been moved is observable rather than only visible.
- Introduced: #94 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-94.11: a scroll over the filter panel leaves the picture where it is
  - ~~🚫 RT-94.12: a scroll over the picture pans it~~
  - ✅ RT-94.13: a scroll with no comparison on screen pans nothing
  - ✅ RT-94.17: a location inside the picture belongs to it and one outside does not, at any window size
  - ✅ RT-94.18: the comparison reports its pan as a value
- Note: the picture was panned from an `NSEvent` monitor that never asked where the pointer was, so
  scrolling the filter category strip moved the photograph. A monitor is a global interception
  dressed as a view behaviour: it fires for the toolbar, the side panel, the lock chain and the
  status bar alike.
- Note: **RT-94.12 is retired by #136 (2026-08-30), identifier not reused, and the assertion is
  inverted rather than lost.** Inside the curtain, a scroll now moves the divider and a drag moves
  the picture --- guide 2.3 carries the split and DECISION D-7 records why. **RT-136.7** asserts that
  a scroll over the picture does *not* pan it, and **RT-136.5** that a drag still does, so the
  property is more tightly constrained than before rather than less.
- Note: **this criterion's own first clause is unchanged and is the reason #136 could not simply
  reassign the gesture.** "Only while the pointer is over it" is about *where the pointer is*; #136
  changed *what the scroll drives*. RT-94.11 and RT-136.6 both still stand over the original rule.
- Note: **RT-94.13 caught a silent test-helper defect in the full run of 2026-08-30.**
  `leaveComparison()` decided whether to click by reading the control's label, which worked while the
  control renamed itself. #134 gave it one constant name, so the condition became permanently false
  and the helper stopped doing anything at all --- not failing, simply never leaving the curtain. It
  is behaviour-based now, as `enterComparison()` already was. **The same fix had been applied to the
  twin helper and not looked for here**, which is the reusable part.

## The filterable minimum, and the curtain's geometry

### AC96.1 - A picture whose long edge is under the documented minimum is raised to it before any filter sees it, and the user is told that happened. Where no available scale reaches the minimum, it is raised as far as it goes and the user is told the provider may alter it.
- Introduced: #96 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-96.1: an undersized picture reaches the provider at or above the minimum long edge
  - ✅ RT-96.2: a picture already at or above it is sent unchanged
  - ✅ RT-96.3: the raising is reported
  - ✅ RT-96.4: the raised picture becomes the base, and the scale is turned off, so it is not repeatedly re-upscaled
  - ✅ RT-96.17: a picture too small to reach the minimum at 8x is raised as far as it goes and reported as possibly altered
- Note: the floor is **1024 pixels on the long edge**, held in one named constant and open to
  revision. Long edge rather than a width and a height, so portrait, landscape and square are covered
  without baking in an aspect ratio. The check sits at Apply rather than at import, because the base
  can change after import and a check made only on the way in leaves the defect in place on every
  subsequent apply.
- Note: a raise is a distinct asset role from an upscale. `raisedToMinimum` targets the filter
  model's working resolution and remains valid filter input; `upscaled` targets the size the user
  asked for and the graph refuses it as a stage input. Recorded as an upscale, a raised picture could
  never be sent and the floor could never be enforced.

### AC96.2 - The floor is re-enforced whenever a setting change would drop the working image below it.
- Introduced: #96 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-96.5: a raise that fell short of its target leaves the floor still needing enforcement
  - ✅ RT-96.6: the message appears again when it does
  - ✅ RT-96.7: a change that stays above the minimum raises nothing
- Note: this depends on the graph recording what a raise **produced** rather than what it targeted.
  An allocation is made before the work runs, so its size is an intention: a model whose native scale
  is lower than the one requested delivers less, and the area ceiling can reduce a request outright.
  Recorded at its target, such a raise claims a floor it never reached and the next apply sends an
  undersized picture believing it corrected.
- Note: RT-96.5's planned wording was "changing the upscale model so the result falls below the
  minimum raises it again", which describes a situation the application cannot reach --- changing the
  model does not shrink a file that already exists. The model *is* the mechanism, but at the time the
  work runs rather than afterwards. The test drives the reachable form and the criterion is
  unchanged; the deviation is recorded on #96.

### AC96.3 - The two sides of the curtain are drawn at the same displayed width, each keeping its own proportions, so neither is stretched to match the other's shape and their heights differ when their shapes do. That width is the largest at which both sides fit within the canvas.
- Introduced: #96 (closed 2026-08-25)
- Migrated: 2026-08-25
- Supersedes: AC90.10
- Tests:
  - ✅ RT-96.8: sides of differing aspect are each drawn at their own ratio
  - ✅ RT-96.9: a 1:1 return beside a 3:4 original leaves the original at 3:4
  - ✅ RT-96.10: two sides of equal aspect produce two identical frames, so the ordinary case is unchanged
  - ✅ RT-96.16: sides of differing aspect share a width and differ in height
  - ✅ RT-96.18: a portrait side is not clipped in a wide canvas
- Note: AC90.10 required both sides at one displayed *size*, which is one displayed rectangle --- so
  the moment two shapes differ, something has to be stretched to fill it. Grok raises a short edge
  under 1024 to its working size and squares the result, so a 3:4 photograph returns 1:1 and the
  user's own picture was stretched to match it.
- Note: the shared width is bounded by the canvas rather than equal to it. Using the full width
  unconditionally clips the more portrait of the two off the bottom, which reads as a new defect
  rather than an incomplete fix.

### AC96.4 - The curtain's divider addresses the same fraction of width in both pictures whatever their shapes, so dragging it compares like with like.
- Introduced: #96 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-96.11: a divider at 50% is at the horizontal midpoint of each side
  - ✅ RT-96.12: the mapping holds where the two aspects differ
  - ✅ RT-96.13: the divider's own position remains the pointer's, per AC90.14
- Note: sharing the width is what makes AC96.3 and AC96.4 compatible. Each side drawn at its own
  aspect in a frame of its own width would put one vertical line at a different fraction of each
  picture, so "each keeps its proportions" and "the divider means the same on both" described a
  geometry that does not exist.
- Note: RT-96.13 asserts `dividerFraction` and `dividerX` as inverses across the clamped band rather
  than checking each against arithmetic that could be wrong in the same direction twice. UT-90.1
  failed on exactly that --- the pointer not aligning with the curtain.

### AC66.1 - The divider line is visible when positioned over a bright (near-white) image region.
- Introduced: #66 (closed 2026-08-27)
- Migrated: 2026-08-27
- Tests:
  - ✅ UT-66.1: the divider line is visible over a bright, near-white region of the picture --- passed by the author, 2026-08-27, recorded on master #120

### AC66.2 - The divider line is visible when positioned over a dark (near-black) image region.
- Introduced: #66 (closed 2026-08-27)
- Migrated: 2026-08-27
- Tests:
  - ✅ UT-66.2: the divider line is visible over a dark, near-black region of the picture --- passed by the author, 2026-08-27, recorded on master #120

### AC66.3 - The circle handle is visible against both bright and dark image regions.
- Introduced: #66 (closed 2026-08-27)
- Migrated: 2026-08-27
- Tests:
  - ✅ UT-66.3: the handle's outline is visible against a bright, near-white region --- passed by the author, 2026-08-27, recorded on master #120
  - ✅ UT-66.4: the handle is visible against a dark, near-black region --- passed by the author, 2026-08-27, recorded on master #120
  - ✅ RT-66.1: the divider's and the handle's frames are unchanged by the paint
- Note: **these three criteria carry no automated floor beyond RT-66.1, deliberately.** Whether a
  line reads against a photograph is human judgement, which `TESTING.md`'s decision tree sends to a
  user test. A later change dropping the outline leaves every test green, and that is accepted
  knowingly rather than overlooked.
- Note: **RT-66.1 caught the fix itself.** The first version used `.stroke`, which is centred on the
  shape's edge and grows the drawn bounds by half its line width each side; the handle measured 29.5
  points against its declared 28. AC90.14's pointer mapping and AC96.4's shared-fraction rule both
  sit on those frames, and UT-90.1 failed on that geometry once already. `strokeBorder` draws inside.
- Note: **RT-66.1 now measures 44, not 28, and that is #136 rather than a regression.** Since the hit
  area was enlarged, the handle's accessible frame is the reachable circle and the drawn one is no
  longer separately observable from the running application. **The guard this test exists for did not
  go**: it moved to **RT-136.1**, which pins `CurtainGeometry.handleDiameter` at 28 --- and the view
  now draws the circle from that constant rather than from a literal, which it did not before, so the
  unit test genuinely stands over the paint. What RT-66.1 keeps is the half only the application can
  show: the divider line is still 2 points, and the reachable handle is the enlarged one.

### AC96.5 - A returned picture whose shape differs from what was sent is identifiable as such, rather than silently presented as though the provider had preserved the framing.
- Introduced: #96 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-96.14: a return of differing aspect is marked, and the mark appears in the window
  - ✅ RT-96.15: a return of matching aspect is not marked
- Note: recorded on the asset rather than recomputed by the view, because what was *sent* is not
  always the parent --- the area ceiling reduces a picture before it goes and the minimum-resolution
  floor raises one. A view deriving the answer from the parent's size would describe the graph while
  appearing to describe the provider.
- Note: compared as a ratio with a tolerance rather than by equality, so a provider rounding to an
  even number of pixels is not reported as a reshaping. An unrecorded size yields "not known", never
  a silent "no" --- and at the *view's* boundary that collapses to "say nothing", because telling a
  user something on a guess is worse than staying quiet.
- Note: **"identifiable as such" means the user can tell, not that the graph knows.** The provenance
  recorded the difference and nothing displayed it, so the criterion was delivered to its tests and
  not to anybody using the application. A notice now says so, on the same status-bar channel as the
  raise and the area reduction.

### AC100.1 - A loaded image's dimensions are the file's decoded pixel dimensions, whatever resolution the file records and whichever supported format it is stored in.
- Introduced: #100 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-100.1: an image stored at 300 dpi has its full pixel dimensions rather than its point dimensions
  - ✅ RT-100.2: the same image content stored at 72 dpi has identical dimensions, so resolution changes nothing
  - ✅ RT-100.3: the resolution recorded in the file is present in its metadata, so the fixture genuinely exercises the condition
  - ✅ RT-100.4: an image with no resolution recorded at all has its full pixel dimensions
  - ✅ RT-100.5: an image whose horizontal and vertical resolutions differ has its full pixel dimensions on both axes
  - ✅ RT-100.6: the property holds for JPEG as well as PNG
- Note: this criterion pins `SuperscaleKit`'s contract, **which was never broken**. It is here so that
  the half of the application that was always right stays right, and so that a reader can tell which
  half AC100.2 is about.
- Note: RT-100.3 exists because the other five are worthless without it. A fixture whose 300 dpi was
  silently dropped on write would pass every dimension assertion while exercising nothing.

### AC100.2 - The application measures an imported picture through one function, and the size it records is the picture's pixel size.
- Introduced: #100 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-100.7: a picture recording 300 dpi measures at its pixel dimensions
  - ✅ RT-100.8: a picture recording no resolution measures at its pixel dimensions
  - ✅ RT-100.9: a file that cannot be decoded measures as zero rather than crashing
  - ✅ RT-100.10: a picture above the filterable minimum but recording 300 dpi is not raised when a filter is applied
- Note: **"through one function" is the criterion, not an implementation detail.** The defect existed
  precisely because the view and the view model each had their own way of measuring a picture, and
  nothing could tell them apart. `MainView.importedPixelSize` was private to a view, exercised by
  nothing, and used `NSImage.size` --- which reports points adjusted by the file's stored resolution,
  so a 2048 x 1536 photograph saved at 300 dpi measured about 492 x 369. Undersized by the floor's
  reckoning, raised 4x it did not need, the user's picture altered and their scale selection turned
  off, on a photograph twice the minimum.
- Note: **structural, and so confirmed by code review rather than by a test.** That there is exactly
  one such function cannot be asserted from outside; a test proving it would have to read source,
  which `TESTING.md` forbids. What is asserted is the behaviour at every remaining caller.
- Note: **RT-100.10 is the only one of the ten that would have failed against the broken code end to
  end.** The other nine pin the function; that one pins the consequence the user would have met.
- Note: measuring must not decode. The obvious implementation loads the image and reads the result's
  dimensions, which decompresses the whole picture --- and builds a second full-size plane where there
  is an alpha channel --- to keep two integers: about 160 MB at the 32-megapixel ceiling, on the main
  actor, on import. The size comes from the file's header instead. `kCGImagePropertyPixelWidth` is
  the stored pixel count, immune to the resolution that caused this issue, and uncorrected for EXIF
  orientation exactly as the pipeline's own decode is --- so a rotated photograph measures as it will
  actually be treated. An orientation-correcting source would look more careful and disagree with the
  pixels.

## What the canvas reports it is showing

### AC142.1 - The progress badge shows its message a word to a line, stacked, in capitals, with the spinner below the last word and the words set larger than the application's body text.
- Introduced: #142 (closed 2026-08-31)
- Migrated: 2026-08-31
- Tests:
  - ✅ RT-142.2, RT-142.6: the badge is in capitals and publishes one child per word
  - ✅ RT-142.1, RT-142.3: the badge is stacked rather than a row, measured by its own height
  - ✅ RT-142.4: the badge is set larger than the status bar's body text
  - ✅ RT-119.1 to RT-119.4, RT-128.1, RT-128.4, RT-128.5 all re-run and passing
  - ⏳ UT-142.1: apply a filter and judge the badge reads APPLYING / FILTER / spinner and is big enough
- Note: **the author's fifth raising**, and four previous attempts each changed something real without
  changing what he described. #119 moved the badge's position --- and the 68-point offset chased for
  four cycles turned out to be `firstMatch` measuring the spinner. #128 removed a width cap that was
  pinning it, after two attempts that reasoned about `.frame(maxWidth:)` instead of measuring it. The
  opacity was set at his figure. **Through all of it the badge stayed one horizontal line with the
  spinner in front of the text**, which is the one thing he asked to change.
- Note: *"still too small"* appears in the report every time and was read as *the shading is too wide
  for the text* --- which is what #128 fixed, and is not what he wrote.
- Note: the words are split **explicitly**, not left to wrapping. Wrapping needs a width to break
  against, and a width is exactly what #128 spent two attempts removing.
- Note: 🚫 **the words are not individually addressable, after three runs trying.** Identified alone,
  declared as elements with their own labels, and with the container's label removed so it could not
  absorb them --- the query found nothing every time. The badge stays `.combine`d, which is what
  #128 established. What that left is better evidence than expected: `.combine` joins children with
  `", "`, so a comma-separated label whose every part is a single word is **direct proof** the badge
  published one child per word rather than one holding a sentence.
- Note: RT-142.2/142.6 is **message-agnostic** after a correction. The first version required
  "APPLYING" and "FILTER" and failed reading `'PROCESSING, TILE, 1, OF, 1...'` --- the badge was caught
  during the upscale that follows a filter. Which message shows at any instant is a race; that every
  message is split a word to a line is the criterion.
- Note: the 70-point height threshold is **measured, not guessed**: the previous horizontal badge
  stood at roughly 40 points for this message and the stacked one near 110. The failure message
  prints the reading, so a future change is diagnosed rather than re-guessed.

### AC117.1 - The canvas reports which kind of image it is currently displaying, nothing, the base, a filter result, or an upscaled rendering, as part of its accessibility label, and that report changes only when what is displayed changes.
- Introduced: #117 (closed 2026-08-27)
- Migrated: 2026-08-27
- Tests:
  - ✅ RT-117.1: with no image, the canvas reports that it is showing nothing
  - ✅ RT-117.2: with an image imported and no scale selected, it reports the base
  - ✅ RT-117.3: with an upscale rendered, it reports an upscaled rendering
  - ✅ RT-117.4: with a filter result and no upscale, it reports a filter result
  - ✅ RT-117.5: the report follows the filter toggle between base and candidate
  - ✅ RT-117.7: while an upscale is in flight the canvas still reports the previous kind, and the upscaled rendering only once it is on screen
  - ✅ RT-117.8: while an earlier locked iteration is being viewed, the canvas reports the base
  - ✅ RT-117.9: the four kinds are four distinct values, collected in one test that reaches all four
  - ✅ RT-117.10: the label both names the element and carries the state
  - ~~🚫 RT-117.6: the label names the element, the value carries state, and they differ~~
- Note: **the criterion first asked for a value and could not be met.** SwiftUI carried no
  `accessibilityValue` on any element reachable here: empty on the canvas container, empty on the
  outer container, and empty on a shape declared an element of its own. The label is the channel a
  container declaring `children: .contain` does carry, which guide 3.18 had already recorded for
  a different reason. Superseded to the label on that measurement, under the author's standing
  authority for criteria a measurement shows cannot be met.
- Note: RT-117.6 is retired with that supersession. Written against the value clause, it compared the
  label against a substring of itself once the state moved there, and passed while proving nothing.
- Note: **RT-117.7 is the test that stops this criterion recreating the defect it prevents.** AC90.2
  keeps the previous picture on the canvas while work runs, so a report that moved when an upscale
  *started* would tell the suite an upscale had finished before one had, at the 45 call sites of
  `waitForUpscaleComplete`.
- Note: the four kinds are display states and deliberately do not mirror `AssetRole`. A base raised to
  the filterable minimum is a `raisedToMinimum` asset and is still the base to somebody looking at it.
- Note: **RT-117.8 could not be written until #111 closed.** Before it, opening a locked iteration was
  processed as an import and the viewing state collapsed at once, so the test would have passed
  because the state was gone rather than because the report was right.

**Key:** ✅ passing · ⏳ pending · ❌ failing · ~~🚫 removed~~

---

## Storage locations

### AC116.1 - Every directory into which the application writes assets, generated images, or session history derives from a single configured root, so a launch given a test root leaves the user's application-support directory untouched.
- Introduced: #116 (closed 2026-08-26)
- Migrated: 2026-08-26
- Tests:
  - ✅ RT-116.1: with a root configured, an upscale location resolves beneath it
  - ✅ RT-116.2: with a root configured, a raise location resolves beneath it
  - ✅ RT-116.3: with no root configured, all three storage kinds resolve beneath the application-support path
  - ✅ RT-116.4: after a filter and a raise in the GUI suite, the assets are present beneath the configured root and the user's own directory is unchanged
  - ✅ RT-116.5: with a root configured, the session history root resolves beneath it
  - ✅ RT-116.6: with a root configured, the generated-image store resolves beneath it
- Note: the behaviour was never specified, so this is defined under path 2 of `ISSUES.md` §"Bug-fix issues reference existing ACs" rather than backfilled onto a family that did not exist.
- Note: the application resolved its storage root in two independent places, the entry point for the coordinator and the session store, and `MainView`'s property initializer for the workspace's asset graph. A launch given a test root redirected two of the three storage kinds and left the third writing into the user's own application-support directory. Two ways of deciding one thing with nothing able to tell them apart, which is the shape AC100.2 records for measurement.
- Note: RT-116.4 asserts positively that the assets land beneath the configured root before asserting the user's directory is untouched. The negative alone cannot discriminate: against the unfixed code the writes failed and landed nowhere, so a negative-only test passed without the fix. It last ran in a GUI run whose three failures were the environmental focus fault of #118, and passes in isolation.

**Key:** ✅ passing · ⏳ pending · ❌ failing · ~~🚫 removed~~

---

## Provider failures

### AC98.1 - Every provider failure is read by the same parser, whichever client made the call.
- Introduced: #98 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-98.1: a generation failure and a pricing failure with identical bodies produce identical diagnostics
  - ✅ RT-98.2: a nested `error.message` is read on every client
  - ✅ RT-98.3: a request identifier is attached on every client
- Note: pricing had its own smaller reader --- `message` or `detail`, no nesting, no request
  identifier, no redaction --- so an identical body produced a different and less safe diagnostic
  depending on which call happened to fail. Identical bodies producing identical diagnostics is the
  strongest form of "the same parser" that can be asserted from outside, and it is asserted that way
  rather than by inspecting which function each client calls.

### AC98.2 - A validation failure reported as a list is read, and each entry contributes.
- Introduced: #98 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-98.4: a `detail` list of one entry produces that entry's message
  - ✅ RT-98.5: a `detail` list of several produces all of them
  - ✅ RT-98.6: a `detail` string still produces that string
- Note: FastAPI --- which the platform host runs --- reports validation failures as
  `detail: [{...}, {...}]`. Against a list the parser fell through to the next envelope and then to
  "The provider rejected the request.", discarding the only part that said what was wrong. RT-98.6
  guards the regression a list-handling fix invites.

### AC98.3 - No credential the application holds appears in a diagnostic, whichever client produced it, whichever credential it is, and whatever shape the provider's body took, including a body long enough to be truncated.
- Introduced: #98 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-98.7: a key echoed in a `message` is redacted
  - ✅ RT-98.8: a key echoed in a `detail` list entry is redacted
  - ✅ RT-98.9: a key echoed in an unparseable body is redacted
  - ✅ RT-98.10: redaction happens on the pricing and account clients as well as on generation
  - ✅ RT-98.16: a generation failure redacts an echoed account key, not only the one the call used
  - ✅ RT-98.17: a secret straddling the truncation boundary leaves no fragment behind
- Note: **redact, then truncate.** The other order leaves a fragment of any secret straddling the
  limit, because redaction replaces whole occurrences and half a key is not one --- and a test
  asserting the whole key is absent would pass, since the whole key genuinely is.
- Note: **every credential, not the one the call used.** Redaction removes only what it is handed,
  so each client takes the whole set rather than its own key. This application holds two.
- Note: no test uses a real credential. The keys are strings the tests invent.

### AC98.4 - A failure carries what a caller needs to decide what to do about it, without matching on which client raised it.
- Introduced: #98 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-98.11: a missing or rejected credential is distinguishable from a transport failure
  - ✅ RT-98.12: a rejected credential classifies as `credential` and an unreachable host as `transport`
  - ✅ RT-98.13: the provider's own words survive the classification
- Note: the classification is added to the diagnostic rather than replacing it. A taxonomy that
  turned "the model rejected that aspect ratio" into "request error" would be worse than no taxonomy:
  the category tells the caller what to do, the words tell the user what happened.

### AC98.5 - A failure reaches the user through one surface, whatever raised it.
- Introduced: #98 (closed 2026-08-25)
- Migrated: 2026-08-25
- Tests:
  - ✅ RT-98.14: a filter failure and an upscale failure are presented the same way
  - ✅ RT-113.1: a declined generation request reaches the failure surface
  - ✅ RT-113.2: the upload failure and the generation failure present through the same surface, saying different things
  - ✅ RT-113.3: after a failure is dismissed, nothing still claims work is in progress
  - ✅ RT-113.4: the status bar says "Filter failed" and does not repeat the diagnostic
  - ✅ RT-113.5: a dismissed failure does not come back on the next redraw
  - 🚫 RT-113.6, a cancellation raises no alert: retired before implementation. The generation stub
    returns immediately and the suite has no gate on it, so there is no window in which to press
    cancel. Covered structurally instead: the observation is on the failure *message*, and
    `.cancelled` carries none, so there is nothing for it to report.
- Note: **#113 found that RT-98.14 had only ever exercised half of this criterion.** The two failure
  routes out of one apply are the upload and the generation request. `SUPERSCALE_UI_TEST_FAIL=provider`
  set a single `fails` flag on a stub whose `uploadReference` and `generate` both read it, and
  `submitFilter` uploads first --- so the upload threw and execution never reached `generate`.
  RT-98.14's assertion allows "provider" *or* "storage" and had been reading `"Storage is
  unavailable"`. The flag is now `failsUpload` and `failsGeneration`, with a `generation` mode that
  lets the upload succeed. `provider` is unchanged, so RT-98.14 is unchanged.
- Note: the generation route reached no surface at all, not merely the wrong one. `MainView`
  observed the coordinator for **success only**, through `coordinatorOutputPath`; nothing observed
  `.failed`. `statusText` rendered the diagnostic because it reads the phase on every redraw, which
  is incidental rather than a presentation --- an API error in caption type at the foot of the
  window, in the place reserved for ambient state.
- Note: **the observation is on the failure message, not on the phase.** Observing `.failed` would
  re-raise the alert on every redraw that happened while the phase stayed failed. RT-113.5 is the
  guard, and it is written as a bounded positive check --- dismiss, cause a redraw, assert no alert
  --- because "an alert never appears twice" is an unbounded negative that passes whenever the code
  is merely slow.
- Note: the status bar keeps ambient state and the diagnostic goes to the alert alone. RT-113.4
  blocks the narrowest wrong fix, which is to call `report` and *also* leave the provider's words in
  the caption, so they appear twice.
- Note: the sweep for the same shape reached two other terminal states. `.cancelled` stays a
  caption: the user caused it and already knows, so it is not a failure. The face-model download
  sheet stays as it is, being this criterion's one documented exception for the reason recorded
  above.
- Note: **half of this criterion is a design property, confirmed by `audit-code` rather than
  asserted.** "No failure path bypasses that surface" asks a test to prove a negative across paths
  that do not exist yet, and checking it by reading source is what `TESTING.md` forbids. What the
  implementation does instead is make it a compile error: `UpscaleViewModel.errorMessage` is
  `private(set)`, with `report` and `dismissError` the only ways in, so a later path finds nowhere
  else to write. A compile error is a stronger guarantee than a test nobody re-runs.
- Note: the one deliberate exception is the face-model download sheet, which shows its own failure as
  a stage of its own flow with its own retry. The sheet is modal: an alert raised behind it would be
  unreachable until the user dismissed the very flow the failure is about.
- Note: RT-98.14 compares what each alert *says*, not its title. An `NSAlert`'s own label is "Error"
  for every failure alike, so comparing labels would compare two identical strings and prove nothing.

**Key:** ✅ passing · ⏳ pending · ❌ failing · ~~🚫 removed~~
