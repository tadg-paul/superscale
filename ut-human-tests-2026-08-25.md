# User tests pending on master #79 --- 2026-08-25

Eight tests, all human-judged. Six have never been presented; two failed on
2026-08-25 and are re-offered with the defect fixed and the fix described.

Build to test against: `e8e3239` (or later if further commits land tonight ---
check `git log --oneline -1` before starting). Launch the app from Xcode or
`make run` as usual.

Record each verdict in your own words; I will transcribe them onto #79
afterwards. A FAIL needs only what you observed --- attribution is my job.

---

## Never presented

### UT-91.1 --- the reduction message (AC83.7, from #91)

- **Do:** Import a large picture (2048 px+ on the long edge) and choose 8x, so
  the output would exceed 32 megapixels and the app reduces the scale.
- **Expect:** The message explaining the reduction is clear and unobtrusive.
  It appears in the status bar at the foot of the window, reading like
  "Upscaled 4x rather than 8x, to stay within available memory."
- **Judging:** Is that sentence understandable without knowing the internals?
  Is it quiet enough not to interrupt, and present enough to be noticed?

### UT-89.1 --- working the lock chain (AC89.3, from #89)

- **Do:** Apply a filter, lock the result, apply a second filter, lock again.
  Then scroll back through the chain strip and open an earlier iteration.
- **Expect:** Moving between iterations is a usable way to work, not merely a
  list that exists.
- **Judging:** Can you find the iteration you want? Does opening it feel like
  returning to that point in the work?

### UT-93.1 --- the scale buttons under reduction (AC93.1, from #93)

- **Do:** Same setup as UT-91.1 --- a picture large enough that choosing 8x is
  reduced. Then read the scale buttons themselves.
- **Expect:** It is unambiguous which scale is in effect and which was asked
  for. The 8x button should read as requested-but-not-running; 4x as what is
  actually in effect.
- **Judging:** Hover the buttons too --- the tooltips carry the same story.

### UT-94.1 --- Apply responds immediately (AC94.1, from #94)

- **Do:** Configure a FAL key (or use the test stub), press Apply on a filter,
  and watch the canvas from the moment of the click.
- **Expect:** Something happens immediately, and it keeps saying what is
  happening until the result arrives. The name of the work should follow the
  stages (upload, filter, upscale) rather than one generic spinner.
- **Judging:** Any dead gap between click and first feedback is a fail.

### UT-95.1 --- Settings reads cleanly (AC95.1, from #95)

- **Do:** Open Settings and read the whole scene, row by row.
- **Expect:** Each row says what it is once, and the whole scene reads cleanly.
  No pricing or account rows --- those are gone deliberately.
- **Judging:** Look for duplicated labels, orphaned controls, or anything that
  explains itself twice.

### UT-96.1 --- differently-shaped comparison (AC96.3, from #96)

- **Do:** Filter a picture whose short edge is under 1024 so the provider
  returns a square, then enter comparison.
- **Expect:** The two differently-shaped pictures read correctly side by side:
  each keeps its own proportions, drawn at the same width, neither stretched
  to match the other.
- **Judging:** Heights should differ when shapes differ. Any stretching or
  cropping to force a match is a fail.

---

## Failed 2026-08-25, re-offered

### UT-90.1 --- the curtain divider tracks the pointer (AC90.14, from #90)

- **Previously:** FAILED --- *"the mouse pointer does not align with the
  curtain."* Cause found and fixed: the drag handler divided a handle-local
  coordinate by the whole window's width, two coordinate errors compounding,
  in code dating to March.
- **Do:** Enter comparison and drag the divider across the picture, at more
  than one window width. Resize the window and drag again.
- **Expect:** The divider sits where the pointer is throughout.

### UT-90.2 --- the picture is unaltered under the ticker (AC90.13, from #90)

- **Previously:** FAILED --- *"i want to see the original unfucked unadulterated
  image while the upscale ticker sits on top."* Cause: the progress overlay
  was framed to the whole canvas and backed with a blur material. Fixed: the
  overlay is now a badge sized to its own content, and a regression test
  asserts the picture's frame is unchanged while work runs.
- **Do:** Start an upscale and look at the picture while the ticker is up.
- **Expect:** The picture is unaltered --- no blur, no dimming, no material
  across any part of it. The badge sits on top, covering only itself.

---

## Not in this round

- **UT-79.1, UT-74.1, UT-73.2** --- already passed by you, 2026-08-24.
- No user tests arise from the #99 defect-closure work; its findings are all
  automated or structural.
