#!/bin/bash
# Builds RemindersOverlay.app and installs it to /Applications.
#
# Note: this ad-hoc-signs the app. Each rebuild produces a new signature,
# which resets the Reminders permission grant -- macOS will prompt you to
# approve access to Reminders again after running this.
set -e
cd "$(dirname "$0")"

APP_NAME="RemindersOverlay"
APP_PATH="/Applications/$APP_NAME.app"

echo "Building..."
swiftc -O Sources/main.swift Sources/AppDelegate.swift Sources/ReminderStore.swift Sources/ReminderScheduling.swift \
    Sources/OverlayWindowController.swift Sources/OverlayViewModel.swift Sources/OverlayContentView.swift \
    -o "$APP_NAME" \
    -framework Cocoa -framework EventKit -framework SwiftUI

echo "Assembling app bundle at $APP_PATH..."
pkill -f "$APP_PATH/Contents/MacOS/$APP_NAME" 2>/dev/null || true
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
cp "$APP_NAME" "$APP_PATH/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_PATH/Contents/Info.plist"

echo "Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_PATH"

echo "Done. Launch with: open $APP_PATH"
