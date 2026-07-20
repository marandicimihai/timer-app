import Combine
import Foundation
@preconcurrency import UserNotifications

enum PomodoroPhase: String, CaseIterable, Sendable {
    case focus
    case `break`

    var title: String {
        switch self {
        case .focus: "Focus"
        case .break: "Break"
        }
    }

    var next: PomodoroPhase {
        self == .focus ? .break : .focus
    }
}

protocol PomodoroNotifying {
    func requestAuthorizationIfNeeded()
    func sendCompletion(
        for phase: PomodoroPhase,
        startNextPhase: @escaping @MainActor @Sendable () -> Void
    )
}

final class UserNotificationService: NSObject, PomodoroNotifying, UNUserNotificationCenterDelegate {
    private let completionBannerPresenter: any PomodoroCompletionBannerPresenting

    private var notificationCenter: UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return UNUserNotificationCenter.current()
    }

    override convenience init() {
        self.init(completionBannerPresenter: PomodoroCompletionBannerPresenter())
    }

    init(completionBannerPresenter: any PomodoroCompletionBannerPresenting) {
        self.completionBannerPresenter = completionBannerPresenter
        super.init()
        notificationCenter?.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        guard let notificationCenter else { return }
        notificationCenter.getNotificationSettings { [notificationCenter] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func sendCompletion(
        for phase: PomodoroPhase,
        startNextPhase: @escaping @MainActor @Sendable () -> Void
    ) {
        guard let notificationCenter else {
            sendCommandLineNotification(for: phase)
            completionBannerPresenter.presentCompletion(
                for: phase,
                startNextPhase: startNextPhase
            )
            return
        }

        let copy = PomodoroCompletionNotificationCopy(phase: phase)
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.interruptionLevel = PomodoroNotificationPresentationPolicy.interruptionLevel
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        notificationCenter.add(request) { error in
            if let error {
                NSLog("MinimalTimer could not deliver a Pomodoro notification: %@", error.localizedDescription)
            }
        }
        completionBannerPresenter.presentCompletion(
            for: phase,
            startNextPhase: startNextPhase
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(PomodoroNotificationPresentationPolicy.foregroundOptions)
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
    @Published private(set) var isAwaitingNextPhase = false
    @Published private(set) var remainingDuration: TimeInterval

    let settings: PomodoroSettings

    private var startedAt: Date?
    private var activeDuration: TimeInterval?
    private var completionTask: Task<Void, Never>?
    private let now: () -> Date
    private let notifier: PomodoroNotifying
    private let completionDelay: (TimeInterval) -> Duration

    init(
        settings: PomodoroSettings = PomodoroSettings(),
        now: @escaping () -> Date = Date.init,
        notifier: PomodoroNotifying = UserNotificationService(),
        completionDelay: @escaping (TimeInterval) -> Duration = { .seconds($0) }
    ) {
        self.settings = settings
        self.now = now
        self.notifier = notifier
        self.completionDelay = completionDelay
        self.remainingDuration = settings.duration(for: .focus)
    }

    var suggestedPhase: PomodoroPhase {
        completedPhase?.next ?? .focus
    }

    var progress: Double {
        progress(at: now())
    }

    func progress(at date: Date) -> Double {
        guard let startedAt, let activeDuration, activeDuration > 0 else { return 0 }
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        return min(1, elapsed / activeDuration)
    }

    func remainingDuration(at date: Date) -> TimeInterval {
        guard let startedAt, let activeDuration else { return remainingDuration }
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        return max(0, activeDuration - elapsed)
    }

    func canStart(_ phase: PomodoroPhase) -> Bool {
        activePhase == nil && phase == suggestedPhase
    }

    @discardableResult
    func start(_ phase: PomodoroPhase, at date: Date? = nil) -> Bool {
        guard canStart(phase) else { return false }
        if settings.notificationsEnabled {
            notifier.requestAuthorizationIfNeeded()
        }
        let duration = settings.duration(for: phase)
        let startDate = date ?? now()
        activePhase = phase
        isAwaitingNextPhase = false
        startedAt = startDate
        activeDuration = duration
        remainingDuration = duration
        let delay = completionDelay(duration)
        completionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.tick(at: startDate.addingTimeInterval(duration))
        }
        return true
    }

    func stop() {
        completionTask?.cancel()
        completionTask = nil
        activePhase = nil
        isAwaitingNextPhase = false
        startedAt = nil
        activeDuration = nil
        remainingDuration = settings.duration(for: suggestedPhase)
    }

    func tick(at date: Date? = nil) {
        guard let activePhase, let startedAt, let activeDuration else { return }
        let elapsed = max(0, (date ?? now()).timeIntervalSince(startedAt))
        remainingDuration = max(0, activeDuration - elapsed)

        guard remainingDuration == 0 else { return }
        self.isAwaitingNextPhase = true
        self.activePhase = nil
        self.completedPhase = activePhase
        self.startedAt = nil
        self.activeDuration = nil
        completionTask?.cancel()
        completionTask = nil
        if settings.notificationsEnabled {
            let nextPhase = activePhase.next
            notifier.sendCompletion(for: activePhase) { [weak self] in
                self?.start(nextPhase)
            }
        }
    }

    func refreshIdleDurationFromSettings() {
        guard activePhase == nil else { return }
        remainingDuration = settings.duration(for: suggestedPhase)
    }

    func requestNotificationAuthorizationIfNeeded() {
        guard settings.notificationsEnabled else { return }
        notifier.requestAuthorizationIfNeeded()
    }
}
