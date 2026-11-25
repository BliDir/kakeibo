#!/bin/sh
# Scheduled Firebase test build (run by launchd; installed by scripts/install-scheduled-build.sh).
# Keeps its own clone in ~/Library/Application Support/KakeiboBuild/repo, because macOS does not
# let a background job read ~/Documents (where the owner's checkout lives). It fetches origin,
# resets the clone to origin/main and runs scripts/firebase-distribute.sh from it, so the owner's
# checkout is never touched. A macOS notification reports the result; the log is in
# ~/Library/Logs/KakeiboBuild.
#
# Usage: scheduled-firebase-build.sh <git remote URL>
set -u

REMOTE=${1:?usage: scheduled-firebase-build.sh <git remote URL>}
SUPPORT="$HOME/Library/Application Support/KakeiboBuild"
CLONE="$SUPPORT/repo"
LOGS="$HOME/Library/Logs/KakeiboBuild"
mkdir -p "$LOGS" "$SUPPORT"
cd "$SUPPORT" || exit 1
LOG="$LOGS/firebase-$(date +%Y-%m-%d-%H%M).log"
LOCK="${TMPDIR:-/tmp}/kakeibo-firebase-build.lock"

notify() { # <title> <message>
    osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

if ! mkdir "$LOCK" 2>/dev/null; then
    echo "Another build is running ($LOCK)." >> "$LOG"
    exit 0
fi
trap 'rm -rf "$LOCK"' EXIT

{
    echo "Kakeibo scheduled Firebase build, $(date)"
    if [ ! -d "$CLONE/.git" ]; then
        echo "Cloning $REMOTE into $CLONE"
        git clone --quiet "$REMOTE" "$CLONE"
    fi &&
    git -C "$CLONE" remote set-url origin "$REMOTE" &&
    git -C "$CLONE" fetch --quiet origin main &&
    git -C "$CLONE" checkout --quiet --detach origin/main &&
    git -C "$CLONE" reset --quiet --hard origin/main &&
    git -C "$CLONE" clean -fdq &&
    echo "main is at $(git -C "$CLONE" log -1 --format='%h %s')" &&
    "$CLONE/scripts/firebase-distribute.sh"
} >> "$LOG" 2>&1
STATUS=$?

# Keep the last 20 logs.
ls -1t "$LOGS"/firebase-*.log 2>/dev/null | tail -n +21 | while read -r old; do rm -f "$old"; done

if [ "$STATUS" = 0 ]; then
    notify "Kakeibo build uploaded" "Install the update from Firebase App Tester on your iPhone."
else
    notify "Kakeibo build failed" "See $(basename "$LOG") in ~/Library/Logs/KakeiboBuild."
fi
exit "$STATUS"
