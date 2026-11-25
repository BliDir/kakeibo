#!/bin/sh
# Test release through Firebase App Distribution: archives the Release build, exports a signed
# .ipa and uploads it with the Firebase CLI. No Firebase SDK is added to the app; Firebase only
# hosts the .ipa. Setup, tester steps and the scheduled build: docs/firebase-distribution.md.
#
# Usage: scripts/firebase-distribute.sh [options]
#   --testers "a@x.com,b@y.com"   testers to invite (or FIREBASE_TESTERS)
#   --groups  "blidir-team"       tester group aliases (or FIREBASE_GROUPS)
#   --notes   "What to test"      release notes (default: last commit subject and expiry)
#   --build-only                  archive and export, do not upload
#   --development / --adhoc       signing (or KAKEIBO_EXPORT=development|adhoc)
#
# Settings come from Config/firebase-distribution.env; environment variables override them.
# development: free Personal Team, only the owner's registered iPhone, expires after 7 days.
#   The cached Kakeibo team profile is removed first, so each build gets a fresh 7 days.
# adhoc: paid Apple Developer Program, registered iPhones, profile lasts about a year.
#
# Builds the committed HEAD of this checkout and refuses a dirty tree, so a test build always
# matches a commit. The build number is the commit count (always increasing on main); the
# version stays MARKETING_VERSION. Output: build/firebase/Kakeibo.ipa (git-ignored).
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/firebase"
BUNDLE_ID=com.blidir.kakeibo

# Config file first, then any variable already set in the environment wins.
for name in FIREBASE_PROJECT FIREBASE_APP_ID FIREBASE_GROUPS FIREBASE_TESTERS KAKEIBO_EXPORT KAKEIBO_TEAM; do
    eval "[ -z \"\${$name+x}\" ] || saved_$name=\$$name"
done
CONFIG="$ROOT/Config/firebase-distribution.env"
[ ! -f "$CONFIG" ] || . "$CONFIG"
for name in FIREBASE_PROJECT FIREBASE_APP_ID FIREBASE_GROUPS FIREBASE_TESTERS KAKEIBO_EXPORT KAKEIBO_TEAM; do
    eval "[ -z \"\${saved_$name+x}\" ] || $name=\$saved_$name"
done

TEAM=${KAKEIBO_TEAM:-A75X4JPQUW}
TESTERS=${FIREBASE_TESTERS:-}
TESTER_GROUPS=${FIREBASE_GROUPS:-}
EXPORT=${KAKEIBO_EXPORT:-adhoc}
NOTES=""
UPLOAD=1

while [ $# -gt 0 ]; do
    case "$1" in
        --testers) TESTERS=$2; shift 2 ;;
        --groups) TESTER_GROUPS=$2; shift 2 ;;
        --notes) NOTES=$2; shift 2 ;;
        --build-only) UPLOAD=0; shift ;;
        --development) EXPORT=development; shift ;;
        --adhoc) EXPORT=adhoc; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

case "$EXPORT" in
    development) METHOD=debugging ;;
    adhoc) METHOD=release-testing ;;
    *) echo "KAKEIBO_EXPORT must be development or adhoc, not $EXPORT" >&2; exit 2 ;;
esac

cd "$ROOT"
if [ -n "$(git status --porcelain)" ]; then
    echo "The working tree has uncommitted changes. Commit or stash them first." >&2
    exit 1
fi
if [ "$UPLOAD" = 1 ] && [ -z "${FIREBASE_APP_ID:-}" ]; then
    echo "Set FIREBASE_APP_ID in Config/firebase-distribution.env (Firebase console > Project settings > Your apps)." >&2
    exit 1
fi

BUILD_NUMBER=$(git rev-list --count HEAD)
COMMIT=$(git rev-parse --short HEAD)

profile_field() { # <profile file> <key>
    security cms -D -i "$1" 2>/dev/null | plutil -extract "$2" raw -o - - 2>/dev/null
}

if [ "$EXPORT" = development ]; then
    # A cached team profile keeps its original expiry; remove it so Xcode asks Apple for a new one.
    for dir in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
               "$HOME/Library/MobileDevice/Provisioning Profiles"; do
        [ -d "$dir" ] || continue
        for profile in "$dir"/*.mobileprovision; do
            [ -f "$profile" ] || continue
            if [ "$(profile_field "$profile" Name)" = "iOS Team Provisioning Profile: $BUNDLE_ID" ]; then
                echo "Removing cached team profile $(basename "$profile")"
                rm -f "$profile"
            fi
        done
    done
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>$METHOD</string>
    <key>signingStyle</key><string>automatic</string>
    <key>teamID</key><string>$TEAM</string>
    <key>compileBitcode</key><false/>
    <key>thinning</key><string>&lt;none&gt;</string>
</dict>
</plist>
EOF

echo "Archiving $COMMIT (build $BUILD_NUMBER, $EXPORT)…"
xcodebuild archive -scheme Kakeibo -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$OUT/Kakeibo.xcarchive" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" -quiet

echo "Exporting .ipa ($METHOD)…"
xcodebuild -exportArchive \
    -archivePath "$OUT/Kakeibo.xcarchive" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -exportPath "$OUT" \
    -allowProvisioningUpdates -quiet

IPA="$OUT/Kakeibo.ipa"
[ -f "$IPA" ] || { echo "Export produced no Kakeibo.ipa in $OUT" >&2; exit 1; }

(cd "$OUT" && rm -rf ipa && mkdir ipa && cd ipa && unzip -q ../Kakeibo.ipa 'Payload/*/embedded.mobileprovision')
EXPIRES=$(profile_field "$OUT"/ipa/Payload/*.app/embedded.mobileprovision ExpirationDate || true)
rm -rf "$OUT/ipa"
EXPIRES_DAY=$(printf '%s' "${EXPIRES:-unknown}" | cut -c1-10)
echo "Built $IPA (profile expires ${EXPIRES:-unknown})"

[ "$UPLOAD" = 1 ] || exit 0
[ -n "$NOTES" ] || NOTES="$(git log -1 --format=%s) ($COMMIT). Expires $EXPIRES_DAY."

set -- appdistribution:distribute "$IPA" --app "$FIREBASE_APP_ID" --release-notes "$NOTES"
[ -z "${FIREBASE_PROJECT:-}" ] || set -- "$@" --project "$FIREBASE_PROJECT"
[ -z "$TESTERS" ] || set -- "$@" --testers "$TESTERS"
[ -z "$TESTER_GROUPS" ] || set -- "$@" --groups "$TESTER_GROUPS"

if command -v firebase >/dev/null 2>&1; then
    firebase "$@"
else
    npx --yes firebase-tools "$@"
fi
