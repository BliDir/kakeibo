#!/bin/sh
# Runs `swift test` for every local package. Used by Xcode Cloud and runnable locally.
set -eu

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"

for package in KakeiboCore KakeiboScan KakeiboStore; do
    echo "==> swift test: $package"
    swift test --package-path "$REPO_ROOT/Packages/$package"
done
