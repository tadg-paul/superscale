#!/usr/bin/env bash
# ABOUTME: Runs the one-off tests belonging to a single issue.
# ABOUTME: Reports when an issue has no one-off tests rather than passing vacuously.
set -eo pipefail

usage() {
    cat <<'USAGE'
Usage:
  run-one-off.sh ISSUE

Runs the one-off tests for the given issue number from the OneOff package.

`swift test --filter` exits successfully when its pattern matches nothing, which
would let an empty run look like a passing one. This checks for matches first
and reports their absence instead.
USAGE
}

if [[ $# -ne 1 ]]; then
    usage >&2
    exit 2
fi

case "$1" in
    -h|--help)
        usage
        exit 0
        ;;
esac

readonly issue="$1"
readonly package_path="OneOff"
readonly pattern="OT${issue}_"

if ! listing="$(swift test list --package-path "$package_path")"; then
    printf 'run-one-off: could not enumerate tests in %s\n' "$package_path" >&2
    exit 2
fi

# grep exits 1 when nothing matches. That is a result, not a failure, so its
# status is consumed by the condition rather than suppressed.
if ! printf '%s\n' "$listing" | grep -qF -- "$pattern"; then
    printf 'run-one-off: no one-off tests found for issue %s\n' "$issue" >&2
    printf 'Looked for names containing %s in the %s package.\n' "$pattern" "$package_path" >&2
    exit 1
fi

swift test --package-path "$package_path" --filter "$pattern"
