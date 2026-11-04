#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
mode="${1:---local}"
if [[ "$mode" != --local && "$mode" != --release ]] || [[ $# -gt 2 ]]; then
    printf 'Usage: %s [--local|--release] [output.dmg]\n' "$0" >&2
    exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Info.plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$project_dir/Info.plist")"
sign_identity=""
notary_profile=""
name="EdgeSwipe-$version-local-arm64.dmg"
if [[ "$mode" == --release ]]; then
    sign_identity="${EDGESWIPE_SIGN_IDENTITY:?Set EDGESWIPE_SIGN_IDENTITY to a Developer ID Application identity}"
    notary_profile="${EDGESWIPE_NOTARY_PROFILE:?Set EDGESWIPE_NOTARY_PROFILE to a notarytool keychain profile}"
    name="EdgeSwipe-$version-arm64.dmg"
fi
output="${2:-$project_dir/dist/$name}"
if [[ "$output" != *.dmg || -e "$output" || -L "$output" ]]; then
    printf 'Choose a new .dmg output path.\n' >&2
    exit 1
fi

mkdir -p "$(dirname "$output")"
staging="$(mktemp -d "$(dirname "$output")/.edgeswipe-dmg.XXXXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir "$staging/contents"
app="$staging/contents/EdgeSwipe.app"
image="$staging/EdgeSwipe.dmg"
EDGESWIPE_SIGN_IDENTITY="$sign_identity" "$project_dir/build-app.sh" "$app"
ln -s /Applications "$staging/contents/Applications"
hdiutil create -volname EdgeSwipe -srcfolder "$staging/contents" -fs HFS+ -format UDZO "$image"

if [[ "$mode" == --release ]]; then
    if ! codesign -dv --verbose=2 "$app" 2>&1 | grep '^Authority=Developer ID Application:' >/dev/null; then
        printf 'The app must be signed with a Developer ID Application identity.\n' >&2
        exit 1
    fi
    codesign --sign "$sign_identity" --timestamp --identifier "$bundle_id.dmg" "$image"
    xcrun notarytool submit "$image" --keychain-profile "$notary_profile" --wait --output-format json \
        > "$staging/notary.json"
    cat "$staging/notary.json"
    if [[ "$(plutil -extract status raw "$staging/notary.json")" != Accepted ]]; then
        printf 'Apple notarization did not accept this image. See the submission ID above.\n' >&2
        exit 1
    fi
    xcrun stapler staple "$image"
    xcrun stapler validate "$image"
    spctl --assess --type open --context context:primary-signature --verbose "$image"
fi

hdiutil verify "$image"
mv "$image" "$output"
printf '%s\n' "$output"
