#!/bin/sh
# Upgrade check on the iOS Simulator (B-09): installs an older release, gives it a populated
# store, installs the current build over it (as an App Store update would) and prints what the
# upgraded store holds. Screenshots of both launches go to the output folder.
#
# Usage: scripts/upgrade-check.sh [old commit] [output folder]
#   old commit: the release to upgrade from (default 0a410e6, the last v1.0 commit on main)
#   output folder: default ./build/upgrade-check
#
# The old app is given Packages/KakeiboStore/Tests/KakeiboStoreTests/Fixtures/v2-store (the
# store v1.0 writes: three November 2026 expenses, one with a photo) and a receipt photo.
# Runs on a temporary simulator, which is deleted at the end. Never touches a real iPhone.
set -eu

OLD=${1:-0a410e6}
OUT=${2:-build/upgrade-check}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUNDLE=com.blidir.kakeibo
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
WORK=$(mktemp -d)

UDID=$(xcrun simctl create "Kakeibo upgrade check" "iPhone 17")
cleanup() {
    xcrun simctl shutdown "$UDID" 2>/dev/null || true
    xcrun simctl delete "$UDID" 2>/dev/null || true
    git -C "$ROOT" worktree remove --force "$WORK/old" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT
xcrun simctl boot "$UDID"

build() { # <source folder> <derived data>
    (cd "$1" && xcodebuild build -scheme Kakeibo -configuration Debug \
        -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$2" -quiet)
}

echo "Building $OLD and the current tree…"
git -C "$ROOT" worktree add -q --detach "$WORK/old" "$OLD"
build "$WORK/old" "$WORK/dd-old"
build "$ROOT" "$WORK/dd-new"
APP=Build/Products/Debug-iphonesimulator/Kakeibo.app

# The old release, first launch (creates the store), then a populated store and a photo.
xcrun simctl install "$UDID" "$WORK/dd-old/$APP"
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null; sleep 4; xcrun simctl terminate "$UDID" "$BUNDLE"
SUPPORT="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)/Library/Application Support"
FIXTURE="$ROOT/Packages/KakeiboStore/Tests/KakeiboStoreTests/Fixtures/v2-store"
rm -f "$SUPPORT"/default.store*
for suffix in "" -shm -wal; do cp "$FIXTURE/Kakeibo.store$suffix" "$SUPPORT/default.store$suffix"; done
mkdir -p "$SUPPORT/Receipts"
sips -s format jpeg "$ROOT/UITests/sample-receipt.png" \
    --out "$SUPPORT/Receipts/4C0E7B1A-0B2D-4D5E-8F10-1A2B3C4D5E01.jpg" >/dev/null
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null; sleep 5
xcrun simctl io "$UDID" screenshot "$OUT/1-old-ledger.png" >/dev/null 2>&1
xcrun simctl terminate "$UDID" "$BUNDLE"

# The update.
xcrun simctl install "$UDID" "$WORK/dd-new/$APP"
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null; sleep 6
xcrun simctl io "$UDID" screenshot "$OUT/2-new-ledger.png" >/dev/null 2>&1
xcrun simctl terminate "$UDID" "$BUNDLE"

SUPPORT="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)/Library/Application Support"
STORE="$SUPPORT/default.store"
echo "Upgraded store:"
sqlite3 "$STORE" "select '  expenses: ' || count(*) from ZEXPENSE;
                  select '  items: ' || count(*) from ZLINEITEM;
                  select '  photo names: ' || count(*) from ZEXPENSE where ZPHOTOFILENAME is not null;
                  select '  budget months: ' || count(*) from ZBUDGETMONTH;
                  select '  budget template: ' || count(*) from ZBUDGETTEMPLATE;
                  select '  alert intents: ' || count(*) from ZBUDGETALERTINTENT;"
echo "  photo files: $(ls "$SUPPORT/Receipts" | wc -l | tr -d ' ')"
echo "Expected: 3 expenses, 2 items, 1 photo name and file, no budget rows."
echo "Screenshots: $OUT"
