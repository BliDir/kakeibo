#!/bin/sh
# Test release through Firebase App Distribution: archives the Release build, exports an
# Ad Hoc ("release-testing") .ipa and uploads it with the Firebase CLI. No Firebase SDK is added
# to the app; Firebase only hosts the .ipa. Setup and tester steps: docs/firebase-distribution.md.
#
# Usage: FIREBASE_APP_ID=1:123:ios:abc scripts/firebase-distribute.sh [options]
#   --testers "a@x.com,b@y.com"   testers to invite (or FIREBASE_TESTERS)
#   --groups  "internal"          tester group aliases (or FIREBASE_GROUPS)
#   --notes   "What to test"      release notes (default: the last commit subject)
#   --build-only                  archive and export, do not upload
#
# Builds the committed HEAD of this checkout and refuses a dirty tree, so a test build always
# matches a commit. The build number is the commit count (always increasing on main); the
# version stays MARKETING_VERSION. Output: build/firebase/Kakeibo.ipa (git-ignored).
#
# Ad Hoc builds install only on iPhones registered in the Apple Developer account. Register new
# testers' UDIDs first, then run this again so the profile includes them.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/firebase"
TEAM=${KAKEIBO_TEAM:-A75X4JPQUW}
TESTERS=${FIREBASE_TESTERS:-}
TESTER_GROUPS=${FIREBASE_GROUPS:-}
NOTES=""
UPLOAD=1

while [ $# -gt 0 ]; do
    case "$1" in
        --testers) TESTERS=$2; shift 2 ;;
        --groups) TESTER_GROUPS=$2; shift 2 ;;
        --notes) NOTES=$2; shift 2 ;;
        --build-only) UPLOAD=0; shift ;;
        -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

cd "$ROOT"
if [ -n "$(git status --porcelain)" ]; then
    echo "The working tree has uncommitted changes. Commit or stash them first." >&2
    exit 1
fi
if [ "$UPLOAD" = 1 ] && [ -z "${FIREBASE_APP_ID:-}" ]; then
    echo "Set FIREBASE_APP_ID (Firebase console > Project settings > Your apps > App ID)." >&2
    exit 1
fi

BUILD_NUMBER=$(git rev-list --count HEAD)
COMMIT=$(git rev-parse --short HEAD)
[ -n "$NOTES" ] || NOTES="$(git log -1 --format=%s) ($COMMIT)"

rm -rf "$OUT"
mkdir -p "$OUT"
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>release-testing</string>
    <key>signingStyle</key><string>automatic</string>
    <key>teamID</key><string>$TEAM</string>
    <key>compileBitcode</key><false/>
    <key>thinning</key><string>&lt;none&gt;</string>
</dict>
</plist>
EOF

echo "Archiving $COMMIT (build $BUILD_NUMBER)…"
xcodebuild archive -scheme Kakeibo -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$OUT/Kakeibo.xcarchive" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" -quiet

echo "Exporting Ad Hoc .ipa…"
xcodebuild -exportArchive \
    -archivePath "$OUT/Kakeibo.xcarchive" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -exportPath "$OUT" \
    -allowProvisioningUpdates -quiet

IPA="$OUT/Kakeibo.ipa"
[ -f "$IPA" ] || { echo "Export produced no Kakeibo.ipa in $OUT" >&2; exit 1; }
echo "Built $IPA"

[ "$UPLOAD" = 1 ] || exit 0

set -- appdistribution:distribute "$IPA" --app "$FIREBASE_APP_ID" --release-notes "$NOTES"
[ -z "$TESTERS" ] || set -- "$@" --testers "$TESTERS"
[ -z "$TESTER_GROUPS" ] || set -- "$@" --groups "$TESTER_GROUPS"

if command -v firebase >/dev/null 2>&1; then
    firebase "$@"
else
    npx --yes firebase-tools "$@"
fi
