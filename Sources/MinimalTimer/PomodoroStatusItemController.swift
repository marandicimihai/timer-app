import AppKit
import Combine
import SwiftUI

@MainActor
final class PomodoroStatusItemController: NSObject, ObservableObject {
    private let controller: TimerAppController
    private let preferences: MenuBarPreferences
    private weak var detailWindowCoordinator: DetailWindowCoordinator?
    private var statusItem: NSStatusItem?
    private let popover: NSPopover
    private let hostingController: NSHostingController<PomodoroPopoverView>
    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false

    init(
        controller: TimerAppController,
        preferences: MenuBarPreferences,
        detailWindowCoordinator: DetailWindowCoordinator
    ) {
        self.controller = controller
        self.preferences = preferences
        self.detailWindowCoordinator = detailWindowCoordinator
        hostingController = NSHostingController(
            rootView: PomodoroPopoverView(controller: controller)
        )
        let popover = NSPopover()
        self.popover = popover
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 280, height: 170)
        popover.contentViewController = hostingController
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        createStatusItem()

        Publishers.CombineLatest4(
            preferences.$showsPomodoroIcon,
            controller.pomodoro.$activePhase,
            controller.pomodoro.$completedPhase,
            controller.pomodoro.$isAwaitingNextPhase
        )
            .sink { [weak self] preferenceEnabled, phase, completedPhase, isAwaitingNextPhase in
                self?.updateStatusItem(
                    preferenceEnabled: preferenceEnabled,
                    phase: phase,
                    completedPhase: completedPhase,
                    isAwaitingNextPhase: isAwaitingNextPhase
                )
            }
            .store(in: &cancellables)

        controller.$currentDate
            .sink { [weak self] date in
                guard let self, let phase = controller.pomodoro.activePhase else { return }
                updateIcon(at: date, phase: phase)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .minimalTimerActivityPopoverDidOpen)
            .sink { [weak self] _ in
                self?.closePopover()
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(
        preferenceEnabled: Bool,
        phase: PomodoroPhase?,
        completedPhase: PomodoroPhase?,
        isAwaitingNextPhase: Bool
    ) {
        let displaysIcon = Self.shouldDisplayIcon(
            activePhase: phase,
            isAwaitingNextPhase: isAwaitingNextPhase
        )
        if Self.shouldClosePopover(
            preferenceEnabled: preferenceEnabled,
            displaysIcon: displaysIcon
        ), popover.isShown {
            popover.performClose(nil)
        }
        statusItem?.isVisible = Self.shouldReserveStatusItem(preferenceEnabled: preferenceEnabled)

        guard let button = statusItem?.button else { return }
        button.isEnabled = preferenceEnabled && displaysIcon

        guard preferenceEnabled, displaysIcon else {
            button.image = nil
            button.toolTip = nil
            button.setAccessibilityValue("Inactive")
            return
        }

        updateIcon(
            at: controller.currentDate,
            phase: phase,
            completedPhase: completedPhase
        )
    }

    private func createStatusItem() {
        precondition(statusItem == nil, "Pomodoro status item must only be created once")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusBar.system.thickness)
        guard let button = item.button else {
            NSStatusBar.system.removeStatusItem(item)
            return
        }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.imagePosition = .imageOnly
        button.toolTip = "Pomodoro"
        button.setAccessibilityLabel("Pomodoro timer")
        statusItem = item
        updateStatusItem(
            preferenceEnabled: preferences.showsPomodoroIcon,
            phase: controller.pomodoro.activePhase,
            completedPhase: controller.pomodoro.completedPhase,
            isAwaitingNextPhase: controller.pomodoro.isAwaitingNextPhase
        )
    }

    static func shouldReserveStatusItem(preferenceEnabled: Bool) -> Bool {
        preferenceEnabled
    }

    static func shouldClosePopover(
        preferenceEnabled: Bool,
        displaysIcon: Bool
    ) -> Bool {
        !preferenceEnabled || !displaysIcon
    }

    static func shouldDisplayIcon(
        activePhase: PomodoroPhase?,
        isAwaitingNextPhase: Bool
    ) -> Bool {
        activePhase != nil || isAwaitingNextPhase
    }

    private func updateIcon(
        at date: Date,
        phase: PomodoroPhase?,
        completedPhase: PomodoroPhase? = nil
    ) {
        guard let button = statusItem?.button else { return }
        if let phase {
            let progress = controller.pomodoro.progress(at: date)
            let percentage = Int(PomodoroStatusIconRenderer.normalized(progress) * 100)
            button.image = PomodoroStatusIconRenderer.progressImage(progress: progress)
            button.toolTip = "\(phase.title) Pomodoro — \(percentage)%"
            button.setAccessibilityValue("\(percentage) percent")
        } else {
            button.image = PomodoroStatusIconRenderer.waitingImage()
            if let completedPhase {
                button.toolTip = "\(completedPhase.title) complete — \(completedPhase.next.title) ready"
                button.setAccessibilityValue(
                    "\(completedPhase.title) complete, \(completedPhase.next.title) ready"
                )
            } else {
                button.toolTip = "Pomodoro"
                button.setAccessibilityValue("Ready")
            }
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard statusItem?.button != nil else { return }
        if popover.isShown {
            popover.performClose(sender)
            return
        }

        detailWindowCoordinator?.cancelPendingFocus()
        NotificationCenter.default.post(name: .minimalTimerPomodoroPopoverWillOpen, object: self)
        DispatchQueue.main.async { [weak self] in
            guard let self, let button = statusItem?.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }
}

extension Notification.Name {
    static let minimalTimerActivityPopoverDidOpen = Notification.Name(
        "MinimalTimer.activityPopoverDidOpen"
    )
    static let minimalTimerPomodoroPopoverWillOpen = Notification.Name(
        "MinimalTimer.pomodoroPopoverWillOpen"
    )
}

enum PomodoroStatusIconRenderer {
    static let imageSize = NSSize(width: 16, height: 16)

    static func normalized(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(1, max(0, progress))
    }

    static func progressImage(progress: Double) -> NSImage {
        let value = normalized(progress)
        let image = NSImage(size: imageSize, flipped: false) { rect in
            let circleRect = drawOutline(in: rect)
            let center = NSPoint(x: circleRect.midX, y: circleRect.midY)
            let radius = min(circleRect.width, circleRect.height) / 2

            guard value > 0 else { return true }
            NSColor.black.setFill()
            let fill = NSBezierPath()
            fill.move(to: center)
            fill.line(to: NSPoint(x: center.x, y: center.y + radius))
            fill.appendArc(
                withCenter: center,
                radius: radius - 1.4,
                startAngle: 90,
                endAngle: 90 - (360 * value),
                clockwise: true
            )
            fill.close()
            fill.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    static func waitingImage() -> NSImage {
        let image = NSImage(size: imageSize, flipped: false) { rect in
            let circleRect = drawOutline(in: rect)
            let checkmark = NSBezierPath()
            checkmark.move(
                to: NSPoint(
                    x: circleRect.minX + circleRect.width * 0.25,
                    y: circleRect.minY + circleRect.height * 0.50
                )
            )
            checkmark.line(
                to: NSPoint(
                    x: circleRect.minX + circleRect.width * 0.43,
                    y: circleRect.minY + circleRect.height * 0.31
                )
            )
            checkmark.line(
                to: NSPoint(
                    x: circleRect.minX + circleRect.width * 0.76,
                    y: circleRect.minY + circleRect.height * 0.69
                )
            )
            checkmark.lineWidth = 1.7
            checkmark.lineCapStyle = .round
            checkmark.lineJoinStyle = .round
            NSColor.black.setStroke()
            checkmark.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawOutline(in rect: NSRect) -> NSRect {
        let circleRect = rect.insetBy(dx: 2.25, dy: 2.25)
        NSColor.black.setStroke()
        let outline = NSBezierPath(ovalIn: circleRect)
        outline.lineWidth = 1.4
        outline.stroke()
        return circleRect
    }
}
