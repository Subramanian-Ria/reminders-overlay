# RemindersOverlay

A small native macOS menu-bar app that pops up a full-screen (or minimized
sidebar) overlay of today's incomplete Apple Reminders, using EventKit
directly (no AppleScript/Automation permissions involved).

## Behavior

- Every reminder with a specific due time pops up exactly at that time
  (each gets its own scheduled timer). Reminders with no due time at all
  have nothing to schedule against, so they default to always shown as
  soon as anything is checked, including at launch.
- The quick-add row's "9am"/"3pm" buttons are just convenient presets for
  common check-in times -- reminders added that way behave like any other
  timed reminder, nothing special.
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

## Quick start

```sh
./start
```

This builds the app, installs it to `/Applications/RemindersOverlay.app`,
launches it, and asks whether you want it to launch automatically at login
(skips that question if already enabled). Approve the Reminders access
prompt when it appears.

## Building and installing manually

If you just want to rebuild without going through the login-item prompt
each time:

```sh
./build.sh
```

This compiles the app, assembles `/Applications/RemindersOverlay.app`, and
ad-hoc code-signs it. Launch it with:

```sh
open /Applications/RemindersOverlay.app
```

**Note on ad-hoc signing:** every time you rerun `build.sh`, the app gets a
new ad-hoc signature, which macOS treats as a new app for permission
purposes. That means each rebuild resets the Reminders permission grant and
you'll need to approve the access prompt again. This is expected; it's not
an error.

## Running at login

`start` will offer to do this for you. To do it manually instead:

```sh
cp com.remindersoverlay.app.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.remindersoverlay.app.plist
```

To undo:

```sh
launchctl bootout gui/$(id -u)/com.remindersoverlay.app
rm ~/Library/LaunchAgents/com.remindersoverlay.app.plist
```

## Menu bar controls

Click the checklist icon in the menu bar for:
- **Check Reminders Now** -- manual refresh, shows everything outstanding
  regardless of schedule (same as Cmd+R while the overlay is focused).
- **Toggle Minimize** -- shrink/restore the overlay.
- **Quit**.

## Project layout

- `Sources/main.swift` -- app entry point.
- `Sources/AppDelegate.swift` -- menu bar setup, time-of-day scheduling,
  sleep/wake and live-change handling.
- `Sources/ReminderScheduling.swift` -- shared "is this reminder eligible
  to show right now" logic, used by both the scheduler and the overlay's
  own active/later split.
- `Sources/ReminderStore.swift` -- EventKit wrapper (fetch, complete, add).
- `Sources/OverlayWindowController.swift` -- the overlay's `NSWindow`
  management, including the separate invisible full-screen window used to
  block clicks elsewhere on screen while not minimized.
- `Sources/OverlayViewModel.swift` / `Sources/OverlayContentView.swift` --
  SwiftUI view model and UI.
- `Info.plist` -- app bundle metadata (bundle ID, `NSRemindersUsageDescription`,
  `LSUIElement`).
