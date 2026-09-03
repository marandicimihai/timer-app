import Combine
import Foundation
import Testing
@testable import MinimalTimer

@Test @MainActor
func runningActivityDoesNotRefreshTheEntireAppEverySecond() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)
    let controller = TimerAppController(
        activityStore: store,
        pomodoro: PomodoroTimer(
            settings: makeTestPomodoroSettings(),
            now: { clock.date },
            notifier: TestNotifier()
        ),
        now: { clock.date }
    )
    controller.startActivity(named: "Writing")

    var appUpdates = 0
    let subscription = controller.objectWillChange.sink { appUpdates += 1 }
    defer { subscription.cancel() }

    // Drive the same run loop that a global Timer publisher would use.
    RunLoop.main.run(until: Date().addingTimeInterval(1.2))
    #expect(appUpdates == 0)

    // Elapsed time remains accurate even without intermediate refreshes.
    clock.date.addTimeInterval(3_661)
    #expect(controller.menuBarTime(at: clock.date) == "1:01:01")
    controller.finishActivity()
    #expect(store.sessions.first?.duration == 3_661)
    #expect(appUpdates > 0)
}
