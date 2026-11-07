#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/edgeswipe-tests.XXXXXXXX")"
trap 'rm -rf "$scratch"' EXIT
swiftc -O "$project_dir"/Sources/GestureCore/*.swift \
    "$project_dir"/Tests/GestureCoreTests/*.swift -o "$scratch/test"
"$scratch/test"
