import EventKit
import Foundation

// Shared by AppDelegate (deciding when to pop the overlay up / scheduling
// timers) and the overlay's own view model (splitting "active" reminders
// from "later today" ones for display). Keeping one copy avoids the two
// ever disagreeing about what counts as due.
//
// Reminders due at/before 9am, or with no specific time at all, are
// "morning" reminders: always eligible. Everything else becomes eligible
// exactly at its own scheduled due time.
enum ReminderScheduling {
    static func isEligibleNow(_ reminder: EKReminder, now: Date = Date()) -> Bool {
        guard let threshold = eligibilityThreshold(for: reminder) else { return true }
        return now >= threshold
    }

    static func eligibilityThreshold(for reminder: EKReminder) -> Date? {
        guard let comps = reminder.dueDateComponents, let hour = comps.hour,
              let dueDate = Calendar.current.date(from: comps) else {
            return nil
        }
        let minutesSinceMidnight = hour * 60 + (comps.minute ?? 0)
        if minutesSinceMidnight <= 9 * 60 {
            return nil
        }
        return dueDate
    }
}
