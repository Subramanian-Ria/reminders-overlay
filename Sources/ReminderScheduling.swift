import EventKit
import Foundation

// Shared by AppDelegate (deciding when to pop the overlay up / scheduling
// timers) and the overlay's own view model (splitting "active" reminders
// from "later today" ones for display). Keeping one copy avoids the two
// ever disagreeing about what counts as due.
//
// A reminder with a specific due time becomes eligible exactly at that
// time (each gets its own scheduled Timer -- see scheduleUpcomingTriggers).
// A reminder with no due time at all has nothing to schedule against, so
// it falls back to always eligible, shown as soon as anything is checked.
enum ReminderScheduling {
    static func isEligibleNow(_ reminder: EKReminder, now: Date = Date()) -> Bool {
        guard let threshold = eligibilityThreshold(for: reminder) else { return true }
        return now >= threshold
    }

    static func eligibilityThreshold(for reminder: EKReminder) -> Date? {
        guard let comps = reminder.dueDateComponents, comps.hour != nil,
              let dueDate = Calendar.current.date(from: comps) else {
            return nil
        }
        return dueDate
    }
}
