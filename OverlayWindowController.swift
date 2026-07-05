import Cocoa
import EventKit
import QuartzCore
import SwiftUI

// Plain NSWindow defaults canBecomeKey/canBecomeMain to false when its
// styleMask is .borderless, which breaks reliable click handling, hover
// cursor tracking, and keyboard focus for the SwiftUI content inside it.
final class OverlayPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // This is an accessory app with no main menu, so there's no NSMenuItem
    // to attach a standard Cmd+R key-equivalent to. performKeyEquivalent(with:)
    // is called on the key window for any key event before normal keyDown
    // dispatch, which is the standard way to catch a shortcut like this
    // without a menu bar.
    var onRefreshShortcut: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "r" {
            onRefreshShortcut?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class OverlayWindowController: NSWindowController {
    private let store: ReminderStore
    private let onDismiss: () -> Void
    private let onRefresh: () -> Void
    private let viewModel = OverlayViewModel()

    // A separate, invisible, full-screen window that exists only while not
    // minimized, purely to swallow clicks elsewhere on screen. Keeping this
    // apart from the visible card window means the card's own resize is a
    // small, single-animation-system transition (driven only by
    // NSAnimationContext) instead of fighting a second, independent SwiftUI
    // animation trying to track the same resize -- that mismatch was the
    // source of the earlier "expand"/non-smooth glitches.
    private var blockerWindow: NSWindow?

    private static let fullSize = NSSize(width: 380, height: 560)
    private static let miniSize = NSSize(width: 340, height: 420)
    private static let miniMargin: CGFloat = 16
    private let resizeDuration: TimeInterval = 0.25

    init(store: ReminderStore, onDismiss: @escaping () -> Void, onRefresh: @escaping () -> Void) {
        self.store = store
        self.onDismiss = onDismiss
        self.onRefresh = onRefresh

        let window = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: Self.fullSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true

        super.init(window: window)

        window.onRefreshShortcut = { [weak self] in
            self?.onRefresh()
        }

        viewModel.onToggleMinimize = { [weak self] in
            self?.applyFrame(animated: true)
            self?.updateBlockerWindow()
        }
        viewModel.onComplete = { [weak self] reminder in
            self?.completeReminder(reminder)
        }
        viewModel.onClose = { [weak self] in
            self?.onDismiss()
        }
        viewModel.onAdd = { [weak self] title, hour, minute in
            self?.addReminder(title: title, hour: hour, minute: minute)
        }

        let hostingView = NSHostingView(rootView: OverlayContentView(viewModel: viewModel))
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = window.contentLayoutRect
        window.contentView = hostingView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(reminders: [EKReminder]) {
        viewModel.setReminders(reminders)
    }

    func toggleMinimizeFromMenu() {
        viewModel.toggleMinimize()
    }

    private func completeReminder(_ reminder: EKReminder) {
        store.complete(reminder)
        viewModel.remove(reminder)
        if viewModel.activeReminders.isEmpty {
            onDismiss()
        }
    }

    private func addReminder(title: String, hour: Int, minute: Int) {
        store.addReminder(title: title, hour: hour, minute: minute) { [weak self] reminder in
            guard let self = self, let reminder = reminder else { return }
            self.viewModel.insert(reminder)
        }
    }

    override func showWindow(_ sender: Any?) {
        applyFrame(animated: false)
        updateBlockerWindow()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func close() {
        blockerWindow?.orderOut(nil)
        blockerWindow = nil
        super.close()
    }

    private func applyFrame(animated: Bool) {
        guard let window = window, let screen = NSScreen.main else { return }
        let size = viewModel.minimized ? Self.miniSize : Self.fullSize
        let target: NSRect
        if viewModel.minimized {
            let visible = screen.visibleFrame
            target = NSRect(
                x: visible.maxX - size.width - Self.miniMargin,
                y: visible.maxY - size.height - Self.miniMargin,
                width: size.width,
                height: size.height
            )
        } else {
            let frame = screen.frame
            target = NSRect(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }

        guard animated else {
            window.setFrame(target, display: true, animate: false)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = self.resizeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(target, display: true)
        }
    }

    private func updateBlockerWindow() {
        guard let screen = NSScreen.main else { return }
        if viewModel.minimized {
            blockerWindow?.orderOut(nil)
            return
        }
        if blockerWindow == nil {
            let blocker = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            blocker.isOpaque = false
            blocker.backgroundColor = .clear
            blocker.level = .floating
            blocker.hasShadow = false
            blocker.isReleasedWhenClosed = false
            blocker.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            blockerWindow = blocker
        }
        blockerWindow?.setFrame(screen.frame, display: true)
        blockerWindow?.orderFront(nil)
        window?.orderFront(nil)
    }
}
