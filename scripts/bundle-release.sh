#!/bin/zsh

set -euo pipefail

readonly script_directory="${0:A:h}"
readonly project_directory="${script_directory:h}"
readonly info_plist="${project_directory}/Packaging/Info.plist"
readonly version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}")"
readonly output_directory="${OUTPUT_DIR:-${project_directory}/dist}"
readonly archive_name="MinimalTimer-${version}.zip"
readonly archive_path="${output_directory}/${archive_name}"
readonly checksum_path="${archive_path}.sha256"
readonly staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/minimal-timer-release.XXXXXX")"
readonly staged_app="${staging_directory}/Minimal Timer.app"

cleanup() {
    rm -rf "${staging_directory}"
}
trap cleanup EXIT

if [[ ! "${version}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "CFBundleShortVersionString must use x.y.z format; found ${version}" >&2
    exit 1
fi

cd "${project_directory}"
swift build -c release --product MinimalTimer --arch arm64 --arch x86_64
readonly binary_directory="$(swift build -c release --show-bin-path --arch arm64 --arch x86_64)"

mkdir -p "${staged_app}/Contents/MacOS"
mkdir -p "${staged_app}/Contents/Resources"
install -m 755 "${binary_directory}/MinimalTimer" "${staged_app}/Contents/MacOS/MinimalTimer"
install -m 644 "${info_plist}" "${staged_app}/Contents/Info.plist"
install -m 644 "${project_directory}/Packaging/AppIcon.icns" "${staged_app}/Contents/Resources/AppIcon.icns"
install -m 644 "${project_directory}/Packaging/Assets.car" "${staged_app}/Contents/Resources/Assets.car"

codesign --force --sign - --timestamp=none --identifier com.mihai.minimaltimer "${staged_app}"
codesign --verify --strict --verbose=2 "${staged_app}"

mkdir -p "${output_directory}"
rm -f "${archive_path}" "${checksum_path}"
ditto -c -k --sequesterRsrc --keepParent "${staged_app}" "${archive_path}"

cd "${output_directory}"
shasum -a 256 "${archive_name}" > "${archive_name}.sha256"

echo "Created ${archive_path}"
echo "Created ${checksum_path}"
