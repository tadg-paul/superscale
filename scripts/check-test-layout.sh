#!/usr/bin/env bash
# ABOUTME: Refuses to let one-off tests run inside the regression pack.
# ABOUTME: Enumerates a package's tests and reports any bearing a one-off identifier.
set -eo pipefail

usage() {
    cat <<'USAGE'
Usage:
  check-test-layout.sh [--package-path DIR]
  check-test-layout.sh --listing FILE

Enumerates a Swift package's tests and fails if any test name bears a one-off
identifier (OT<issue>_<n>). One-off tests belong in the separate one-off
package, where the regression command cannot reach them.

Options:
  --package-path DIR   Package to enumerate (default: current directory)
  --listing FILE       Read a captured test listing instead of enumerating
  -h, --help           Show this help
USAGE
}

# A one-off identifier is a case-sensitive OT, an issue number, a separator and
# a sequence number, at the end of the test name. Digits are required and the
# match is anchored so that a name merely containing the letters cannot fire it.
readonly ONE_OFF_PATTERN='_OT[0-9][0-9]*_[0-9][0-9]*$'

package_path="."
listing_file=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --package-path)
            package_path="$2"
            shift 2
            ;;
        --listing)
            listing_file="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'check-test-layout: unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

listing=""
if [[ -n "$listing_file" ]]; then
    if [[ ! -f "$listing_file" ]]; then
        printf 'check-test-layout: listing not found: %s\n' "$listing_file" >&2
        exit 2
    fi
    listing="$(cat -- "$listing_file")"
else
    if ! listing="$(swift test list --package-path "$package_path")"; then
        printf 'check-test-layout: could not enumerate tests in %s\n' "$package_path" >&2
        exit 2
    fi
fi

# grep exits 1 when nothing matches. That is a result, not a failure, so its
# status is consumed by the condition rather than suppressed.
if offenders="$(printf '%s\n' "$listing" | grep -E "$ONE_OFF_PATTERN")"; then
    printf 'check-test-layout: one-off tests found in the regression package:\n' >&2
    while IFS= read -r offender; do
        printf '  %s\n' "$offender" >&2
    done <<<"$offenders"
    printf '\n' >&2
    printf 'One-off tests belong in the OneOff package, invoked by "make test-one-off".\n' >&2
    printf 'Move them there so the regression command cannot reach them.\n' >&2
    exit 1
fi

exit 0
