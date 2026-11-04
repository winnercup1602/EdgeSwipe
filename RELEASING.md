# Release process

The installer is a read-only DMG containing EdgeSwipe and an Applications folder shortcut. Local packaging and signed distribution are separate modes.

## Build and sign the release

1. Keep the app identifier `io.github.winnercup1602.edgeswipe` and the Developer ID team consistent across public releases. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `Info.plist`.
2. On an Apple Silicon Mac, install an Apple **Developer ID Application** signing identity. Set up a local Keychain profile with `xcrun notarytool store-credentials` using your own Apple notarization credentials. Keep the signing key and Apple credentials in Keychain.
3. Run the following from the repository root.

   ```sh
   ./test.sh
   EDGESWIPE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
   EDGESWIPE_NOTARY_PROFILE='edgeswipe-notary' \
   ./build-dmg.sh --release
   ```

The script signs the app with Hardened Runtime and a timestamp, signs the disk image, submits it to Apple, attaches and validates the notarization ticket, and verifies the resulting DMG.

## Verify and publish

- On a clean Mac account or a second Mac, download and mount the signed DMG, drag the app into Applications, and check Gatekeeper and first launch. Test permissions, gestures, haptics, and the hardware listed in the release notes.
- For subsequent releases, install over the previous signed build and check whether macOS retains the existing access grants.
- Attach the validated DMG to a GitHub release with the corresponding version tag. Label early builds as prereleases and document the devices and OS versions tested.

Use `./build-dmg.sh --local` for a development image that can be checked on the build Mac. The release build requires a valid signing identity and a notarization profile. See [Apple’s packaging guide](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).
