# RemindersOverlay

A small native macOS menu-bar app that pops up a full-screen (or minimized
sidebar) overlay of today's incomplete Apple Reminders, using EventKit
directly (no AppleScript/Automation permissions involved).

## Behavior

- Reminders due at/before 9am, or with no specific time, are "morning"
  reminders: always shown as soon as anything is checked, including at
  launch.
- Everything else pops up exactly at its own scheduled due time.
- A "Later Today" section (collapsed by default) previews anything due
  later today, including things quick-added from within the overlay.
- Listens for live changes to Reminders (`EKEventStoreChanged`) and for
  wake-from-sleep, so it stays in sync even if something is added/edited
  directly in Reminders.app or synced in from another device.
- Cmd+R while the overlay is focused (or "Check Reminders Now" in the menu
  bar) forces an immediate manual refresh.

## Requirements

- macOS 13+ (uses `EKEventStore.requestFullAccessToReminders` on macOS 14+,
  falls back to the older `requestAccess` API on macOS 13).
- Xcode Command Line Tools (`xcode-select --install`) -- no full Xcode
  install needed, `swiftc` from the Command Line Tools is enough.

## Building and installing

```sh
./build.sh
```

This compiles the app, assembles `/Applications/RemindersOverlay.app`, and
ad-hoc code-signs it. Launch it once with:

```sh
open /Applications/RemindersOverlay.app
```

The first launch will prompt for Reminders access -- approve it.

**Note on ad-hoc signing:** every time you rerun `build.sh`, the app gets a
new ad-hoc signature, which macOS treats as a new app for permission
purposes. That means each rebuild resets the Reminders permission grant and
you'll need to approve the access prompt again. This is expected; it's not
an error.

## Running at login

To have it launch automatically at login (in the background, no Dock icon,
since it's an accessory/menu-bar-only app):

```sh
cp com.riasubramanian.remindersoverlay.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.riasubramanian.remindersoverlay.plist
```

To undo:

```sh
launchctl bootout gui/$(id -u)/com.riasubramanian.remindersoverlay
rm ~/Library/LaunchAgents/com.riasubramanian.remindersoverlay.plist
```

## Menu bar controls

Click the checklist icon in the menu bar for:
- **Check Reminders Now** -- manual refresh, shows everything outstanding
  regardless of schedule (same as Cmd+R while the overlay is focused).
- **Toggle Minimize** -- shrink/restore the overlay.
- **Quit**.

## Project layout

- `main.swift` -- app entry point.
- `AppDelegate.swift` -- menu bar setup, time-of-day scheduling, sleep/wake
  and live-change handling.
- `ReminderScheduling.swift` -- shared "is this reminder eligible to show
  right now" logic, used by both the scheduler and the overlay's own
  active/later split.
- `ReminderStore.swift` -- EventKit wrapper (fetch, complete, add).
- `OverlayWindowController.swift` -- the overlay's `NSWindow` management,
  including the separate invisible full-screen window used to block clicks
  elsewhere on screen while not minimized.
- `OverlayViewModel.swift` / `OverlayContentView.swift` -- SwiftUI view
  model and UI.
- `Info.plist` -- app bundle metadata (bundle ID, `NSRemindersUsageDescription`,
  `LSUIElement`).
