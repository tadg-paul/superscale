#!/usr/bin/env bash
# ABOUTME: Creates a GUI release: builds .app, packages DMG, updates Homebrew cask.
# ABOUTME: Companion to release.sh which handles CLI-only releases.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TAP_REPO="tigger04/homebrew-tap"
CASK_PATH="Casks/superscale-gui.rb"
XCODEPROJ="${PROJECT_ROOT}/SuperscaleApp/SuperscaleApp.xcodeproj"
SCHEME="SuperscaleWithTests"
APP_NAME="Superscale"
DMG_NAME="Superscale.dmg"
MODELS_DIR="${PROJECT_ROOT}/models"
SHARED_MODELS_DIR="${HOME}/Library/Application Support/superscale/models"

# --- Helpers ---

die() { echo "ERROR: $*" >&2; exit 1; }

get_current_version() {
    local source_file="${PROJECT_ROOT}/Sources/Superscale/SuperscaleCommand.swift"
    grep -oE 'version: "v[0-9]+\.[0-9]+\.[0-9]+' "${source_file}" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
}

# --- Determine version ---

VERSION=$(get_current_version)
if [[ -z "${VERSION}" ]]; then
    die "Could not parse current version from source"
fi

TAG="v${VERSION}"
echo "=== Superscale GUI Release ==="
echo "  Version: ${VERSION}"
echo "  Tag:     ${TAG}"
echo ""

# --- 1. Build release .app ---

echo "Building release .app..."
BUILD_DIR=$(xcodebuild -project "${XCODEPROJ}" -scheme "${SCHEME}" \
    -configuration Release -showBuildSettings 2>/dev/null \
    | grep ' BUILT_PRODUCTS_DIR' | awk '{print $3}')

xcodebuild -project "${XCODEPROJ}" -scheme "${SCHEME}" \
    -configuration Release build -quiet 2>&1

APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
if [[ ! -d "${APP_PATH}" ]]; then
    die ".app bundle not found at ${APP_PATH}"
fi

echo "  Built: ${APP_PATH}"

# --- 2. Verify no bundled models ---

if [[ -d "${APP_PATH}/Contents/MacOS/models" ]]; then
    # Remove any symlinks from development
    if [[ -L "${APP_PATH}/Contents/MacOS/models" ]]; then
        rm -f "${APP_PATH}/Contents/MacOS/models"
        echo "  Removed development model symlink"
    else
        die ".app contains bundled models — should use shared location instead"
    fi
fi

# --- 3. Ad-hoc code sign ---

echo "Code signing (ad-hoc)..."
codesign --force --deep --sign - "${APP_PATH}"

# --- 4. Create DMG ---

echo "Creating DMG..."
STAGING_DIR=$(mktemp -d)
trap 'rm -rf "${STAGING_DIR}"' EXIT

cp -R "${APP_PATH}" "${STAGING_DIR}/"

# Add Applications symlink for drag-install
ln -s /Applications "${STAGING_DIR}/Applications"

DMG_OUTPUT="${PROJECT_ROOT}/.build/${DMG_NAME}"
mkdir -p "$(dirname "${DMG_OUTPUT}")"

# Remove existing DMG if present
if [[ -f "${DMG_OUTPUT}" ]]; then
    rm -f "${DMG_OUTPUT}"
fi

hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING_DIR}" \
    -ov -format UDZO "${DMG_OUTPUT}" > /dev/null

DMG_SHA256=$(shasum -a 256 "${DMG_OUTPUT}" | awk '{print $1}')
echo "  DMG: ${DMG_OUTPUT}"
echo "  SHA256: ${DMG_SHA256}"

# --- 5. Upload DMG to GitHub release ---

echo "Uploading DMG to GitHub release ${TAG}..."

# Check if release exists; if not, note that make release should be run first
if ! gh release view "${TAG}" > /dev/null 2>&1; then
    echo "  Release ${TAG} does not exist. Creating GUI-specific release..."
    gh release create "${TAG}" \
        --title "Superscale ${VERSION}" \
        --notes "Superscale ${VERSION} — GUI app release."
fi

# Upload (overwrite if exists)
gh release upload "${TAG}" "${DMG_OUTPUT}" --clobber
echo "  Uploaded ${DMG_NAME} to release ${TAG}"

# --- 6. Install models to shared location ---

echo "Ensuring models in shared location..."
mkdir -p "${SHARED_MODELS_DIR}"

MODELS_INSTALLED=0
for pkg in "${MODELS_DIR}"/*.mlpackage; do
    pkg_name=$(basename "${pkg}")
    dest="${SHARED_MODELS_DIR}/${pkg_name}"
    if [[ ! -d "${dest}" ]]; then
        cp -R "${pkg}" "${dest}"
        MODELS_INSTALLED=$((MODELS_INSTALLED + 1))
        echo "  Installed: ${pkg_name}"
    fi
done

if [[ ${MODELS_INSTALLED} -eq 0 ]]; then
    echo "  All models already present in shared location."
else
    echo "  Installed ${MODELS_INSTALLED} model(s) to ${SHARED_MODELS_DIR}"
fi

# --- 7. Update Homebrew cask ---

echo "Updating Homebrew cask..."
DMG_URL="https://github.com/tigger04/superscale/releases/download/${TAG}/${DMG_NAME}"

CASK_CONTENT=$(cat <<RUBY
cask "superscale-gui" do
  version "${VERSION}"
  sha256 "${DMG_SHA256}"

  url "${DMG_URL}"
  name "Superscale"
  desc "AI image upscaling for Apple Silicon"
  homepage "https://github.com/tigger04/superscale"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "${APP_NAME}.app"

  postflight do
    # Install shared models if not already present (e.g. from CLI install)
    models_dir = Pathname("#{Dir.home}/Library/Application Support/superscale/models")
    models_dir.mkpath unless models_dir.exist?

    # Models are downloaded separately via the CLI or brew install superscale
    # If neither is installed, inform the user
    unless models_dir.children.any? { |c| c.extname == ".mlpackage" }
      ohai "Models not found. Install them with:"
      ohai "  brew install tigger04/tap/superscale"
      ohai "Or download manually — see https://github.com/tigger04/superscale#readme"
    end
  end

  zap trash: [
    "~/Library/Application Support/superscale",
    "~/Library/Caches/superscale",
  ]

  caveats <<~EOS
    Superscale GUI shares models with the CLI tool.
    If you also have the CLI installed (brew install superscale),
    both use the same model files — no duplication.

    If the CLI is not installed, models will be downloaded on first use.
  EOS
end
RUBY
)

# Write cask locally
mkdir -p "${PROJECT_ROOT}/Casks"
echo "${CASK_CONTENT}" > "${PROJECT_ROOT}/Casks/superscale-gui.rb"
git add "${PROJECT_ROOT}/Casks/superscale-gui.rb"
git commit -m "chore: update Homebrew cask for GUI ${VERSION}" || true
git push || true

# Push cask to tap repo
echo "Pushing cask to tap (${TAP_REPO})..."
B64_FILE=$(mktemp)
PAYLOAD_FILE=$(mktemp)
base64 < "${PROJECT_ROOT}/Casks/superscale-gui.rb" | tr -d '\n' > "${B64_FILE}"

EXISTING_SHA=""
if gh api "repos/${TAP_REPO}/contents/${CASK_PATH}" > /dev/null 2>&1; then
    EXISTING_SHA=$(gh api "repos/${TAP_REPO}/contents/${CASK_PATH}" --jq '.sha')
fi

python3 -c "
import json
with open('${B64_FILE}') as f:
    content = f.read().strip()
payload = {'message': 'Update superscale-gui cask to ${VERSION}', 'content': content}
sha = '${EXISTING_SHA}'
if sha:
    payload['sha'] = sha
with open('${PAYLOAD_FILE}', 'w') as f:
    json.dump(payload, f)
"

gh api "repos/${TAP_REPO}/contents/${CASK_PATH}" \
    --method PUT --input "${PAYLOAD_FILE}" > /dev/null

rm -f "${B64_FILE}" "${PAYLOAD_FILE}"

echo ""
echo "=== GUI Release Complete ==="
echo "  Version: ${VERSION}"
echo "  Tag:     ${TAG}"
echo "  DMG:     ${DMG_OUTPUT}"
echo "  Release: https://github.com/tigger04/superscale/releases/tag/${TAG}"
echo "  Cask:    Updated in ${TAP_REPO}"
echo ""
echo "Users can now install with:"
echo "  brew tap tigger04/tap"
echo "  brew install --cask superscale-gui"
