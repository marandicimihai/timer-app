# Free release checklist

## Build and package

1. Run `swift test` and `./scripts/bundle-release.sh` on macOS with Xcode installed.
2. Run `./scripts/package-dmg.sh dist/MinimalTimer-VERSION.zip`.
3. Run `./scripts/verify-release.sh dist/MinimalTimer.dmg`.
4. On a fresh Mac or test account, download the DMG through a browser. Open it,
   drag the app to Applications, and launch from Applications. Follow the
   per-app Open Anyway instructions in the README if blocked. Verify the
   menu-bar icon appears, with no Dock icon. Eject the image and relaunch.
5. Start an activity, finish it, start another, and check History and Goals.
   Use disposable demo activities; do not clear a user's history for a recording.
6. Capture the actual interface for a short demo: start Writing, finish it,
   start Reading, then show History and Goals. Crop out unrelated windows and
   private activity names. Add the resulting GIF near the README download link.
7. Upload the ZIP, DMG, and both SHA-256 files to the matching GitHub release.
   For an existing release, download and checksum its ZIP first, then package
   that exact ZIP; do not replace an already published binary silently.
8. Download `releases/latest/download/MinimalTimer.dmg` anonymously, confirm
   HTTP 200 after redirects, compare its checksum, and verify the downloaded DMG.
   Check the README and feedback template are also published on the default branch.

Keep the fixed name `MinimalTimer.dmg`. GitHub's latest release must have that
asset; drafts, prereleases, or a new release without it can break the shortcut.
The release is ad-hoc signed and has no Apple notarization. A valid code
signature does not mean Gatekeeper will accept a browser download automatically.
Do not remove quarantine or disable Gatekeeper as an installation step.

## Verification record — 2026-11-07

Host: Apple Silicon, macOS 26.6.2, Xcode SDK 26.4.

- Universal local release build succeeded; 71 existing tests passed.
- Published v1.9.5 ZIP downloaded and its published SHA-256 verified.
- DMG created from that ZIP, preserving its ad-hoc app signature.
- Read-only mount verified: Minimal Timer.app, Applications → /Applications,
  and INSTALL FIRST.txt. DMG checksum and internal image checksum passed.
- Code signature passed strict verification. Both arm64 and x86_64 slices
  are present and declare macOS 14.0 minimum; LSUIElement is true.
- Initial public installer URL returned HTTP 404 (ZIP-only release).
- Added DMG and checksum assets to v1.9.5. Anonymous download through the
  latest-release URL then returned HTTP 200 and matched the local SHA-256:
  `db0c0e3ee6449d0e1f87cd54ebe40af1e32c2cd840535fbc89e8f6795c372d75`.
  This was a command-line HTTP download, not a browser/Gatekeeper test.

Not yet verified: Intel execution, macOS 14/15 execution, a fresh-account
browser-download → Applications → Gatekeeper approval → menu-bar flow.
The native UI tool timed out opening the released app, so no genuine demo
recording was captured in this session. Do not substitute a mockup for it.
