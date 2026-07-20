import Foundation
import Testing
@testable import MinimalTimer

final class TestNotifier: PomodoroNotifying {
    private(set) var authorizationRequests = 0
    private(set) var completedPhases: [PomodoroPhase] = []
    private(set) var completionActions: [@MainActor @Sendable () -> Void] = []

    func requestAuthorizationIfNeeded() {
        authorizationRequests += 1
    }

    func sendCompletion(
        for phase: PomodoroPhase,
        startNextPhase: @escaping @MainActor @Sendable () -> Void
    ) {
        completedPhases.append(phase)
        completionActions.append(startNextPhase)
    }
}

@MainActor
func makeTestPomodoroSettings(
    focusMinutes: Int = PomodoroSettings.defaultFocusDurationMinutes,
    breakMinutes: Int = PomodoroSettings.defaultBreakDurationMinutes,
    notificationsEnabled: Bool = true,
    showTimerValueInMenuBar: Bool = true
) -> PomodoroSettings {
    let settings = PomodoroSettings(userDefaults: nil)
    settings.setFocusDurationMinutes(focusMinutes)
    settings.setBreakDurationMinutes(breakMinutes)
    settings.setNotificationsEnabled(notificationsEnabled)
    settings.setShowTimerValueInMenuBar(showTimerValueInMenuBar)
    return settings
}

@Test @MainActor
func pomodoroCompletesAndPreparesTheNextPhase() {
    var now = Date(timeIntervalSince1970: 1_000)
    let notifier = TestNotifier()
    let settings = makeTestPomodoroSettings()
    let pomodoro = PomodoroTimer(settings: settings, now: { now }, notifier: notifier)

    #expect(!pomodoro.isAwaitingNextPhase)
    pomodoro.start(.focus)
    #expect(!pomodoro.isAwaitingNextPhase)
    now.addTimeInterval(settings.duration(for: .focus))
    pomodoro.tick()

    #expect(pomodoro.activePhase == nil)
    #expect(pomodoro.completedPhase == .focus)
    #expect(pomodoro.isAwaitingNextPhase)
    #expect(pomodoro.suggestedPhase == .break)
    #expect(pomodoro.remainingDuration == 0)
    #expect(notifier.authorizationRequests == 1)
    #expect(notifier.completedPhases == [.focus])
}

@Test @MainActor
func completionBannerActionStartsOnlyTheNextValidPhase() {
    var now = Date(timeIntervalSince1970: 1_000)
    let notifier = TestNotifier()
    let settings = makeTestPomodoroSettings(focusMinutes: 1, breakMinutes: 1)
    let pomodoro = PomodoroTimer(settings: settings, now: { now }, notifier: notifier)

    #expect(pomodoro.start(.focus))
    now.addTimeInterval(60)
    pomodoro.tick()
    #expect(notifier.completionActions.count == 1)

    notifier.completionActions[0]()
    #expect(pomodoro.activePhase == .break)
    #expect(!pomodoro.isAwaitingNextPhase)

    now.addTimeInterval(60)
    pomodoro.tick()
    #expect(notifier.completionActions.count == 2)

    // The old Focus-complete action still asks for Break, so the model rejects it.
    notifier.completionActions[0]()
    #expect(pomodoro.activePhase == nil)

    notifier.completionActions[1]()
    #expect(pomodoro.activePhase == .focus)
}

@Test @MainActor
func stoppingWhileAwaitingTheNextPhaseDismissesTheMenuBarPrompt() {
    var now = Date(timeIntervalSince1970: 1_000)
    let settings = makeTestPomodoroSettings(focusMinutes: 1, breakMinutes: 1)
    let pomodoro = PomodoroTimer(settings: settings, now: { now }, notifier: TestNotifier())

    #expect(pomodoro.start(.focus))
    now.addTimeInterval(60)
    pomodoro.tick()
    #expect(pomodoro.isAwaitingNextPhase)
    #expect(pomodoro.suggestedPhase == .break)

    pomodoro.stop()

    #expect(pomodoro.activePhase == nil)
    #expect(!pomodoro.isAwaitingNextPhase)
    #expect(pomodoro.suggestedPhase == .break)
}

@Test @MainActor
func stoppingAnInitialFocusPreparesFocusAgain() {
    let now = Date(timeIntervalSince1970: 1_000)
    let settings = makeTestPomodoroSettings(focusMinutes: 40, breakMinutes: 10)
    let pomodoro = PomodoroTimer(settings: settings, now: { now }, notifier: TestNotifier())

    #expect(pomodoro.start(.focus))
    pomodoro.stop()

    #expect(pomodoro.activePhase == nil)
    #expect(pomodoro.completedPhase == nil)
    #expect(!pomodoro.isAwaitingNextPhase)
    #expect(pomodoro.suggestedPhase == .focus)
    #expect(pomodoro.remainingDuration == 40 * 60)
}

@Test @MainActor
func stoppingABreakPreparesThatUnfinishedBreakAgain() {
    var now = Date(timeIntervalSince1970: 1_000)
    let settings = makeTestPomodoroSettings(focusMinutes: 1, breakMinutes: 10)
    let pomodoro = PomodoroTimer(settings: settings, now: { now }, notifier: TestNotifier())

    #expect(pomodoro.start(.focus))
    now.addTimeInterval(60)
    pomodoro.tick()
    #expect(pomodoro.start(.break))
    pomodoro.stop()

    #expect(pomodoro.activePhase == nil)
    #expect(pomodoro.completedPhase == .focus)
    #expect(!pomodoro.isAwaitingNextPhase)
    #expect(pomodoro.suggestedPhase == .break)
    #expect(pomodoro.remainingDuration == 10 * 60)
}

@Test @MainActor
func invalidPhaseStartsDoNotResetOrReplaceTheActiveTimer() {
    var now = Date(timeIntervalSince1970: 1_000)
    let notifier = TestNotifier()
    let settings = makeTestPomodoroSettings(focusMinutes: 1, breakMinutes: 1)
    let pomodoro = PomodoroTimer(settings: settings, now: { now }, notifier: notifier)

    #expect(!pomodoro.start(.break))
    #expect(pomodoro.activePhase == nil)
    #expect(notifier.authorizationRequests == 0)

    #expect(pomodoro.start(.focus))
    #expect(notifier.authorizationRequests == 1)
    now.addTimeInterval(30)
    pomodoro.tick()
    #expect(pomodoro.remainingDuration == 30)

    #expect(!pomodoro.start(.focus))
    #expect(!pomodoro.start(.break))
    #expect(pomodoro.activePhase == .focus)
    #expect(pomodoro.remainingDuration == 30)
    #expect(notifier.authorizationRequests == 1)

    now.addTimeInterval(30)
    pomodoro.tick()
    #expect(pomodoro.completedPhase == .focus)
    #expect(!pomodoro.start(.focus))
    #expect(notifier.authorizationRequests == 1)
    #expect(pomodoro.start(.break))
    #expect(notifier.authorizationRequests == 2)
}

@Test @MainActor
func completedBreakOnlyAllowsTheNextFocus() {
    var now = Date(timeIntervalSince1970: 1_000)
    let notifier = TestNotifier()
    let settings = makeTestPomodoroSettings(focusMinutes: 1, breakMinutes: 1)
    let pomodoro = PomodoroTimer(settings: settings, now: { now }, notifier: notifier)

    #expect(pomodoro.start(.focus))
    now.addTimeInterval(60)
    pomodoro.tick()
    #expect(pomodoro.start(.break))
    now.addTimeInterval(60)
    pomodoro.tick()

    #expect(pomodoro.completedPhase == .break)
    #expect(pomodoro.suggestedPhase == .focus)
    #expect(!pomodoro.start(.break))
    #expect(pomodoro.start(.focus))
    #expect(notifier.completedPhases == [.focus, .break])
}

@Test @MainActor
func runningPomodoroKeepsItsStartingDurationWhenSettingsChange() {
    var now = Date(timeIntervalSince1970: 1_000)
    let settings = makeTestPomodoroSettings(focusMinutes: 2)
    let pomodoro = PomodoroTimer(settings: settings, now: { now }, notifier: TestNotifier())

    pomodoro.start(.focus)
    settings.setFocusDurationMinutes(1)
    now.addTimeInterval(60)
    pomodoro.tick()

    #expect(pomodoro.activePhase == .focus)
    #expect(pomodoro.remainingDuration == 60)
    #expect(pomodoro.progress == 0.5)

    pomodoro.stop()
    pomodoro.start(.focus)
    #expect(pomodoro.remainingDuration == 60)
}

@Test @MainActor
func disabledNotificationsNeitherRequestAuthorizationNorSendCompletion() {
    var now = Date(timeIntervalSince1970: 1_000)
    let notifier = TestNotifier()
    let settings = makeTestPomodoroSettings(focusMinutes: 1, notificationsEnabled: false)
    let pomodoro = PomodoroTimer(settings: settings, now: { now }, notifier: notifier)

    pomodoro.start(.focus)
    now.addTimeInterval(60)
    pomodoro.tick()

    #expect(notifier.authorizationRequests == 0)
    #expect(notifier.completedPhases.isEmpty)
    #expect(pomodoro.isAwaitingNextPhase)
}

@Test @MainActor
func customBreakDurationControlsBreakCompletion() {
    var now = Date(timeIntervalSince1970: 1_000)
    let settings = makeTestPomodoroSettings(focusMinutes: 1, breakMinutes: 2)
    let notifier = TestNotifier()
    let pomodoro = PomodoroTimer(settings: settings, now: { now }, notifier: notifier)

    #expect(pomodoro.start(.focus))
    now.addTimeInterval(60)
    pomodoro.tick()
    #expect(pomodoro.start(.break))
    now.addTimeInterval(119)
    pomodoro.tick()
    #expect(pomodoro.activePhase == .break)
    #expect(pomodoro.remainingDuration == 1)

    now.addTimeInterval(1)
    pomodoro.tick()
    #expect(pomodoro.activePhase == nil)
    #expect(pomodoro.completedPhase == .break)
    #expect(notifier.completedPhases == [.focus, .break])
}

@Test @MainActor
func disablingNotificationsDuringATimerSuppressesCompletionNotification() {
    var now = Date(timeIntervalSince1970: 1_000)
    let notifier = TestNotifier()
    let settings = makeTestPomodoroSettings(focusMinutes: 1)
    let pomodoro = PomodoroTimer(settings: settings, now: { now }, notifier: notifier)

    pomodoro.start(.focus)
    settings.setNotificationsEnabled(false)
    now.addTimeInterval(60)
    pomodoro.tick()

    #expect(notifier.authorizationRequests == 1)
    #expect(notifier.completedPhases.isEmpty)
}

@Test @MainActor
func pomodoroCompletesWithoutPopoverRefresh() async throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let notifier = TestNotifier()
    let settings = makeTestPomodoroSettings(focusMinutes: 1)
    let pomodoro = PomodoroTimer(
        settings: settings,
        now: { now },
        notifier: notifier,
        completionDelay: { _ in .milliseconds(5) }
    )

    pomodoro.start(.focus)
    // Leave enough scheduling headroom when the MainActor test suite runs in parallel.
    try await Task.sleep(for: .milliseconds(250))

    #expect(pomodoro.activePhase == nil)
    #expect(pomodoro.completedPhase == .focus)
    #expect(notifier.completedPhases == [.focus])
}

@Test @MainActor
func stoppingPomodoroCancelsItsScheduledCompletion() async throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let notifier = TestNotifier()
    let settings = makeTestPomodoroSettings(focusMinutes: 1)
    let pomodoro = PomodoroTimer(
        settings: settings,
        now: { now },
        notifier: notifier,
        completionDelay: { _ in .milliseconds(5) }
    )

    pomodoro.start(.focus)
    pomodoro.stop()
    try await Task.sleep(for: .milliseconds(50))

    #expect(pomodoro.activePhase == nil)
    #expect(pomodoro.completedPhase == nil)
    #expect(notifier.completedPhases.isEmpty)
}
