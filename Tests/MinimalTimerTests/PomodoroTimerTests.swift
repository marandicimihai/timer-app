import Foundation
import Testing
@testable import MinimalTimer

final class TestNotifier: PomodoroNotifying {
    private(set) var authorizationRequests = 0
    private(set) var completedPhases: [PomodoroPhase] = []

    func requestAuthorizationIfNeeded() {
        authorizationRequests += 1
    }

    func sendCompletion(for phase: PomodoroPhase) {
        completedPhases.append(phase)
    }
}

@Test @MainActor
func pomodoroCompletesAndPreparesTheNextPhase() {
    var now = Date(timeIntervalSince1970: 1_000)
    let notifier = TestNotifier()
    let pomodoro = PomodoroTimer(now: { now }, notifier: notifier)

    pomodoro.start(.focus)
    now.addTimeInterval(PomodoroPhase.focus.duration)
    pomodoro.tick()

    #expect(pomodoro.activePhase == nil)
    #expect(pomodoro.completedPhase == .focus)
    #expect(pomodoro.suggestedPhase == .break)
    #expect(pomodoro.remainingDuration == 0)
    #expect(notifier.authorizationRequests == 1)
    #expect(notifier.completedPhases == [.focus])
}

@Test @MainActor
func stoppingPomodoroResetsItToFocus() {
    let now = Date(timeIntervalSince1970: 1_000)
    let pomodoro = PomodoroTimer(now: { now }, notifier: TestNotifier())

    pomodoro.start(.break)
    pomodoro.stop()

    #expect(pomodoro.activePhase == nil)
    #expect(pomodoro.completedPhase == nil)
    #expect(pomodoro.suggestedPhase == .focus)
    #expect(pomodoro.remainingDuration == PomodoroPhase.focus.duration)
}
