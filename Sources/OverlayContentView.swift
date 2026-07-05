import Cocoa
import EventKit
import SwiftUI

// NSCursor.set() only takes effect while this app is the frontmost/active
// application -- macOS silently ignores cursor changes requested by a
// background app, so the pointing-hand cursor won't show while some other
// app is active. An NSView cursor-rect-based approach was tried to work
// around that, but NSViewRepresentable content placed outside a
// ScrollView/LazyVStack never received mouseEntered/cursorUpdate callbacks
// for reasons that resisted diagnosis, and fixing it for every element
// added more complexity than the "cursor while unfocused" polish is worth.
// Reverted to the simple, reliable version: works while focused, silently
// does nothing while some other app is active.
private func setCursor(_ hovering: Bool, _ cursor: NSCursor = .pointingHand) {
    if hovering {
        cursor.set()
    } else {
        NSCursor.arrow.set()
    }
}

private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter
}()

private func dueSubtitle(_ reminder: EKReminder) -> String? {
    guard let comps = reminder.dueDateComponents, comps.hour != nil,
          let date = Calendar.current.date(from: comps) else {
        return nil
    }
    return "Today, \(timeFormatter.string(from: date))"
}

private func isOverdue(_ reminder: EKReminder) -> Bool {
    guard let comps = reminder.dueDateComponents, comps.hour != nil,
          let date = Calendar.current.date(from: comps) else {
        return false
    }
    return date < Date()
}

private func colorForReminder(_ reminder: EKReminder) -> Color {
    guard let calendar = reminder.calendar else { return .accentColor }
    return Color(calendar.color)
}

private func openInReminders(_ reminder: EKReminder) {
    guard let url = URL(string: "x-apple-reminderkit://REMCDReminder/\(reminder.calendarItemIdentifier)") else {
        return
    }
    NSWorkspace.shared.open(url)
}

struct OverlayContentView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        card
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.activeReminders.enumerated()), id: \.element.calendarItemIdentifier) { index, reminder in
                        ReminderRow(
                            reminder: reminder,
                            tintColor: colorForReminder(reminder),
                            isRecentlyAdded: reminder.calendarItemIdentifier == viewModel.recentlyAddedID,
                            onOpen: {
                                openInReminders(reminder)
                                viewModel.minimize()
                            }
                        ) {
                            viewModel.complete(reminder)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        Divider().padding(.leading, 42)
                    }
                    QuickAddRow { title, hour, minute in
                        viewModel.add(title, hour: hour, minute: minute)
                    }

                    if !viewModel.laterReminders.isEmpty {
                        Divider().padding(.top, 8)
                        LaterTodaySection(
                            reminders: viewModel.laterReminders,
                            colorFor: colorForReminder,
                            recentlyAddedID: viewModel.recentlyAddedID,
                            expanded: $viewModel.laterExpanded,
                            onOpen: { reminder in
                                openInReminders(reminder)
                                viewModel.minimize()
                            },
                            onComplete: { viewModel.complete($0) }
                        )
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.15), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.35), radius: 24)
        // Fixed margin (not tied to minimized/full state) so the shadow's
        // blur has room to render without being hard-clipped by the
        // window's own bounds -- that hard clip is what produced small
        // triangular remnants of the shadow poking out near the corners.
        .padding(Self.shadowMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static let shadowMargin: CGFloat = 32

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("TODO")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                Text("\(viewModel.activeReminders.count) remaining")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HeaderIconButton(systemName: viewModel.minimized ? "arrow.up.left.and.arrow.down.right" : "minus") {
                viewModel.toggleMinimize()
            }
            HeaderIconButton(systemName: "xmark") {
                viewModel.close()
            }
        }
        .padding(16)
    }
}

private struct HeaderIconButton: View {
    let systemName: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Color.gray.opacity(hovering ? 0.28 : 0.15))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0; setCursor($0) }
    }
}

private struct QuickAddRow: View {
    let onAdd: (String, Int, Int) -> Void
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 19))
                .foregroundColor(Color.secondary.opacity(0.5))

            TextField("New Reminder", text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($focused)
                .onSubmit { submit(hour: 9, minute: 0) }

            Spacer(minLength: 8)

            TimeChip(label: "9am") { submit(hour: 9, minute: 0) }
            TimeChip(label: "3pm") { submit(hour: 15, minute: 0) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private func submit(hour: Int, minute: Int) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed, hour, minute)
        text = ""
    }
}

private struct TimeChip: View {
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(hovering ? 0.28 : 0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0; setCursor($0) }
    }
}

private struct LaterTodaySection: View {
    let reminders: [EKReminder]
    let colorFor: (EKReminder) -> Color
    let recentlyAddedID: String?
    @Binding var expanded: Bool
    let onOpen: (EKReminder) -> Void
    let onComplete: (EKReminder) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("LATER TODAY")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(reminders.count)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            }
            .onHover { setCursor($0) }

            if expanded {
                ForEach(reminders, id: \.calendarItemIdentifier) { reminder in
                    LaterReminderRow(
                        reminder: reminder,
                        tintColor: colorFor(reminder),
                        isRecentlyAdded: reminder.calendarItemIdentifier == recentlyAddedID,
                        onOpen: { onOpen(reminder) }
                    ) {
                        onComplete(reminder)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

private struct LaterReminderRow: View {
    let reminder: EKReminder
    let tintColor: Color
    let isRecentlyAdded: Bool
    let onOpen: () -> Void
    let onComplete: () -> Void
    @State private var checked = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: {
                checked = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    onComplete()
                }
            }) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(checked ? tintColor : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .onHover { setCursor($0) }

            Text(reminder.title ?? "Untitled")
                .font(.caption)
                .foregroundColor(.secondary)
                .strikethrough(checked)
                .lineLimit(1)

            Spacer()

            if let subtitle = dueSubtitle(reminder) {
                Text(subtitle.replacingOccurrences(of: "Today, ", with: ""))
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(checked ? Color.blue.opacity(0.2) : (isRecentlyAdded ? tintColor.opacity(0.2) : Color.clear))
        .animation(.easeOut(duration: 0.35), value: isRecentlyAdded)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}

private struct ReminderRow: View {
    let reminder: EKReminder
    let tintColor: Color
    let isRecentlyAdded: Bool
    let onOpen: () -> Void
    let onComplete: () -> Void
    @State private var checked = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                checked = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    onComplete()
                }
            }) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundColor(checked ? tintColor : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .onHover { setCursor($0) }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.title ?? "Untitled")
                        .font(.body)
                        .strikethrough(checked)
                        .foregroundColor(checked ? .secondary : .primary)
                    if let subtitle = dueSubtitle(reminder) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(checked ? .secondary : (isOverdue(reminder) ? .red : .secondary))
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpen() }
            .onHover { setCursor($0) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(checked ? Color.blue.opacity(0.2) : (isRecentlyAdded ? tintColor.opacity(0.2) : (hovering ? Color.gray.opacity(0.08) : Color.clear)))
        .animation(.easeOut(duration: 0.35), value: isRecentlyAdded)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
