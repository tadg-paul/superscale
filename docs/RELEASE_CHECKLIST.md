<!-- Version: 1.2 | Last updated: 2026-08-25 -->

# Superscale v2.0 Release Checklist

## Provider Scope

FAL is the only provider shipped in v2.0. The default generation model is
`xai/grok-imagine-image`.

Google and Replicate are future directions informed by `storyboard-gen`; they
are not shipped in v2.0. Release notes and user-facing copy must not imply that
either provider is available in the MVP.

## Automated Evidence

- Run the package regression suite without paid network calls: `make test`.
- Run the SSIM quality gate: `make test-ssim`.
- Run the GUI regression suite in an exclusive UI-test window: `make test-gui`.
  The display must stay awake and unlocked for the whole run --- wrap it in
  `caffeinate` with a keepalive (guide section 7), since a screensaver engaging
  mid-run fails tests in ways that read as element timeouts.
- Build the Release app without publishing it, then run
  `make inspect-gui-release APP_PATH=/path/to/Superscale.app`.
- Confirm the inspector reports 86 prompt packs and no credential, account,
  session, generated-output, or model artefacts.
- Confirm `make release` still builds the CLI path and `make release-gui` uses
  the distinct `.app` and DMG path.

### Licence exclusion of the face model

**AC1.5** requires the GFPGAN weights to be excluded from git, the Homebrew
formula, and all distribution artefacts. The repository half is covered
automatically by `RT-88.5`, which asserts that no model weight is tracked.

The distribution half is verified here rather than by a test, because reading
the formula's text proves only what the file says, and proving what an install
carries needs the network, the published release assets, and a Homebrew prefix:

- Install from the formula into a scratch prefix.
- Confirm the installed tree contains no `.pth`, `.mlpackage`, `.mlmodelc` or
  `.mlmodel` belonging to GFPGAN.
- Confirm the face model is obtained only through `superscale
  --download-face-model`, which presents the licence and requires acceptance.

The weights are non-commercial. A build that shipped them would breach the
licence, so this check is release-blocking rather than advisory.

## Manual Provider Smoke Checks

These checks use real credentials and may incur FAL charges. They must remain
outside automated tests.

*Revised 2026-08-25: issue #78 was closed as superseded when the mode-based
design was removed, and two of its checks describe surfaces the MVP excludes.
The superseded rows stay, struck through, so the history is not dropped.*

- ~~`UT-78.1`: Generate one image from text through FAL and inspect the
  output.~~ **Superseded**: text-to-image is excluded from the MVP.
- ~~`UT-78.3`: Refresh pricing and account state.~~ **Superseded**: pricing
  and account surfaces are paused; grok ships at a documented flat rate and no
  account endpoint is contacted (AC89.7).
- `SMOKE-1` (was UT-78.2): apply one filter to a real photograph through the
  live provider and inspect the result on the canvas and under the curtain.
- `SMOKE-2` (was UT-78.4): upscale the filter result locally at a preset
  scale, and save the output through the standard save flow.
- `SMOKE-3` (was UT-78.5): review release wording; confirm it does not
  overpromise Google or Replicate support, and that the privacy wording
  matches the README's (upscaling local; filters upload the working image).

Record manual results on the active release's tracking issue; only the human
reviewer marks user tests. The wire protocol itself is proven separately by
the one-off live tests recorded on #107 and is not re-proven at release.

## Changelog

- **1.2 (2026-08-25):** The provider smoke checks are reconciled with the delivered MVP: the
  text-to-image and pricing/account checks are struck as superseded with their reasons, the three
  surviving checks are renumbered SMOKE-1 to SMOKE-3 against the shipped filter flow, and the GUI
  suite's display-awake requirement is recorded beside its evidence step.
- **1.1 (2026-08-24):** Added the licence exclusion check for the GFPGAN
  weights, following #88. The regression test that read the Homebrew formula as
  text was removed: a formula's text is not evidence about a built artefact, and
  proving what an install carries is release-time work.
- **1.0 (2026-08-05):** Promoted the v2 release checklist to the canonical
  documentation set.
