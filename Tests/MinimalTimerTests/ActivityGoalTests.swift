import Foundation
import Testing
@testable import MinimalTimer

@Test @MainActor
func weeklyGoalsPersistEditsAndRemovalAcrossLaunches() throws {
    let suite = "MinimalTimerTests.ActivityGoals.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ActivityGoalPreferences(userDefaults: defaults)

    preferences.setGoal(hours: 10, forActivityNamed: " Writing ")
    preferences.setGoal(hours: 2.5, forActivityNamed: "WRITING")
    preferences.setGoal(hours: 4, forActivityNamed: "Reading")

    let reloaded = ActivityGoalPreferences(userDefaults: defaults)
    #expect(reloaded.goals.count == 2)
    #expect(reloaded.goal(forActivityID: "writing")?.hours == 2.5)
    reloaded.removeGoal(forActivityID: "writing")
    #expect(ActivityGoalPreferences(userDefaults: defaults).goals.map(\.id) == ["reading"])
}

@Test @MainActor
func weeklyGoalsRejectInvalidTargetsWithoutChangingExistingGoals() {
    let preferences = ActivityGoalPreferences(userDefaults: nil)
    preferences.setGoal(hours: 8, forActivityNamed: "Writing")
    for hours in [0, -1, 169, Double.nan, .infinity] {
        preferences.setGoal(hours: hours, forActivityNamed: "Writing")
    }
    preferences.setGoal(hours: 8, forActivityNamed: "  ")
    #expect(preferences.goals.count == 1)
    #expect(preferences.goals.first?.hours == 8)
}

@Test
func weeklyGoalProgressUsesRequestedColorBoundariesAndSupportsOverachievement() {
    let goal = WeeklyActivityGoal(id: "writing", name: "Writing", hours: 10)
    for (hours, percentage, level) in [
        (0.0, 0, ActivityGoalProgressLevel.red),
        (1.0, 10, .red),
        (1.99, 19, .red),
        (2.0, 20, .yellow),
        (6.99, 69, .yellow),
        (7.0, 70, .green),
        (10.0, 100, .green),
        (12.0, 120, .green)
    ] {
        let progress = ActivityGoalProgress(goal: goal, duration: hours * 3_600)
        #expect(progress.percentage == percentage)
        #expect(progress.level == level)
    }
}

@Test @MainActor
func weeklyGoalsClipAtMondayIncludeRunningTimeAndResetTheFollowingWeek() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    // The chosen week starts on Monday, October 12, 2026.
    let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
    let clock = TestClock(monday.addingTimeInterval(12 * 3_600))
    let store = try makeStore(clock: clock, calendar: calendar)
    let goal = WeeklyActivityGoal(id: "writing", name: "Writing", hours: 10)
    let unused = WeeklyActivityGoal(id: "reading", name: "Reading", hours: 5)

    store.startActivity(named: "Writing", at: monday.addingTimeInterval(-5 * 3_600))
    _ = store.finishActivity(at: monday.addingTimeInterval(-3 * 3_600))
    store.startActivity(named: " WRITING ", at: monday.addingTimeInterval(-3_600))
    let boundarySession = try #require(store.finishActivity(at: monday.addingTimeInterval(3_600)))
    store.startActivity(named: "Reading", at: monday.addingTimeInterval(2 * 3_600))
    _ = store.finishActivity(at: monday.addingTimeInterval(3 * 3_600))
    store.startActivity(named: "writing", at: monday.addingTimeInterval(10 * 3_600))

    let progress = store.weeklyGoalProgress(for: [goal, unused], at: clock.date)
    #expect(progress[0].completedHours == 3)
    #expect(progress[0].percentage == 30)
    #expect(progress[1].completedHours == 1)
    #expect(store.weeklyGoalProgress(for: [goal], at: monday)[0].duration == 0)

    _ = store.finishActivity(at: clock.date)
    #expect(store.weeklyGoalProgress(for: [goal], at: clock.date)[0].completedHours == 3)
    #expect(store.deleteSession(id: boundarySession.id))
    #expect(store.weeklyGoalProgress(for: [goal], at: clock.date)[0].completedHours == 2)

    let sunday = monday.addingTimeInterval(6 * 86_400 + 12 * 3_600)
    #expect(store.weeklyGoalProgress(for: [goal], at: sunday)[0].completedHours == 2)
    let nextMonday = monday.addingTimeInterval(7 * 86_400)
    #expect(store.weeklyGoalProgress(for: [goal, unused], at: nextMonday).map(\.duration) == [0, 0])
}

@Test @MainActor
func weeklyGoalsUseLocalWeekBoundariesAcrossDaylightSavingChanges() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Chisinau"))
    let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)))
    let nextMonday = try #require(calendar.date(byAdding: .day, value: 7, to: monday))
    let clock = TestClock(nextMonday.addingTimeInterval(3_600))
    let store = try makeStore(clock: clock, calendar: calendar)
    let goal = WeeklyActivityGoal(id: "writing", name: "Writing", hours: 10)

    store.startActivity(named: "Writing", at: nextMonday.addingTimeInterval(-3_600))
    #expect(store.weeklyGoalProgress(for: [goal], at: nextMonday.addingTimeInterval(-1))[0].duration == 3_599)
    #expect(store.weeklyGoalProgress(for: [goal], at: clock.date)[0].duration == 3_600)
}
