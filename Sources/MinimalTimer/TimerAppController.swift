import Combine
import Foundation

enum DetailWindowTab: Hashable, CaseIterable {
    case settings
    case statistics
    case goals
    case manageActivities
    case pomodoro
    case history

    var title: String {
        switch self {
        case .settings: "Settings"
        case .statistics: "Statistics"
        case .goals: "Goals"
        case .manageActivities: "Manage activities"
        case .pomodoro: "Pomodoro"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .settings: "gearshape"
        case .statistics: "chart.bar.xaxis"
        case .goals: "target"
        case .manageActivities: "archivebox"
        case .pomodoro: "circle.circle"
        case .history: "clock.arrow.circlepath"
        }
    }
}

@MainActor
final class TimerAppController: ObservableObject {
    let activityStore: ActivityStore
    let pomodoro: PomodoroTimer
    @Published private(set) var currentDate: Date
    @Published var selectedDetailWindowTab: DetailWindowTab = .settings

    private let now: () -> Date
    private var archiveCancellable: AnyCancellable?

    init(
        activityStore: ActivityStore,
        pomodoro: PomodoroTimer,
        now: @escaping () -> Date = Date.init
    ) {
        self.activityStore = activityStore
        self.pomodoro = pomodoro
        self.now = now
        self.currentDate = now()
        archiveCancellable = activityStore.archivePreferences.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // Clock displays own their timelines. Publishing a date here every
        // second also rebuilds app scenes, history, and hidden statistics.
    }

    var isTimerRunning: Bool {
        activityStore.activeActivity != nil || pomodoro.activePhase != nil
    }

    var menuBarTime: String {
        menuBarTime(at: currentDate)
    }

    func menuBarTime(at date: Date) -> String {
        if let activity = activityStore.activeActivity {
            return DurationFormatter.clock(date.timeIntervalSince(activity.startedAt))
        }
        return ""
    }

    var menuBarSymbol: String {
        "timer"
    }

    var showsTimerValueInMenuBar: Bool {
        activityStore.activeActivity != nil && pomodoro.settings.showTimerValueInMenuBar
    }

    func refresh(at date: Date? = nil) {
        currentDate = date ?? now()
        pomodoro.tick(at: currentDate)
    }

    func startActivity(named name: String) {
        activityStore.startActivity(named: name, at: now())
        refresh()
    }

    func finishActivity() {
        _ = activityStore.finishActivity(at: now())
        refresh()
    }

    func deleteActivitySession(id: UUID) {
        guard activityStore.deleteSession(id: id) else { return }
        objectWillChange.send()
    }

    func deleteActivityHistory(named name: String) {
        guard activityStore.deleteActivityHistory(named: name) > 0 else { return }
        objectWillChange.send()
    }

    func clearActivityHistory() {
        activityStore.clearHistory()
        objectWillChange.send()
    }

    func archiveActivity(named name: String) {
        _ = activityStore.archiveActivity(named: name)
    }

    func unarchiveActivity(id: String) {
        activityStore.archivePreferences.unarchiveActivity(id: id)
    }

    func setPomodoroEnabled(_ enabled: Bool) {
        if !enabled { pomodoro.stop() }
        pomodoro.settings.setEnabled(enabled)
        objectWillChange.send()
    }

    func showHistoryTab() {
        selectedDetailWindowTab = .history
    }

    func showSettingsTab() {
        selectedDetailWindowTab = .settings
    }

    func showStatisticsTab() {
        selectedDetailWindowTab = .statistics
    }

    func setFocusDurationMinutes(_ minutes: Int) {
        pomodoro.settings.setFocusDurationMinutes(minutes)
        pomodoro.refreshIdleDurationFromSettings()
        objectWillChange.send()
    }

    func setBreakDurationMinutes(_ minutes: Int) {
        pomodoro.settings.setBreakDurationMinutes(minutes)
        pomodoro.refreshIdleDurationFromSettings()
        objectWillChange.send()
    }

    func setPomodoroNotificationsEnabled(_ enabled: Bool) {
        pomodoro.settings.setNotificationsEnabled(enabled)
        if enabled {
            pomodoro.requestNotificationAuthorizationIfNeeded()
        }
        objectWillChange.send()
    }

    func setShowTimerValueInMenuBar(_ enabled: Bool) {
        pomodoro.settings.setShowTimerValueInMenuBar(enabled)
        objectWillChange.send()
    }

    func restorePomodoroSettings() {
        pomodoro.settings.restorePomodoroDefaults()
        pomodoro.refreshIdleDurationFromSettings()
        objectWillChange.send()
    }

    @discardableResult
    func startPomodoro(_ phase: PomodoroPhase) -> Bool {
        guard pomodoro.start(phase, at: now()) else { return false }
        refresh()
        return true
    }

    @discardableResult
    func startSuggestedPomodoro() -> Bool {
        startPomodoro(pomodoro.suggestedPhase)
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
