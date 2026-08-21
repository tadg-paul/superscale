#!/usr/bin/env bash
# ABOUTME: Runs the one-off tests belonging to a single issue.
# ABOUTME: Reports when an issue has no one-off tests rather than passing vacuously.
set -eo pipefail

usage() {
    cat <<'USAGE'
Usage:
  run-one-off.sh ISSUE [--package-path DIR] [--scratch-path DIR]

Runs the one-off tests for the given issue number.

`swift test --filter` exits successfully when its pattern matches nothing, which
would let an empty run look like a passing one. This checks for matches first
and reports their absence instead.

Options:
  --package-path DIR   One-off package to run (default: OneOff)
  --scratch-path DIR   Build directory to use. Needed only when invoking this
                       against a package whose own test run is in progress,
                       since SwiftPM locks its build directory.
  -h, --help           Show this help
USAGE
}

issue=""
package_path="OneOff"
scratch_path=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --package-path)
            package_path="$2"
            shift 2
            ;;
        --scratch-path)
            scratch_path="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ -n "$issue" ]]; then
                printf 'run-one-off: unexpected argument: %s\n' "$1" >&2
                usage >&2
                exit 2
            fi
            issue="$1"
            shift
            ;;
    esac
done

if [[ -z "$issue" ]]; then
    usage >&2
    exit 2
fi

readonly pattern="OT${issue}_"

scratch_args=()
if [[ -n "$scratch_path" ]]; then
    scratch_args=(--scratch-path "$scratch_path")
fi

if ! listing="$(swift test list --package-path "$package_path" "${scratch_args[@]}")"; then
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

swift test --package-path "$package_path" "${scratch_args[@]}" --filter "$pattern"
