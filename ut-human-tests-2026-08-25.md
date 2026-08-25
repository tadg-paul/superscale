# User tests, round 3 --- 2026-08-25

**Quit and relaunch the app before starting.** The copy running during round 2
still sends the storage type FAL rejects; the rebuilt app sends the accepted
one, live-proven by OT-107.1 to OT-107.3 with your own stored key.

Three tests: the ones round 2 could not reach because every Apply failed at
the upload (#107, now fixed). Write verdicts straight into this file.

---

## UT-89.1 --- working the lock chain (AC89.3, from #89)

- **Do:** Apply a filter, lock the result, apply a second filter, lock again.
  Then scroll back through the chain strip and open an earlier iteration.
- **Expect:** Moving between iterations is a usable way to work, not merely a
  list that exists.
- **Judging:** Can you find the iteration you want? Does opening it feel like
  returning to that point in the work?

→

## UT-94.1 --- Apply responds immediately (AC94.1, from #94)

- **Do:** Press Apply on a filter and watch the canvas from the moment of the
  click.
- **Expect:** Something happens immediately, and it keeps saying what is
  happening until the result arrives. The name of the work should follow the
  stages (upload, filter, upscale) rather than one generic spinner.
- **Judging:** Any dead gap between click and first feedback is a fail.

→

## UT-96.1 --- differently-shaped comparison (AC96.3, from #96)

- **Do:** Filter a picture whose short edge is under 1024 so grok returns a
  square, then enter comparison.
- **Expect:** The two differently-shaped pictures read correctly side by side:
  each keeps its own proportions, drawn at the same width, neither stretched
  to match the other.
- **Judging:** Heights should differ when shapes differ. Any stretching or
  cropping to force a match is a fail.

→

---

## Not offered this round

- **UT-93.1** --- failed round 2; waits on #108 (the info panel doing its own
  scale arithmetic).
- **UT-95.1** --- failed round 2; waits on #109 (account key control) and #110
  (the jumping Settings layout).
- **UT-91.1, UT-90.1, UT-90.2** --- passed round 2, done.
