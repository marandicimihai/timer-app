import Combine
import Foundation

@MainActor
final class TimerAppController: ObservableObject {
    let activityStore: ActivityStore
    let pomodoro: PomodoroTimer
    @Published private(set) var currentDate: Date

    private let now: () -> Date

    init(
        activityStore: ActivityStore,
        pomodoro: PomodoroTimer,
        now: @escaping () -> Date = Date.init
    ) {
        self.activityStore = activityStore
        self.pomodoro = pomodoro
        self.now = now
        self.currentDate = now()
    }

    var isTimerRunning: Bool {
        activityStore.activeActivity != nil || pomodoro.activePhase != nil
    }

    var menuBarTime: String {
        if let activity = activityStore.activeActivity {
            return DurationFormatter.clock(currentDate.timeIntervalSince(activity.startedAt))
        }
        if pomodoro.activePhase != nil {
            return DurationFormatter.clock(pomodoro.remainingDuration)
        }
        return ""
    }

    var menuBarSymbol: String {
        pomodoro.activePhase == nil ? "timer" : "leaf"
    }

    func refresh() {
        currentDate = now()
        pomodoro.tick(at: currentDate)
        objectWillChange.send()
    }

    func startActivity(named name: String) {
        if activityStore.activeActivity != nil {
            pomodoro.stop()
        }
        activityStore.startActivity(named: name, at: now())
        refresh()
    }

    func finishActivity() {
        _ = activityStore.finishActivity(at: now())
        pomodoro.stop()
        refresh()
    }

    func startPomodoro(_ phase: PomodoroPhase) {
        pomodoro.start(phase, at: now())
        refresh()
    }

    func stopPomodoro() {
        pomodoro.stop()
        refresh()
    }

    func applicationWillTerminate() {
        activityStore.endActivityForTermination()
        pomodoro.stop()
    }
}
