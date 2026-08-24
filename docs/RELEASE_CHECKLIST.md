<!-- Version: 1.1 | Last updated: 2026-08-24 -->

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

- `UT-78.1`: Generate one image from text through FAL and inspect the output.
- `UT-78.2`: Generate one image using at least one reference image and inspect
  the output.
- `UT-78.3`: Refresh pricing and account state. Confirm successful values are
  understandable, or that an unavailable response is clear and non-fatal.
- `UT-78.4`: Send a generated image to Upscale, process it locally, and save the
  result.
- `UT-78.5`: Review release wording and confirm it does not overpromise Google
  or Replicate support.

Record manual results on issue `#78`; only the human reviewer marks user tests.

## Changelog

- **1.1 (2026-08-24):** Added the licence exclusion check for the GFPGAN
  weights, following #88. The regression test that read the Homebrew formula as
  text was removed: a formula's text is not evidence about a built artefact, and
  proving what an install carries is release-time work.
- **1.0 (2026-08-05):** Promoted the v2 release checklist to the canonical
  documentation set.
