#!/bin/sh
# Scheduled Firebase test build (run by launchd; installed by scripts/install-scheduled-build.sh).
# Builds the latest origin/main in a temporary worktree, so the owner's checkout, its branch and
# any uncommitted work are never touched, then runs scripts/firebase-distribute.sh from it.
# A macOS notification reports the result; the log is in ~/Library/Logs/KakeiboBuild.
#
# Usage: scheduled-firebase-build.sh <path to the kakeibo repository>
set -u

REPO=${1:?usage: scheduled-firebase-build.sh <repository>}
LOGS="$HOME/Library/Logs/KakeiboBuild"
mkdir -p "$LOGS"
LOG="$LOGS/firebase-$(date +%Y-%m-%d-%H%M).log"
LOCK="${TMPDIR:-/tmp}/kakeibo-firebase-build.lock"

notify() { # <title> <message>
    osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

if ! mkdir "$LOCK" 2>/dev/null; then
    echo "Another build is running ($LOCK)." >> "$LOG"
    exit 0
fi
WORK=$(mktemp -d)
cleanup() {
    git -C "$REPO" worktree remove --force "$WORK/src" >/dev/null 2>&1 || true
    rm -rf "$WORK" "$LOCK"
}
trap cleanup EXIT

{
    echo "Kakeibo scheduled Firebase build, $(date)"
    git -C "$REPO" fetch --quiet origin main &&
    git -C "$REPO" worktree add --quiet --detach "$WORK/src" origin/main &&
    echo "main is at $(git -C "$WORK/src" log -1 --format='%h %s')" &&
    "$WORK/src/scripts/firebase-distribute.sh"
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
