import Cocoa
import Combine
import EventKit
import SwiftUI

final class OverlayViewModel: ObservableObject {
    @Published var reminders: [EKReminder] = []
    @Published var minimized: Bool = false
    @Published var laterExpanded: Bool = false
    @Published var recentlyAddedID: String?

    var onToggleMinimize: (() -> Void)?
    var onComplete: ((EKReminder) -> Void)?
    var onClose: (() -> Void)?
    var onAdd: ((String, Int, Int) -> Void)?

    func setReminders(_ new: [EKReminder]) {
        reminders = new.sorted { a, b in
            let dateA = a.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
            let dateB = b.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
            switch (dateA, dateB) {
            case let (dateA?, dateB?):
                return dateA < dateB
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            default:
                return (a.title ?? "") < (b.title ?? "")
            }
        }
    }

    func remove(_ reminder: EKReminder) {
        withAnimation(.easeInOut(duration: 0.3)) {
            reminders.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
        }
    }

    func insert(_ reminder: EKReminder) {
        withAnimation(.easeInOut(duration: 0.3)) {
            setReminders(reminders + [reminder])
            if !ReminderScheduling.isEligibleNow(reminder) {
                laterExpanded = true
            }
        }
        let id = reminder.calendarItemIdentifier
        recentlyAddedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self, self.recentlyAddedID == id else { return }
            self.recentlyAddedID = nil
        }
    }

    // Reminders due now (or with no time / due before 9am) vs. ones due
    // later today, which are shown as a condensed preview instead of a full
    // interactive row.
    var activeReminders: [EKReminder] {
        reminders.filter { ReminderScheduling.isEligibleNow($0) }
    }

    var laterReminders: [EKReminder] {
        reminders.filter { !ReminderScheduling.isEligibleNow($0) }
    }

    func add(_ title: String, hour: Int, minute: Int) {
        onAdd?(title, hour, minute)
    }

    func toggleMinimize() {
        minimized.toggle()
        onToggleMinimize?()
    }

    func complete(_ reminder: EKReminder) {
        onComplete?(reminder)
    }

    func close() {
        onClose?()
    }
}
