#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cache="$project_dir/.build/sparkle-tools"
version=2.10.1
checksum=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
archive="$cache/Sparkle-$version.tar.xz"
target="$cache/distribution"
if [[ -f "$target/.edgeswipe-$checksum" ]]; then exit 0; fi
mkdir -p "$cache"
if [[ ! -f "$archive" ]] || ! printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 -c - >/dev/null; then
    curl --fail --location --silent --show-error --connect-timeout 15 --max-time 120 \
        "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" --output "$archive"
fi
printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 -c -
staging="$(mktemp -d "$cache/.tools.XXXXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir "$staging/distribution"
tar -xJf "$archive" -C "$staging/distribution"
touch "$staging/distribution/.edgeswipe-$checksum"
if [[ -e "$target" ]]; then mv "$target" "$staging/previous"; fi
mv "$staging/distribution" "$target"
