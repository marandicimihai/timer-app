import Foundation
import Testing
@testable import MinimalTimer

@Test @MainActor
func disablingPomodoroStopsItAndPreservesActivityTracking() throws {
    let suite = "MinimalTimerTests.PomodoroEnabled.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = PomodoroSettings(userDefaults: defaults)
    #expect(settings.isEnabled)
    let clock = TestClock(Date())
    let notifier = TestNotifier()
    let timer = PomodoroTimer(settings: settings, now: { clock.date }, notifier: notifier)
    let store = try makeStore(clock: clock)
    let controller = TimerAppController(activityStore: store, pomodoro: timer, now: { clock.date })
    controller.startActivity(named: "Writing")
    #expect(controller.startSuggestedPomodoro())

    controller.setPomodoroEnabled(false)
    #expect(!settings.isEnabled)
    #expect(!PomodoroSettings(userDefaults: defaults).isEnabled)
    #expect(timer.activePhase == nil)
    #expect(!timer.isAwaitingNextPhase)
    #expect(!controller.startSuggestedPomodoro())
    #expect(!timer.start(.focus))
    #expect(!timer.canStart(.focus))
    clock.date.addTimeInterval(3_600)
    controller.refresh()
    #expect(notifier.completedPhases.isEmpty)
    #expect(store.activeActivity?.name == "Writing")
    #expect(controller.showsTimerValueInMenuBar)

    controller.setPomodoroEnabled(true)
    #expect(controller.startSuggestedPomodoro())
    #expect(timer.activePhase == .focus)
    timer.stop()
}

@Test @MainActor
func disabledPomodoroRejectsActionsFromAnEarlierCompletionBanner() throws {
    let clock = TestClock(Date())
    let notifier = TestNotifier()
    let settings = makeTestPomodoroSettings(focusMinutes: 1)
    let timer = PomodoroTimer(settings: settings, now: { clock.date }, notifier: notifier)
    let store = try makeStore(clock: clock)
    let controller = TimerAppController(activityStore: store, pomodoro: timer, now: { clock.date })
    #expect(controller.startSuggestedPomodoro())
    clock.date.addTimeInterval(60)
    timer.tick()
    let action = try #require(notifier.completionActions.first)

    controller.setPomodoroEnabled(false)
    action()
    #expect(timer.activePhase == nil)
    #expect(!timer.isAwaitingNextPhase)
    #expect(!timer.canStart(.break))
}

@Test @MainActor
func pomodoroDefaultsRestoreEnablementWithoutChangingActivityDisplay() throws {
    let clock = TestClock(Date())
    let store = try makeStore(clock: clock)
    let settings = makeTestPomodoroSettings(showTimerValueInMenuBar: false)
    let controller = TimerAppController(
        activityStore: store,
        pomodoro: PomodoroTimer(settings: settings, notifier: TestNotifier())
    )
    controller.setPomodoroEnabled(false)
    controller.setFocusDurationMinutes(45)
    controller.restorePomodoroSettings()
    #expect(settings.isEnabled)
    #expect(settings.focusDurationMinutes == 25)
    #expect(!settings.showTimerValueInMenuBar)
}

@Test
func detailTabsAppearInTheRequestedOrder() {
    #expect(DetailWindowTab.allCases.map(\.title) == [
        "Settings", "Statistics", "Goals", "Manage activities", "Pomodoro", "History"
    ])
}
