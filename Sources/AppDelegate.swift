import Cocoa
import EventKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayController: OverlayWindowController?
    private let store = ReminderStore()
    private var scheduledTimers: [Timer] = []
    private var eventStoreChangeWorkItem: DispatchWorkItem?
    // Set by the "Open" menu action so the overlay stays visible (even with
    // zero reminders) until the user dismisses it themselves, instead of an
    // automatic check closing it again just because nothing's eligible yet.
    private var keepOpenRegardless = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        // The overlay's window is set to appear on every Space
        // (.canJoinAllSpaces), including its full-screen click-blocker --
        // without this, swiping to a different desktop to do unrelated work
        // would still show the same full-screen blocking overlay there.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSpaceChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        // Fires whenever Reminders' underlying data changes for any reason --
        // edits made directly in Reminders.app, iCloud sync from another
        // device, etc. -- not just changes made through this app. Without
        // this, a reminder added elsewhere with an already-past due time
        // would just sit unnoticed until the next unrelated trigger.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEventStoreChanged),
            name: .EKEventStoreChanged,
            object: store.eventStore
        )
        performCheck(respectSchedule: true)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Reminders Overlay")

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open", action: #selector(openOverlayNow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let checkItem = NSMenuItem(title: "Check Reminders Now", action: #selector(checkRemindersNow), keyEquivalent: "r")
        checkItem.target = self
        menu.addItem(checkItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // Timers never fire while the Mac is asleep. A one-shot Timer whose fire
    // date already passed fires almost immediately once the run loop resumes
    // on wake, which covers most cases on its own -- but we also force an
    // explicit check + reschedule here so a long sleep (spanning multiple
    // missed trigger times) can't leave anything stuck unshown.
    @objc private func handleWake() {
        performCheck(respectSchedule: true)
    }

    @objc private func handleSpaceChange() {
        overlayController?.minimizeForSpaceChange()
    }

    // EventKit can post EKEventStoreChanged in quick bursts (e.g. during an
    // iCloud sync with several edits), so debounce down to a single check.
    @objc private func handleEventStoreChanged() {
        eventStoreChangeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performCheck(respectSchedule: true)
        }
        eventStoreChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    @objc private func checkRemindersNow() {
        performCheck(respectSchedule: false)
    }

    @objc private func openOverlayNow() {
        keepOpenRegardless = true
        store.requestAccess { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                print("[RemindersOverlay] Reminders access not granted.")
                return
            }
            self.store.fetchTodayIncomplete { all in
                self.handle(all: all, shouldShow: true)
                self.scheduleUpcomingTriggers(all: all)
            }
        }
    }

    @objc private func scheduledTimerFired() {
        performCheck(respectSchedule: true)
    }

    // The overlay itself displays both "active" (eligible now) reminders and
    // a condensed "later today" preview of everything else, so we always
    // hand it the full list -- only whether to show/hide the overlay window
    // at all is gated by whether anything is actually eligible right now.
    private func performCheck(respectSchedule: Bool) {
        store.requestAccess { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                print("[RemindersOverlay] Reminders access not granted.")
                return
            }
            self.store.fetchTodayIncomplete { all in
                let now = Date()
                let eligibleNow = all.filter { ReminderScheduling.isEligibleNow($0, now: now) }
                let shouldShow = respectSchedule ? !eligibleNow.isEmpty : !all.isEmpty
                self.handle(all: all, shouldShow: shouldShow || self.keepOpenRegardless)
                self.scheduleUpcomingTriggers(all: all)
            }
        }
    }

    private func handle(all: [EKReminder], shouldShow: Bool) {
        if !shouldShow {
            overlayController?.close()
            overlayController = nil
            return
        }
        if overlayController == nil {
            overlayController = OverlayWindowController(
                store: store,
                onDismiss: { [weak self] in
                    self?.overlayController?.close()
                    self?.overlayController = nil
                    self?.keepOpenRegardless = false
                    // Covers reminders quick-added (with a later due time) from
                    // within the overlay and then dismissed before that time --
                    // without this, the timer set built from the last automatic
                    // check wouldn't know about them yet.
                    self?.refreshSchedule()
                },
                onRefresh: { [weak self] in
                    self?.checkRemindersNow()
                }
            )
        }
        overlayController?.update(reminders: all)
        overlayController?.showWindow(nil)
    }

    // MARK: - Time-of-day scheduling

    private func scheduleUpcomingTriggers(all reminders: [EKReminder]) {
        scheduledTimers.forEach { $0.invalidate() }
        scheduledTimers.removeAll()

        let now = Date()
        var fireDates = Set<Date>()
        for reminder in reminders {
            guard let threshold = ReminderScheduling.eligibilityThreshold(for: reminder), threshold > now else { continue }
            fireDates.insert(threshold)
        }

        for date in fireDates {
            let timer = Timer(fireAt: date, interval: 0, target: self, selector: #selector(scheduledTimerFired), userInfo: nil, repeats: false)
            RunLoop.main.add(timer, forMode: .common)
            scheduledTimers.append(timer)
        }
    }

    private func refreshSchedule() {
        store.fetchTodayIncomplete { [weak self] all in
            self?.scheduleUpcomingTriggers(all: all)
        }
    }
}
