# Release process

The MacBook release contains volume control, built-in display brightness, trackpad gestures, and per-device haptics. The `experimental/external-displays` branch retains the earlier external display implementation.

## Validate a candidate

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `Info.plist`. Keep the bundle identifier `io.github.winnercup1602.edgeswipe` consistent.
2. Run `./test.sh` and a release build. Run `swift run EdgeSwipe --probe` on the target MacBook. Add `--round-trip` to check the normal control paths, brightness cancellation, and restoration. The brightness round trip runs when its initial value is on a system keyboard step so the same key path can restore it precisely.
3. On a MacBook with its built-in display only, verify both edges, directions, system indicators, and haptic strength on each supported trackpad. Check normal pointing, two-finger scrolling, clicks, pause and resume, permission changes, sleep and wake, and Bluetooth reconnection. The pointer must release when input ends or is interrupted.
4. Install the packaged app into Applications and repeat the gesture checks through the menu bar app. Record the hardware and OS version tested in the release notes.

## Ad-hoc signed distribution

Build a free downloadable DMG with an Applications folder shortcut.

```sh
./build-dmg.sh --local dist/EdgeSwipe-0.3.0-arm64.dmg
shasum -a 256 dist/EdgeSwipe-0.3.0-arm64.dmg > dist/SHA256SUMS
```

Upload the DMG and checksum to the matching Git tag. State the ad-hoc signing status and link to Apple's [first-launch approval guide](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac). Ad-hoc signed updates can require renewing macOS privacy permissions.

## Developer ID distribution

A Developer ID Application identity and a notarization profile enable Apple's signed distribution flow. Keep the signing key and notarization credentials in Keychain, and keep the Developer ID team consistent across updates.

```sh
EDGESWIPE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
EDGESWIPE_NOTARY_PROFILE='edgeswipe-notary' \
./build-dmg.sh --release
```

The script enables Hardened Runtime, signs the app and disk image, submits the image to Apple, attaches the notarization ticket, and validates the result. On a second Mac or clean account, verify download, installation, first launch, and permission retention before publishing.
