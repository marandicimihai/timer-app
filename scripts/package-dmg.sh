#!/bin/zsh

# Package an existing release ZIP without rebuilding or changing its signature.
set -euo pipefail

if (( $# != 1 )); then
    echo "Usage: $0 /path/to/MinimalTimer-x.y.z.zip" >&2
    exit 1
fi

readonly archive_path="${1:A}"
[[ -f "${archive_path}" ]] || { echo "Release ZIP not found: ${archive_path}" >&2; exit 1; }
readonly output_directory="${archive_path:h}"
readonly image_path="${output_directory}/MinimalTimer.dmg"
readonly staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/minimal-timer-dmg.XXXXXX")"
trap 'rm -rf "${staging_directory}"' EXIT

mkdir "${staging_directory}/payload"
ditto -x -k "${archive_path}" "${staging_directory}/payload"
readonly staged_app="${staging_directory}/payload/Minimal Timer.app"
[[ -d "${staged_app}" ]] || { echo "Release ZIP has no Minimal Timer.app" >&2; exit 1; }
codesign --verify --strict "${staged_app}"
lipo "${staged_app}/Contents/MacOS/MinimalTimer" -verify_arch arm64 x86_64
ln -s /Applications "${staging_directory}/payload/Applications"
cat > "${staging_directory}/payload/INSTALL FIRST.txt" <<'EOF'
MINIMAL TIMER — macOS 14 or later, Apple Silicon and Intel

1. Drag Minimal Timer.app onto Applications.
2. Open Minimal Timer from Applications, then eject this disk image.
3. Look for the timer icon in your menu bar. There is no Dock icon.

FIRST LAUNCH
This free app is ad-hoc signed and is not notarized by Apple.
If macOS blocks it, and you trust this download:
- Try opening it once and dismiss the warning.
- Open System Settings > Privacy & Security.
- Scroll to Security, choose Open Anyway for Minimal Timer, and confirm.
No Terminal commands or changes to global security settings are needed.

TRY IT
Name an activity, press Start, and finish it when you are done.
Open History to review your time, or Goals to set a weekly target.

Source and releases: https://github.com/marandicimihai/timer-app
Feedback: https://github.com/marandicimihai/timer-app/issues/new?template=feedback.yml
EOF

# Build elsewhere first so a failed build cannot replace the previous image.
hdiutil create -volname "Minimal Timer" -srcfolder "${staging_directory}/payload" \
    -format UDZO -ov "${staging_directory}/release.dmg"
hdiutil verify "${staging_directory}/release.dmg"
mv -f "${staging_directory}/release.dmg" "${image_path}"
(cd "${output_directory}" && shasum -a 256 MinimalTimer.dmg > MinimalTimer.dmg.sha256)
echo "Created ${image_path}"
