#!/bin/sh
# Xcode Cloud custom step: runs before each xcodebuild action.
# Package tests run once per test action, before the app's test plan is built.
set -eu

if [ "${CI_XCODEBUILD_ACTION:-}" = "build-for-testing" ]; then
    "$(dirname "$0")/test_packages.sh"
fi
