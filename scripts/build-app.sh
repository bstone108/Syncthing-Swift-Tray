#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/SyncthingTray.xcodeproj"
SCHEME="SyncthingTray"
OUTPUT_DIR="${ROOT_DIR}/build"
APP_NAME="Syncthing Tray.app"
DEST_APP="${OUTPUT_DIR}/${APP_NAME}"
DERIVED_DATA_PARENT="${TMPDIR%/}/SyncthingTrayBuild"
DERIVED_DATA_PATH="$(/usr/bin/mktemp -d "${DERIVED_DATA_PARENT}.XXXXXX")"
SOURCE_APP="${DERIVED_DATA_PATH}/Build/Products/Debug/${APP_NAME}"
XCODEGEN_BIN="${XCODEGEN_BIN:-$(command -v xcodegen || true)}"

cleanup() {
  /bin/rm -rf "${DERIVED_DATA_PATH}"
}

trap cleanup EXIT

/bin/rm -rf "${OUTPUT_DIR}"
/bin/mkdir -p "${OUTPUT_DIR}"

if [[ -z "${XCODEGEN_BIN}" ]]; then
  echo "xcodegen is required to build Syncthing Tray." >&2
  exit 1
fi

"${XCODEGEN_BIN}" generate --spec "${ROOT_DIR}/project.yml"

/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration Debug \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  build

/usr/bin/codesign --verify --deep --strict "${SOURCE_APP}"
/usr/bin/ditto --norsrc --noqtn "${SOURCE_APP}" "${DEST_APP}"
/usr/bin/xattr -cr "${DEST_APP}" || true
/usr/bin/find "${DEST_APP}" -name '._*' -delete || true
/usr/bin/find "${DEST_APP}" -name '.DS_Store' -delete || true

# Repo-local exports under iCloud-managed Documents can pick up file-provider
# metadata after copy. Verify the real build product above and treat the export
# verification here as best-effort so the copied bundle remains available.
if ! /usr/bin/codesign --verify --deep --strict "${DEST_APP}"; then
  echo "warning: exported app bundle in build/ picked up local file metadata after copy; source build verified before export" >&2
fi

echo "Built ${DEST_APP}"
