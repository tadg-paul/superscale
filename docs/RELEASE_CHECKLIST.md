<!-- Version: 1.0 | Last updated: 2026-08-05 -->

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

- **1.0 (2026-08-05):** Promoted the v2 release checklist to the canonical
  documentation set.
