import EventKit
import Foundation

final class ReminderStore {
    let eventStore = EKEventStore()

    func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToReminders { granted, error in
                if let error = error {
                    print("[RemindersOverlay] Access request error: \(error)")
                }
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            eventStore.requestAccess(to: .reminder) { granted, error in
                if let error = error {
                    print("[RemindersOverlay] Access request error: \(error)")
                }
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    // EventKit's predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)
    // silently excludes reminders whose due date has no time-of-day component (i.e. a
    // plain date picked without a specific time), which is the common case when you
    // set a reminder's date from the Reminders UI without also setting a time. So we
    // fetch all incomplete reminders and filter by date ourselves.
    func fetchTodayIncomplete(completion: @escaping ([EKReminder]) -> Void) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            completion([])
            return
        }
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        eventStore.fetchReminders(matching: predicate) { reminders in
            let todays = (reminders ?? []).filter { reminder in
                guard let components = reminder.dueDateComponents,
                      let due = calendar.date(from: components) else {
                    return false
                }
                return due >= startOfDay && due < endOfDay
            }
            DispatchQueue.main.async {
                completion(todays)
            }
        }
    }

    func complete(_ reminder: EKReminder) {
        reminder.isCompleted = true
        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            print("[RemindersOverlay] Failed to save completed reminder: \(error)")
        }
    }

    func addReminder(title: String, hour: Int, minute: Int, completion: @escaping (EKReminder?) -> Void) {
        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            print("[RemindersOverlay] No default calendar for new reminders.")
            completion(nil)
            return
        }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = calendar
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        reminder.dueDateComponents = comps
        do {
            try eventStore.save(reminder, commit: true)
            completion(reminder)
        } catch {
            print("[RemindersOverlay] Failed to add reminder: \(error)")
            completion(nil)
        }
    }
}
