#!/bin/zsh

set -euo pipefail

readonly script_directory="${0:A:h}"
readonly project_directory="${script_directory:h}"
readonly installation_directory="${INSTALL_DIR:-${HOME}/Applications}"
readonly destination="${installation_directory}/Minimal Timer.app"
readonly staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/minimal-timer-install.XXXXXX")"
readonly staged_app="${staging_directory}/Minimal Timer.app"

cleanup() {
    rm -rf "${staging_directory}"
}
trap cleanup EXIT

cd "${project_directory}"
swift build -c release --product MinimalTimer
readonly binary_directory="$(swift build -c release --show-bin-path)"

mkdir -p "${staged_app}/Contents/MacOS"
install -m 755 "${binary_directory}/MinimalTimer" "${staged_app}/Contents/MacOS/MinimalTimer"
install -m 644 "${project_directory}/Packaging/Info.plist" "${staged_app}/Contents/Info.plist"

codesign --force --sign - --timestamp=none --identifier com.mihai.minimaltimer "${staged_app}"
codesign --verify --strict "${staged_app}"

mkdir -p "${installation_directory}"
rm -rf "${destination}"
mv "${staged_app}" "${destination}"

echo "Installed ${destination}"
