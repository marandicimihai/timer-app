import Foundation
import SwiftData
import Testing
@testable import MinimalTimer

@Test @MainActor
func activityLoggingWorksWithoutPomodoro() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)
    let pomodoro = PomodoroTimer(now: { clock.date }, notifier: TestNotifier())
    let controller = TimerAppController(activityStore: store, pomodoro: pomodoro, now: { clock.date })

    controller.startActivity(named: "Deep work")
    #expect(store.activeActivity?.name == "Deep work")
    #expect(pomodoro.activePhase == nil)

    clock.date.addTimeInterval(600)
    controller.finishActivity()

    #expect(store.sessions.first?.name == "Deep work")
    #expect(store.sessions.first?.duration == 600)
    #expect(pomodoro.activePhase == nil)
}

@Test @MainActor
func finishingAnActivityFromTheMenuFlowStopsPomodoro() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)
    let pomodoro = PomodoroTimer(now: { clock.date }, notifier: TestNotifier())
    let controller = TimerAppController(activityStore: store, pomodoro: pomodoro, now: { clock.date })

    controller.startActivity(named: "Email")
    controller.startPomodoro(.focus)
    clock.date.addTimeInterval(45)
    controller.finishActivity()

    #expect(store.activeActivity == nil)
    #expect(store.sessions.first?.duration == 45)
    #expect(pomodoro.activePhase == nil)
}

@Test @MainActor
func switchingActivitiesFromTheMenuFlowStopsPomodoro() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)
    let pomodoro = PomodoroTimer(now: { clock.date }, notifier: TestNotifier())
    let controller = TimerAppController(activityStore: store, pomodoro: pomodoro, now: { clock.date })

    controller.startActivity(named: "Email")
    controller.startPomodoro(.focus)
    clock.date.addTimeInterval(60)
    controller.startActivity(named: "Design")

    #expect(store.sessions.first?.name == "Email")
    #expect(store.activeActivity?.name == "Design")
    #expect(pomodoro.activePhase == nil)
}

@Test @MainActor
func pomodoroCanRunWithoutAnActivityFromTheMenuFlow() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)
    let pomodoro = PomodoroTimer(now: { clock.date }, notifier: TestNotifier())
    let controller = TimerAppController(activityStore: store, pomodoro: pomodoro, now: { clock.date })

    controller.startPomodoro(.focus)

    #expect(store.activeActivity == nil)
    #expect(pomodoro.activePhase == .focus)
}
