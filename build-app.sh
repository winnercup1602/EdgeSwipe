#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
scratch="$project_dir/.build/release-build"
output="${1:-$project_dir/dist/EdgeSwipe.app}"
sign_identity="${EDGESWIPE_SIGN_IDENTITY:-}"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$project_dir/Info.plist")"

if [[ "$(uname -m)" != arm64 || "$output" != *.app ]]; then
    printf 'Build on an Apple Silicon Mac and use an .app output path.\n' >&2
    exit 1
fi
if [[ -e "$output" || -L "$output" ]]; then
    existing_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$output/Contents/Info.plist" 2>/dev/null || true)
    if [[ -L "$output" || "$existing_id" != "$bundle_id" ]]; then
        printf 'Output exists and does not match this bundle identifier: %s\n' "$output" >&2
        exit 1
    fi
fi

swift build --package-path "$project_dir" --scratch-path "$scratch" -c release --product EdgeSwipe
bin_dir="$(swift build --package-path "$project_dir" --scratch-path "$scratch" -c release --show-bin-path)"
mkdir -p "$(dirname "$output")"
staging="$(mktemp -d "$(dirname "$output")/.edgeswipe-bundle.XXXXXXXX")"
trap 'rm -rf "$staging"' EXIT
bundle="$staging/EdgeSwipe.app"
iconset="$staging/EdgeSwipe.iconset"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$project_dir/Assets/EdgeSwipe.png" \
        --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$project_dir/Assets/EdgeSwipe.png" \
        --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$iconset" --output "$bundle/Contents/Resources/EdgeSwipe.icns"
install -m 644 "$project_dir/LICENSE" "$bundle/Contents/Resources/"
install -m 755 "$bin_dir/EdgeSwipe" "$bundle/Contents/MacOS/EdgeSwipe"
install -m 644 "$project_dir/Info.plist" "$bundle/Contents/Info.plist"
plutil -lint "$bundle/Contents/Info.plist"
if [[ -n "$sign_identity" ]]; then
    codesign --force --sign "$sign_identity" --options runtime --timestamp "$bundle"
else
    codesign --force --sign - "$bundle"
fi
codesign --verify --strict "$bundle"
if [[ -e "$output" ]]; then
    mv "$output" "$staging/previous.app"
fi
if ! mv "$bundle" "$output"; then
    if [[ -e "$staging/previous.app" ]]; then mv "$staging/previous.app" "$output"; fi
    exit 1
fi
codesign --verify --strict "$output"
printf '%s\n' "$output"
