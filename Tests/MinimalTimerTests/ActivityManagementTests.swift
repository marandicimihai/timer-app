import Foundation
import SwiftData
import SwiftUI
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

@Test(arguments: [false, true]) @MainActor
func deletingAnActivityRemovesHistoryAndPreferencesAndPersists(archived: Bool) throws {
    let suite = "MinimalTimerTests.DeleteActivity.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let archives = ActivityArchivePreferences(userDefaults: defaults)
    let goals = ActivityGoalPreferences(userDefaults: defaults, archivePreferences: archives)
    let colors = ActivityColorPreferences(userDefaults: defaults, archivePreferences: archives)
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: ActivitySession.self, configurations: configuration)
    let clock = TestClock(Date())
    let store = ActivityStore(modelContext: container.mainContext, now: { clock.date }, archivePreferences: archives)
    let controller = TimerAppController(
        activityStore: store,
        pomodoro: PomodoroTimer(settings: makeTestPomodoroSettings(), notifier: TestNotifier())
    )
    for name in ["Writing", "writing", "Reading"] {
        store.startActivity(named: name)
        clock.date.addTimeInterval(60)
        store.finishActivity()
    }
    goals.setGoal(hours: 4, forActivityNamed: "Writing")
    goals.setGoal(hours: 2, forActivityNamed: "Reading")
    colors.setColor(.red, forActivityID: "writing")
    colors.setColor(.blue, forActivityID: "reading")
    if archived {
        #expect(store.archiveActivity(named: "Writing"))
        #expect(store.deleteActivityHistory(named: "Writing") == 0)
        colors.removeColor(forActivityID: "writing")
        #expect(colors.customColors["writing"] != nil)
    }

    #expect(try controller.deleteActivity(named: "  WRITING  ", goalPreferences: goals, colorPreferences: colors))
    #expect(store.sessions.map(\.name) == ["Reading"])
    #expect(store.knownActivities.map(\.id) == ["reading"])
    #expect(store.recentActivityNames() == ["Reading"])
    #expect(!archives.isArchived("writing"))
    #expect(goals.goals.map(\.id) == ["reading"])
    #expect(colors.customColors["writing"] == nil)
    #expect(colors.customColors["reading"] != nil)
    let reloaded = ActivityStore(modelContext: container.mainContext)
    #expect(reloaded.sessions.map(\.name) == ["Reading"])
    #expect(!ActivityArchivePreferences(userDefaults: defaults).isArchived("writing"))
    #expect(ActivityGoalPreferences(userDefaults: defaults).goals.map(\.id) == ["reading"])
    #expect(ActivityColorPreferences(userDefaults: defaults).customColors["writing"] == nil)
    #expect(ActivityColorPreferences(userDefaults: defaults).customColors["reading"] != nil)
}

@Test @MainActor
func deletingAnActivityWithoutHistoryRemovesItsGoalColorAndArchive() throws {
    let clock = TestClock(Date())
    let archives = ActivityArchivePreferences(userDefaults: nil)
    let store = try makeStore(clock: clock, archivePreferences: archives)
    let goals = ActivityGoalPreferences(userDefaults: nil, archivePreferences: archives)
    let colors = ActivityColorPreferences(userDefaults: nil, archivePreferences: archives)
    let controller = TimerAppController(
        activityStore: store,
        pomodoro: PomodoroTimer(settings: makeTestPomodoroSettings(), notifier: TestNotifier())
    )
    goals.setGoal(hours: 4, forActivityNamed: "Writing")
    colors.setColor(.red, forActivityID: "writing")
    archives.archiveActivity(named: "Writing")
    #expect(try controller.deleteActivity(named: "Writing", goalPreferences: goals, colorPreferences: colors))
    #expect(store.knownActivities.isEmpty)
    #expect(goals.goals.isEmpty)
    #expect(colors.customColors.isEmpty)
    #expect(archives.archivedActivities.isEmpty)
}

@Test @MainActor
func runningActivitiesMustBeFinishedBeforeDeletion() throws {
    let clock = TestClock(Date())
    let store = try makeStore(clock: clock)
    let goals = ActivityGoalPreferences(userDefaults: nil)
    let colors = ActivityColorPreferences(userDefaults: nil)
    let controller = TimerAppController(
        activityStore: store,
        pomodoro: PomodoroTimer(settings: makeTestPomodoroSettings(), notifier: TestNotifier())
    )
    store.startActivity(named: "Writing")
    clock.date.addTimeInterval(60)
    store.finishActivity()
    store.startActivity(named: "Writing")
    goals.setGoal(hours: 4, forActivityNamed: "Writing")
    colors.setColor(.red, forActivityID: "writing")
    #expect(try !controller.deleteActivity(named: " WRITING ", goalPreferences: goals, colorPreferences: colors))
    #expect(store.activeActivity?.name == "Writing")
    #expect(store.sessions.count == 1)
    #expect(goals.goals.count == 1)
    #expect(colors.customColors["writing"] != nil)
    store.finishActivity()
    #expect(try controller.deleteActivity(named: "Writing", goalPreferences: goals, colorPreferences: colors))
    #expect(store.sessions.isEmpty)
    #expect(goals.goals.isEmpty)
    #expect(colors.customColors.isEmpty)
}
