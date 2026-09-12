#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPO_ROOT="${SCRIPT_DIR:h}"
readonly VERSION="${1:-0.1.0}"
readonly BUILD_NUMBER="${2:-1}"
readonly APP_NAME="bzbiji"
readonly ARCH="arm64"
readonly MIN_MACOS="13.0"
readonly DIST_DIR="${REPO_ROOT}/dist"
readonly DMG_NAME="${APP_NAME}-${VERSION}-macos-${ARCH}.dmg"
readonly DMG_PATH="${DIST_DIR}/${DMG_NAME}"
readonly CHECKSUM_PATH="${DMG_PATH}.sha256"

if [[ ! "${VERSION}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "error: version must look like 0.1.0"
    exit 1
fi

if [[ ! "${BUILD_NUMBER}" =~ '^[1-9][0-9]*$' ]]; then
    print -u2 "error: build number must be a positive integer"
    exit 1
fi

for tool in swiftc xcrun codesign hdiutil ditto plutil shasum; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        print -u2 "error: required tool not found: ${tool}"
        exit 1
    fi
done

readonly WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bzbiji-release.XXXXXX")"
trap 'rm -rf -- "${WORK_DIR}"' EXIT

readonly APP_PATH="${WORK_DIR}/${APP_NAME}.app"
readonly CONTENTS_DIR="${APP_PATH}/Contents"
readonly MACOS_DIR="${CONTENTS_DIR}/MacOS"
readonly RESOURCES_DIR="${CONTENTS_DIR}/Resources"
readonly DMG_ROOT="${WORK_DIR}/dmg-root"
readonly MODULE_CACHE="${WORK_DIR}/module-cache"
readonly SDK_PATH="$(xcrun --show-sdk-path --sdk macosx)"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${DMG_ROOT}" "${DIST_DIR}" "${MODULE_CACHE}"

print "Building ${APP_NAME} ${VERSION} (${BUILD_NUMBER}) for macOS ${ARCH}..."

swiftc \
    -O \
    -whole-module-optimization \
    -module-cache-path "${MODULE_CACHE}" \
    -sdk "${SDK_PATH}" \
    -target "${ARCH}-apple-macosx${MIN_MACOS}" \
    -parse-as-library \
    "${REPO_ROOT}/bzbiji.swift" \
    "${REPO_ROOT}/ContentView.swift" \
    "${REPO_ROOT}/TabManager.swift" \
    "${REPO_ROOT}/UnifiedPane.swift" \
    "${REPO_ROOT}/MarkdownConverter.swift" \
    "${REPO_ROOT}/MarkdownPane.swift" \
    "${REPO_ROOT}/ImagePane.swift" \
    "${REPO_ROOT}/FileBrowser.swift" \
    -framework SwiftUI \
    -framework AppKit \
    -framework WebKit \
    -o "${MACOS_DIR}/${APP_NAME}"

ditto "${REPO_ROOT}/Info.plist" "${CONTENTS_DIR}/Info.plist"
ditto "${REPO_ROOT}/bzbiji.icns" "${RESOURCES_DIR}/bzbiji.icns"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist"
plutil -lint "${CONTENTS_DIR}/Info.plist" >/dev/null

codesign --force --sign - "${APP_PATH}"
codesign --verify --strict --verbose=2 "${APP_PATH}"

ditto "${APP_PATH}" "${DMG_ROOT}/${APP_NAME}.app"
ln -s /Applications "${DMG_ROOT}/Applications"

print "Creating ${DMG_NAME}..."
hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "${DMG_ROOT}" \
    -format UDZO \
    -ov \
    "${DMG_PATH}"

hdiutil verify "${DMG_PATH}"
(
    cd "${DIST_DIR}"
    shasum -a 256 "${DMG_NAME}" > "${DMG_NAME}.sha256"
)

print
print "Release artifacts:"
print "  ${DMG_PATH}"
print "  ${CHECKSUM_PATH}"
