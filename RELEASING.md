# Release process

## Validate a candidate

1. Increment `CFBundleVersion` and update `CFBundleShortVersionString` in `Info.plist`. Keep the bundle identifier and `SUPublicEDKey` consistent.
2. Run `./test.sh`, `./prepare-dependencies.sh`, and `swift run -c debug EdgeSwipe --self-test`.
3. Run `swift run -c debug EdgeSwipe --probe` for read-only hardware checks. Add `--round-trip` to test normal/fine volume and built-in brightness, cancellation, and keyboard backlight changes with restoration. Built-in round trips require an initial keyboard-grid level.
4. Check the actual menu-bar app on each supported trackpad: four edges, taps, haptic strength, pointer release, typing/multitouch rejection, app exclusions, pause/resume, permission changes, sleep/wake and Bluetooth reconnection. Verify each display backlight separately. See [verification scope](FEATURES.md#verification).

## Build a free DMG

```sh
./build-dmg.sh --local dist/EdgeSwipe-0.4.0-arm64.dmg
shasum -a 256 dist/EdgeSwipe-0.4.0-arm64.dmg > dist/SHA256SUMS
```

`build-app.sh` downloads the pinned Sparkle binary from its official release, verifies SHA-256, embeds the framework, and validates nested signatures. Runtime files never depend on the build directory.

Upload the DMG and checksum to its matching Git tag. State that the build is ad-hoc signed and not notarized, with Apple's [first-launch approval guide](https://support.apple.com/en-us/102445). Ad-hoc updates may require renewing macOS privacy permissions.

## Sign automatic updates

Sparkle starts with version 0.4.0. Users of 0.3.0 install the new DMG manually once.

The publisher's private key is stored at `~/Library/Application Support/EdgeSwipe/UpdateSigning/ed25519.key` with mode 0600. Keep a private backup outside Git. Only its public key is embedded in `Info.plist`. Ordinary builds and CI do not need the private key.

After building the DMG, prepare the signed feed:

```sh
./Tools/prepare-update.sh dist/EdgeSwipe-0.4.0-arm64.dmg \
  https://github.com/winnercup1602/EdgeSwipe/releases/download/v0.4.0/EdgeSwipe-0.4.0-arm64.dmg \
  dist/appcast.xml
```

The script checks the archive's bundle identity, version, feed URL and public key; verifies the archive signature; then signs and verifies the feed. It uses checksum-pinned official Sparkle tools. A missing/mismatched publisher key must be recovered before publishing an update.

Publish the release assets first. Replace `appcast.xml` on the `updates` branch with the signed output, commit and push, then download the public feed and verify it again. Do not edit the XML after signing. Feed and archive signatures are both required. Automatic checking is opt-in, and Sparkle profile submission is disabled.

## Developer ID distribution

With a Developer ID Application identity and a Keychain notarization profile:

```sh
EDGESWIPE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
EDGESWIPE_NOTARY_PROFILE='edgeswipe-notary' \
./build-dmg.sh --release
```

The app build re-signs Sparkle's nested components while preserving their entitlements. The DMG script signs, submits to Apple, attaches the notarization ticket and validates the result. This path requires the publisher's credentials and separate clean-account installation testing.
