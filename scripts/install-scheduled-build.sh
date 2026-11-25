#!/bin/sh
# Installs (or removes) the launchd job that makes a Firebase test build of origin/main on this
# Mac twice a week, Monday and Thursday at 10:00. Twice a week because development-signed builds
# from a free Personal Team expire after 7 days; a run missed while the Mac sleeps starts on wake.
# The Mac must be logged in, with Xcode signed in to the Apple account and the Firebase CLI
# logged in. See docs/firebase-distribution.md.
#
# Usage: scripts/install-scheduled-build.sh            install or update, using this repository
#        scripts/install-scheduled-build.sh --run-now  install, then start a build at once
#        scripts/install-scheduled-build.sh --uninstall
set -eu

LABEL=com.blidir.kakeibo.firebase-build
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SUPPORT="$HOME/Library/Application Support/KakeiboBuild"
DOMAIN="gui/$(id -u)"
# The job keeps its own clone (a background job cannot read ~/Documents), fetched from this remote.
REMOTE=$(git -C "$(dirname "$0")/.." remote get-url origin)

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
if [ "${1:-}" = --uninstall ]; then
    rm -f "$PLIST" "$SUPPORT/scheduled-firebase-build.sh"
    rm -rf "$SUPPORT/repo"
    echo "Removed the scheduled Firebase build."
    exit 0
fi

# The job runs a copy of the wrapper, so it works whatever branch the checkout is on.
# The job's clone lives here too: $SUPPORT/repo.
mkdir -p "$SUPPORT" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/KakeiboBuild"
cp "$(dirname "$0")/scheduled-firebase-build.sh" "$SUPPORT/"
chmod +x "$SUPPORT/scheduled-firebase-build.sh"

# launchd starts with a minimal PATH; keep the one that finds node/npx (nvm) and git.
NODE_DIR=$(dirname "$(command -v npx || command -v firebase || echo /usr/bin/true)")
JOB_PATH="$NODE_DIR:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>$SUPPORT/scheduled-firebase-build.sh</string>
        <string>$REMOTE</string>
    </array>
    <key>WorkingDirectory</key><string>$SUPPORT</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key><string>$JOB_PATH</string>
    </dict>
    <key>StartCalendarInterval</key>
    <array>
        <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>10</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Weekday</key><integer>4</integer><key>Hour</key><integer>10</integer><key>Minute</key><integer>0</integer></dict>
    </array>
    <key>StandardOutPath</key><string>$HOME/Library/Logs/KakeiboBuild/launchd.log</string>
    <key>StandardErrorPath</key><string>$HOME/Library/Logs/KakeiboBuild/launchd.log</string>
</dict>
</plist>
EOF

launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Scheduled Firebase build installed: Monday and Thursday 10:00, building origin/main of $REMOTE."
echo "Logs: ~/Library/Logs/KakeiboBuild. Remove with: scripts/install-scheduled-build.sh --uninstall"

if [ "${1:-}" = --run-now ]; then
    launchctl kickstart "$DOMAIN/$LABEL"
    echo "Build started; a notification appears when it finishes."
fi
