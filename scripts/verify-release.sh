#!/bin/zsh
# Verify a DMG without launching or changing the app.
set -euo pipefail
(( $# == 1 )) || { echo "Usage: $0 /path/to/MinimalTimer.dmg" >&2; exit 1; }
readonly image_path="${1:A}"
readonly mount_directory="$(mktemp -d "${TMPDIR:-/tmp}/minimal-timer-verify.XXXXXX")"
cleanup() {
    hdiutil detach "${mount_directory}" >/dev/null 2>&1 || true
    rmdir "${mount_directory}" 2>/dev/null || true
}
trap cleanup EXIT
(cd "${image_path:h}" && shasum -a 256 -c "${image_path:t}.sha256")
hdiutil verify "${image_path}"
hdiutil attach -readonly -nobrowse -mountpoint "${mount_directory}" "${image_path}"
readonly app="${mount_directory}/Minimal Timer.app"
[[ -d "${app}" && -f "${mount_directory}/INSTALL FIRST.txt" ]]
[[ "$(readlink "${mount_directory}/Applications")" == /Applications ]]
codesign --verify --strict --verbose=2 "${app}"
codesign -d --verbose=2 "${app}" 2>&1
lipo "${app}/Contents/MacOS/MinimalTimer" -verify_arch arm64 x86_64
lipo -archs "${app}/Contents/MacOS/MinimalTimer"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${app}/Contents/Info.plist")" == 14.0 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "${app}/Contents/Info.plist")" == true ]]
xcrun vtool -show-build "${app}/Contents/MacOS/MinimalTimer"
echo "Verified contents, checksum, signature, architectures, and macOS metadata."
