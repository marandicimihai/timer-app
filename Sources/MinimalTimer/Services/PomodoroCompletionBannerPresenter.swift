import AppKit
import Foundation
@preconcurrency import UserNotifications

struct PomodoroCompletionNotificationCopy: Equatable, Sendable {
    let title: String
    let body: String
    let symbolName: String
    let actionTitle: String
    let nextPhase: PomodoroPhase

    init(phase: PomodoroPhase) {
        title = "\(phase.title) complete"
        nextPhase = phase.next
        actionTitle = "Start \(nextPhase.title)"
        switch phase {
        case .focus:
            body = "Your break is ready when you are."
            symbolName = "checkmark.circle.fill"
        case .break:
            body = "Ready for another focus session?"
            symbolName = "timer.circle.fill"
        }
    }
}

enum PomodoroNotificationPresentationPolicy {
    static var interruptionLevel: UNNotificationInterruptionLevel { .passive }
    static var foregroundOptions: UNNotificationPresentationOptions { [.list] }
}

protocol PomodoroCompletionBannerPresenting: AnyObject, Sendable {
    func presentCompletion(
        for phase: PomodoroPhase,
        startNextPhase: @escaping @MainActor @Sendable () -> Void
    )
}

private final class PomodoroCompletionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class PomodoroCompletionBannerPresenter: NSObject, PomodoroCompletionBannerPresenting, @unchecked Sendable {
    @MainActor private var panel: NSPanel?
    @MainActor private var titleLabel: NSTextField?
    @MainActor private var bodyLabel: NSTextField?
    @MainActor private var iconView: NSImageView?
    @MainActor private var actionButton: NSButton?
    @MainActor private var startNextPhase: (@MainActor @Sendable () -> Void)?
    @MainActor private var dismissalTask: Task<Void, Never>?

    func presentCompletion(
        for phase: PomodoroPhase,
        startNextPhase: @escaping @MainActor @Sendable () -> Void
    ) {
        Task { @MainActor [weak self] in
            self?.showCompletion(for: phase, startNextPhase: startNextPhase)
        }
    }

    @MainActor
    private func showCompletion(
        for phase: PomodoroPhase,
        startNextPhase: @escaping @MainActor @Sendable () -> Void
    ) {
        let panel = panel ?? makePanel()
        updateContent(for: phase)
        self.startNextPhase = startNextPhase
        dismissalTask?.cancel()
        NSSound.beep()

        let screen = screenNearestPointer() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let destination = NSPoint(
            x: visibleFrame.maxX - panel.frame.width - 18,
            y: visibleFrame.maxY - panel.frame.height - 18
        )
        panel.alphaValue = 0
        panel.setFrameOrigin(NSPoint(x: destination.x + 16, y: destination.y))
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(destination)
        }

        dismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.dismissPanel()
        }
    }

    @MainActor
    private func dismissPanel() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
        startNextPhase = nil
    }

    @MainActor
    private func makePanel() -> NSPanel {
        let panelSize = NSSize(width: 420, height: 96)
        let panel = PomodoroCompletionPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentTintColor = .controlAccentColor
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .semibold)

        let titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor

        let bodyLabel = NSTextField(wrappingLabelWithString: "")
        bodyLabel.font = .systemFont(ofSize: 12)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.maximumNumberOfLines = 2

        let textStack = NSStackView(views: [titleLabel, bodyLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        let actionButton = NSButton(
            title: "",
            target: self,
            action: #selector(startNextPhaseClicked)
        )
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .small
        actionButton.setContentHuggingPriority(.required, for: .horizontal)

        background.addSubview(iconView)
        background.addSubview(textStack)
        background.addSubview(actionButton)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            iconView.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 30),
            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            actionButton.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            actionButton.centerYAnchor.constraint(equalTo: background.centerYAnchor)
        ])

        panel.contentView = background
        self.panel = panel
        self.iconView = iconView
        self.titleLabel = titleLabel
        self.bodyLabel = bodyLabel
        self.actionButton = actionButton
        return panel
    }

    @MainActor
    private func updateContent(for phase: PomodoroPhase) {
        let copy = PomodoroCompletionNotificationCopy(phase: phase)
        titleLabel?.stringValue = copy.title
        bodyLabel?.stringValue = copy.body
        iconView?.image = NSImage(systemSymbolName: copy.symbolName, accessibilityDescription: nil)
        actionButton?.title = copy.actionTitle
        actionButton?.toolTip = "Start the next \(copy.nextPhase.title.lowercased()) session"
    }

    @MainActor
    @objc private func startNextPhaseClicked() {
        let action = startNextPhase
        dismissPanel()
        action?()
    }

    @MainActor
    private func screenNearestPointer() -> NSScreen? {
        let pointerLocation = NSEvent.mouseLocation
        return NSScreen.screens.first {
            NSMouseInRect(pointerLocation, $0.frame, false)
        }
    }
}
