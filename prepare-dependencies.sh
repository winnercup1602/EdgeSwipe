#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
version=2.10.1
checksum=4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a
vendor="$project_dir/Vendor/Sparkle.xcframework"
if [[ -f "$vendor/.edgeswipe-$checksum" ]]; then exit 0; fi
mkdir -p "$project_dir/Vendor"
staging="$(mktemp -d "$project_dir/Vendor/.sparkle.XXXXXXXX")"
trap 'rm -rf "$staging"' EXIT
curl --fail --location --silent --show-error --connect-timeout 15 --max-time 120 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-for-Swift-Package-Manager.zip" \
    --output "$staging/Sparkle.zip"
printf '%s  %s\n' "$checksum" "$staging/Sparkle.zip" | shasum -a 256 -c -
ditto -xk "$staging/Sparkle.zip" "$staging/unpacked"
test -d "$staging/unpacked/Sparkle.xcframework"
touch "$staging/unpacked/Sparkle.xcframework/.edgeswipe-$checksum"
if [[ -e "$vendor" ]]; then mv "$vendor" "$staging/previous.xcframework"; fi
mv "$staging/unpacked/Sparkle.xcframework" "$vendor"
