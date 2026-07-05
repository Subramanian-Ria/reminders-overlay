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

    // Padded on each dimension by 2x OverlayContentView.shadowMargin, since
    // the card's own shadow needs room around it that isn't hard-clipped by
    // the window's exact bounds.
    private static let shadowPadding = OverlayContentView.shadowMargin * 2
    private static let fullSize = NSSize(width: 380 + shadowPadding, height: 560 + shadowPadding)
    private static let miniSize = NSSize(width: 340 + shadowPadding, height: 420 + shadowPadding)
    private static let miniMargin: CGFloat = 16
    // Snap back to the default corner if released within this distance of
    // it -- large and quick to settle, so it reads as "magnetic" rather
    // than something you have to precisely aim for.
    private static let snapDistance: CGFloat = 180
    private let resizeDuration: TimeInterval = 0.25
    private var dragSettleWorkItem: DispatchWorkItem?

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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove),
            name: NSWindow.didMoveNotification,
            object: window
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(reminders: [EKReminder]) {
        viewModel.setReminders(reminders)
    }

    func minimizeForSpaceChange() {
        viewModel.minimize()
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

    private func minimizedOrigin(on screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        return NSPoint(
            x: visible.maxX - Self.miniSize.width - Self.miniMargin,
            y: visible.maxY - Self.miniSize.height - Self.miniMargin
        )
    }

    private func applyFrame(animated: Bool) {
        guard let window = window, let screen = NSScreen.main else { return }
        // Only draggable while minimized -- the full-size card is centered
        // and covers the whole screen's click-blocker, so there's no
        // reason to reposition it.
        window.isMovableByWindowBackground = viewModel.minimized
        let size = viewModel.minimized ? Self.miniSize : Self.fullSize
        let target: NSRect
        if viewModel.minimized {
            let origin = minimizedOrigin(on: screen)
            target = NSRect(origin: origin, size: size)
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

    // Fires continuously while the user drags the minimized panel (AppKit's
    // isMovableByWindowBackground handles the drag itself; this just
    // observes where it ends up). After motion pauses, as a proxy for
    // "drag ended" since there's no dedicated end-of-drag notification for
    // this kind of drag, snaps back to the default corner if released
    // within range.
    @objc private func windowDidMove() {
        guard viewModel.minimized else { return }
        dragSettleWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.snapToDefaultCornerIfClose()
        }
        dragSettleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func snapToDefaultCornerIfClose() {
        guard viewModel.minimized, let window = window, let screen = NSScreen.main else { return }
        let target = minimizedOrigin(on: screen)
        let distance = hypot(window.frame.origin.x - target.x, window.frame.origin.y - target.y)
        guard distance < Self.snapDistance, distance > 0 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrameOrigin(target)
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
