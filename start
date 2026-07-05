#!/bin/bash
# One-shot setup: build, install, launch, and optionally enable launch-at-login.
set -e
cd "$(dirname "$0")"

./build.sh

echo ""
echo "Launching RemindersOverlay..."
open /Applications/RemindersOverlay.app
echo "Approve the Reminders access prompt when it appears (every rebuild resets this -- see README)."

LABEL="com.remindersoverlay.app"
PLIST_NAME="$LABEL.plist"
DEST="$HOME/Library/LaunchAgents/$PLIST_NAME"

echo ""
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
    echo "Launch-at-login is already enabled for RemindersOverlay."
else
    read -p "Launch RemindersOverlay automatically at login from now on? [y/N] " answer
    case "$answer" in
        [yY]|[yY][eE][sS])
            mkdir -p "$HOME/Library/LaunchAgents"
            cp "$PLIST_NAME" "$DEST"
            launchctl bootstrap "gui/$(id -u)" "$DEST"
            echo "Launch-at-login enabled."
            echo "To undo later: launchctl bootout gui/\$(id -u)/$LABEL && rm \"$DEST\""
            ;;
        *)
            echo "Skipped. Run this script again anytime to enable it."
            ;;
    esac
fi

echo ""
echo "Done."
