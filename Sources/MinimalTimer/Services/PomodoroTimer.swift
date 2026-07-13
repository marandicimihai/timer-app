import Combine
import Foundation
@preconcurrency import UserNotifications

enum PomodoroPhase: String, CaseIterable {
    case focus
    case `break`

    var title: String {
        switch self {
        case .focus: "Focus"
        case .break: "Break"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .focus: 25 * 60
        case .break: 5 * 60
        }
    }

    var next: PomodoroPhase {
        self == .focus ? .break : .focus
    }
}

protocol PomodoroNotifying {
    func requestAuthorizationIfNeeded()
    func sendCompletion(for phase: PomodoroPhase)
}

final class UserNotificationService: PomodoroNotifying {
    private var notificationCenter: UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return UNUserNotificationCenter.current()
    }

    func requestAuthorizationIfNeeded() {
        guard let notificationCenter else { return }
        notificationCenter.getNotificationSettings { [notificationCenter] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func sendCompletion(for phase: PomodoroPhase) {
        guard let notificationCenter else {
            sendCommandLineNotification(for: phase)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(phase.title) complete"
        content.body = phase == .focus ? "Your break is ready when you are." : "Ready for another focus session?"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        notificationCenter.add(request)
    }

    private func sendCommandLineNotification(for phase: PomodoroPhase) {
        let script: String
        switch phase {
        case .focus:
            script = "display notification \"Your break is ready when you are.\" with title \"Focus complete\""
        case .break:
            script = "display notification \"Ready for another focus session?\" with title \"Break complete\""
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}

@MainActor
final class PomodoroTimer: ObservableObject {
    @Published private(set) var activePhase: PomodoroPhase?
    @Published private(set) var completedPhase: PomodoroPhase?
    @Published private(set) var remainingDuration: TimeInterval = PomodoroPhase.focus.duration

    private var startedAt: Date?
    private let now: () -> Date
    private let notifier: PomodoroNotifying

    init(now: @escaping () -> Date = Date.init, notifier: PomodoroNotifying = UserNotificationService()) {
        self.now = now
        self.notifier = notifier
    }

    var suggestedPhase: PomodoroPhase {
        completedPhase?.next ?? .focus
    }

    var progress: Double {
        guard let activePhase else { return 0 }
        return min(1, max(0, 1 - remainingDuration / activePhase.duration))
    }

    func start(_ phase: PomodoroPhase, at date: Date? = nil) {
        notifier.requestAuthorizationIfNeeded()
        activePhase = phase
        completedPhase = nil
        startedAt = date ?? now()
        remainingDuration = phase.duration
    }

    func stop() {
        activePhase = nil
        completedPhase = nil
        startedAt = nil
        remainingDuration = PomodoroPhase.focus.duration
    }

    func tick(at date: Date? = nil) {
        guard let activePhase, let startedAt else { return }
        let elapsed = max(0, (date ?? now()).timeIntervalSince(startedAt))
        remainingDuration = max(0, activePhase.duration - elapsed)

        guard remainingDuration == 0 else { return }
        self.activePhase = nil
        self.completedPhase = activePhase
        self.startedAt = nil
        notifier.sendCompletion(for: activePhase)
    }
}
