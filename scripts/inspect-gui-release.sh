#!/usr/bin/env bash
# ABOUTME: Inspects a Superscale GUI release candidate for required v2 resources.
# ABOUTME: Rejects local data, credentials, generated assets, and model payloads.

set -euo pipefail
IFS=$'\n\t'

die() { echo "ERROR: $*" >&2; exit 1; }

APP_PATH="${1:-}"
[[ -n "${APP_PATH}" ]] || die "Usage: $0 /path/to/Superscale.app"
[[ -d "${APP_PATH}" ]] || die "App bundle not found: ${APP_PATH}"

RESOURCES_PATH="${APP_PATH}/Contents/Resources"
PROMPT_BUNDLE="${RESOURCES_PATH}/Superscale_SuperscaleUXCore.bundle"
[[ -d "${PROMPT_BUNDLE}" ]] || die "Bundled SuperscaleUXCore resources are missing"

PROMPT_COUNT=$(find "${PROMPT_BUNDLE}" -type f -name 'image-*.md' | wc -l | tr -d ' ')
[[ "${PROMPT_COUNT}" == "86" ]] || \
    die "Expected 86 bundled prompt packs, found ${PROMPT_COUNT}"

FORBIDDEN_PATH=$(find "${APP_PATH}" \( \
    -type d \( \
        -name models -o \
        -name Sessions -o \
        -name History -o \
        -name Generated \
    \) -o \
    -type f \( \
        -name '.env' -o \
        -name '.env.*' -o \
        -name 'credentials.json' -o \
        -name 'account.json' -o \
        -name 'metadata.json' -o \
        -name '*.mlpackage' -o \
        -name '*.mlmodelc' \
    \) \
\) -print -quit)

[[ -z "${FORBIDDEN_PATH}" ]] || die "Forbidden release artefact found: ${FORBIDDEN_PATH}"

echo "GUI release inspection passed: ${PROMPT_COUNT} prompt packs; no local or sensitive artefacts"
