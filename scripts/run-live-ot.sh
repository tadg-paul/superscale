#!/usr/bin/env bash
# ABOUTME: Runs the live-API one-off tests with credentials sourced from .env, never parsed.
# ABOUTME: Outside make test's scope on purpose: these cost real money and touch rest.fal.ai.

set -euo pipefail
cd "$(dirname "$0")/.."

# Source, don't parse: .env is a shell fragment and the shell reads it. `set -a`
# exports everything it defines (FAL_KEY, FAL_ACCOUNT_KEY) to the test process.
# Where the file is absent the tests fall back to the application's own Keychain
# slot, and where neither exists they skip with a message rather than fail.
if [ -f .env ]; then
    set -a
    # shellcheck source=/dev/null
    source ./.env
    set +a
fi

exec swift test --package-path OneOff --filter LiveTests "$@"
