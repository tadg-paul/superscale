# Acceptance Criteria

This is the canonical spec. ACs introduced from 2026-08-21 onward live here.
Pre-cutover ACs remain in their originating issues until cited or migrated.

Last migrated: AC84.6 from #84 on 2026-08-23

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

### AC82.8 - A cleared scale selection persists until a scale is chosen: importing an image, changing the upscale model and changing the custom dimension text all leave it cleared.
- Introduced: #82 (closed 2026-08-23)
- Migrated: 2026-08-23
- Tests:
  - ✅ RT-82.22: importing an image while the selection is cleared leaves it cleared
  - ✅ RT-82.23: changing the upscale model while the selection is cleared leaves it cleared
  - ✅ RT-82.24: a change to the custom dimension text never creates a selection where there was none
  - ✅ RT-82.25: importing an image while a scale is selected adopts the model's native scale rather than clearing the selection

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
