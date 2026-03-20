#!/usr/bin/env bash
# ABOUTME: Creates a tagged GitHub release and updates the Homebrew formula.
# ABOUTME: Bumps version in source, builds, tags, pushes, and updates the tap.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TAP_REPO="tigger04/homebrew-tap"
FORMULA_PATH="Formula/superscale.rb"
SOURCE_FILE="${PROJECT_ROOT}/Sources/Superscale/SuperscaleCommand.swift"
MANIFEST="${PROJECT_ROOT}/models/manifest.json"

# --- Helpers ---

die() { echo "ERROR: $*" >&2; exit 1; }

get_current_version() {
    grep -oE 'version: "[0-9]+\.[0-9]+\.[0-9]+"' "${SOURCE_FILE}" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
}

bump_version() {
    local current="$1"
    local major minor patch
    IFS='.' read -r major minor patch <<< "${current}"
    patch=$((patch + 1))
    echo "${major}.${minor}.${patch}"
}

# --- Determine version ---

CURRENT_VERSION=$(get_current_version)
if [[ -z "${CURRENT_VERSION}" ]]; then
    die "Could not parse current version from ${SOURCE_FILE}"
fi

if [[ $# -gt 0 && -n "$1" ]]; then
    NEW_VERSION="$1"
else
    NEW_VERSION=$(bump_version "${CURRENT_VERSION}")
fi

TAG="v${NEW_VERSION}"

echo "=== Superscale Release ==="
echo "  Current version: ${CURRENT_VERSION}"
echo "  New version:     ${NEW_VERSION}"
echo "  Tag:             ${TAG}"
echo ""

# Check for uncommitted changes (besides what we're about to modify)
if ! git diff --quiet || ! git diff --cached --quiet; then
    die "Working tree has uncommitted changes. Commit or stash first."
fi

# Check tag doesn't already exist
if git rev-parse "${TAG}" > /dev/null 2>&1; then
    die "Tag ${TAG} already exists."
fi

# --- 1. Update version in source ---

echo "Updating version in source..."
TMPFILE=$(mktemp)
sed "s/version: \"${CURRENT_VERSION}\"/version: \"${NEW_VERSION}\"/" "${SOURCE_FILE}" > "${TMPFILE}"
mv "${TMPFILE}" "${SOURCE_FILE}"

# Verify the change took effect
VERIFY_VERSION=$(get_current_version)
if [[ "${VERIFY_VERSION}" != "${NEW_VERSION}" ]]; then
    git checkout -- "${SOURCE_FILE}"
    die "Failed to update version in source (got ${VERIFY_VERSION}, expected ${NEW_VERSION})"
fi

# --- 2. Build release binary ---

echo "Building release binary..."
swift build -c release 2>&1 | tail -3

# Verify binary reports correct version
BINARY="${PROJECT_ROOT}/.build/release/superscale"
BINARY_VERSION=$("${BINARY}" --version 2>&1 || true)
if [[ "${BINARY_VERSION}" != *"${NEW_VERSION}"* ]]; then
    git checkout -- "${SOURCE_FILE}"
    die "Binary version mismatch: expected ${NEW_VERSION}, got ${BINARY_VERSION}"
fi

# --- 3. Commit, tag, push ---

echo "Committing version bump..."
git add "${SOURCE_FILE}"
git commit -m "chore: bump version to ${NEW_VERSION}"
git tag -a "${TAG}" -m "Release ${NEW_VERSION}"

echo "Pushing to remote..."
git push
git push origin "${TAG}"

# --- 4. Create GitHub release ---

echo "Creating GitHub release..."
gh release create "${TAG}" \
    --title "Superscale ${NEW_VERSION}" \
    --notes "$(cat <<EOF
## Superscale ${NEW_VERSION}

AI image upscaling for Apple Silicon.

### Install

\`\`\`bash
brew tap tigger04/tap
brew install superscale
\`\`\`

### From source

\`\`\`bash
git clone https://github.com/tigger04/superscale.git
cd superscale
git checkout ${TAG}
make install
\`\`\`

See [README](https://github.com/tigger04/superscale#readme) for full usage.
EOF
)"

# --- 5. Compute SHA256 of source tarball ---

echo "Downloading source tarball to compute SHA256..."
TARBALL_URL="https://github.com/tigger04/superscale/archive/refs/tags/${TAG}.tar.gz"
TMPDIR_RELEASE=$(mktemp -d)
trap 'rm -rf "${TMPDIR_RELEASE}"' EXIT

curl -sL "${TARBALL_URL}" -o "${TMPDIR_RELEASE}/source.tar.gz"
SOURCE_SHA256=$(shasum -a 256 "${TMPDIR_RELEASE}/source.tar.gz" | awk '{print $1}')
echo "  Source SHA256: ${SOURCE_SHA256}"

# --- 6. Generate model resource blocks ---

echo "Generating model resource blocks..."
if [[ ! -f "${MANIFEST}" ]]; then
    die "models/manifest.json not found. Run 'make release-models' first."
fi

# Generate resource blocks and install lines from manifest + zip SHA256s
MODEL_RESOURCES=$(python3 -c "
import json, subprocess
from pathlib import Path

manifest = json.loads(Path('${MANIFEST}').read_text())
release_tag = manifest['release_tag']
models_dir = Path('${PROJECT_ROOT}/models')

resources = []
names = []
for m in manifest['models']:
    fn = m['filename']
    zipfile = models_dir / f'{fn}.zip'
    if not zipfile.exists():
        print(f'ERROR: {zipfile} not found', flush=True)
        raise SystemExit(1)
    # SHA256 of the zip file (what Homebrew downloads)
    result = subprocess.run(['shasum', '-a', '256', str(zipfile)], capture_output=True, text=True)
    sha = result.stdout.split()[0]
    name = fn.replace('.mlpackage', '')
    resources.append(f'''  resource \"{name}\" do
    url \"{m['url']}\"
    sha256 \"{sha}\"
  end''')
    names.append(name)
    print(f'  {name}: {sha[:16]}...')

print('RESOURCES_START')
print()
print('\n\n'.join(resources))
print()
print('RESOURCES_END')
print('NAMES_START')
for n in names:
    print(f'      {n}')
print('NAMES_END')
")

# Extract resource blocks
RESOURCE_BLOCKS=$(echo "${MODEL_RESOURCES}" | sed -n '/RESOURCES_START/,/RESOURCES_END/p' | sed '1d;$d')
# Extract model names for install loop
INSTALL_NAMES=$(echo "${MODEL_RESOURCES}" | sed -n '/NAMES_START/,/NAMES_END/p' | sed '1d;$d')

# --- 7. Update Homebrew formula ---

echo "Updating Homebrew formula..."
FORMULA_CONTENT=$(cat <<RUBY
class Superscale < Formula
  desc "AI image upscaling for Apple Silicon"
  homepage "https://github.com/tigger04/superscale"
  url "https://github.com/tigger04/superscale/archive/refs/tags/${TAG}.tar.gz"
  sha256 "${SOURCE_SHA256}"
  license "MIT"

  depends_on :macos
  depends_on arch: :arm64

${RESOURCE_BLOCKS}

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/superscale"

    # Install all models alongside binary (Cellar prefix layout)
    %w[
${INSTALL_NAMES}
    ].each do |model|
      resource(model).stage do
        (prefix/"models"/"#{model}.mlpackage").install Dir["*"]
      end
    end
  end

  def caveats
    <<~EOS
      All six upscaling models are bundled and ready to use.

      List available models:
        superscale --list-models

      Auto-detection selects the best model for your image.
      Override with -m <model-name> if needed.
    EOS
  end

  test do
    assert_match "${NEW_VERSION}", shell_output("#{bin}/superscale --version")
    assert_match "realesrgan-x4plus", shell_output("#{bin}/superscale --list-models")
  end
end
RUBY
)

# Write formula locally
mkdir -p "${PROJECT_ROOT}/Formula"
echo "${FORMULA_CONTENT}" > "${PROJECT_ROOT}/Formula/superscale.rb"
git add "${PROJECT_ROOT}/Formula/superscale.rb"
git commit -m "chore: update Homebrew formula for ${NEW_VERSION}"
git push

# Push formula to tap repo
echo "Pushing formula to tap (${TAP_REPO})..."
B64_FILE=$(mktemp)
PAYLOAD_FILE=$(mktemp)
base64 < "${PROJECT_ROOT}/${FORMULA_PATH}" | tr -d '\n' > "${B64_FILE}"

# Check if formula already exists in tap
EXISTING_SHA=""
if gh api "repos/${TAP_REPO}/contents/${FORMULA_PATH}" > /dev/null 2>&1; then
    EXISTING_SHA=$(gh api "repos/${TAP_REPO}/contents/${FORMULA_PATH}" --jq '.sha')
fi

python3 -c "
import json, sys
with open('${B64_FILE}') as f:
    content = f.read().strip()
payload = {'message': 'Update superscale to ${NEW_VERSION}', 'content': content}
sha = '${EXISTING_SHA}'
if sha:
    payload['sha'] = sha
with open('${PAYLOAD_FILE}', 'w') as f:
    json.dump(payload, f)
"

gh api "repos/${TAP_REPO}/contents/${FORMULA_PATH}" \
    --method PUT --input "${PAYLOAD_FILE}" > /dev/null

rm -f "${B64_FILE}" "${PAYLOAD_FILE}"

echo ""
echo "=== Release Complete ==="
echo "  Version: ${NEW_VERSION}"
echo "  Tag:     ${TAG}"
echo "  Release: https://github.com/tigger04/superscale/releases/tag/${TAG}"
echo "  Formula: Updated in ${TAP_REPO}"
echo ""
echo "Users can now install with:"
echo "  brew tap tigger04/tap"
echo "  brew install superscale"
