import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MinimalTimer

@Test @MainActor
func archivedActivitiesPersistAndStartingTheSameNameRestoresEditing() throws {
    let suite = "MinimalTimerTests.Archives.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let archives = ActivityArchivePreferences(userDefaults: defaults)
    archives.archiveActivity(named: " Writing ")
    archives.archiveActivity(named: "WRITING")
    #expect(archives.archivedActivities == [KnownActivity(id: "writing", name: "Writing")])

    let reloaded = ActivityArchivePreferences(userDefaults: defaults)
    #expect(reloaded.isArchived("writing"))
    let clock = TestClock(Date())
    let store = try makeStore(clock: clock, archivePreferences: reloaded)
    let goals = ActivityGoalPreferences(userDefaults: nil, archivePreferences: reloaded)
    #expect(store.knownActivities.map(\.id) == ["writing"])

    goals.setGoal(hours: 4, forActivityNamed: "Writing")
    #expect(goals.goals.isEmpty)
    store.startActivity(named: "Reading")
    #expect(reloaded.isArchived("writing"))
    store.startActivity(named: "  WRITING  ")
    #expect(!reloaded.isArchived("writing"))
    #expect(!ActivityArchivePreferences(userDefaults: defaults).isArchived("writing"))
    #expect(store.activeActivity?.name == "WRITING")
    goals.setGoal(hours: 4, forActivityNamed: "Writing")
    #expect(goals.goal(forActivityID: "writing")?.hours == 4)
}

@Test @MainActor
func archivingKeepsChartsGoalsColorsAndHistoryReadOnly() throws {
    let suite = "MinimalTimerTests.ArchiveLocks.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let archives = ActivityArchivePreferences(userDefaults: defaults)
    let goals = ActivityGoalPreferences(userDefaults: defaults, archivePreferences: archives)
    let colors = ActivityColorPreferences(userDefaults: defaults, archivePreferences: archives)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12)))
    let clock = TestClock(date)
    let store = try makeStore(clock: clock, calendar: calendar, archivePreferences: archives)
    store.startActivity(named: "Writing", at: date.addingTimeInterval(-3_600))
    let writing = try #require(store.finishActivity(at: date))
    store.startActivity(named: "Reading", at: date.addingTimeInterval(-1_800))
    _ = store.finishActivity(at: date)
    goals.setGoal(hours: 8, forActivityNamed: "Writing")
    colors.setColor(.red, forActivityID: "writing")
    colors.setColor(.blue, forActivityID: "reading")
    let overview = store.activityOverview(at: date)
    let statistics = store.activityStatistics(at: date)
    let progress = store.weeklyGoalProgress(for: goals.goals, at: date)

    #expect(store.archiveActivity(named: "Writing"))
    #expect(store.activityOverview(at: date) == overview)
    #expect(store.activityStatistics(at: date) == statistics)
    #expect(store.weeklyGoalProgress(for: goals.goals, at: date) == progress)
    #expect(store.dailySummaries.first?.sessions.count == 2)
    #expect(store.recentActivityNames().contains("Writing"))

    colors.setColor(.green, forActivityID: "writing")
    colors.restoreDefaults()
    goals.setGoal(hours: 10, forActivityNamed: "WRITING")
    goals.removeGoal(forActivityID: "writing")
    #expect(colors.customColors["writing"] == .red)
    #expect(colors.customColors["reading"] == nil)
    #expect(goals.goal(forActivityID: "writing")?.hours == 8)
    #expect(ActivityGoalPreferences(userDefaults: defaults).goal(forActivityID: "writing")?.hours == 8)
    let reloadedColor = try #require(ActivityColorPreferences(userDefaults: defaults).customColors["writing"])
    let actual = try #require(NSColor(reloadedColor).usingColorSpace(.sRGB))
    let expected = try #require(NSColor(Color.red).usingColorSpace(.sRGB))
    #expect(abs(actual.redComponent - expected.redComponent) < 0.001)
    #expect(abs(actual.greenComponent - expected.greenComponent) < 0.001)

    #expect(!store.deleteSession(id: writing.id))
    #expect(store.deleteActivityHistory(named: " writing ") == 0)
    store.clearHistory()
    #expect(store.sessions.map(\.id) == [writing.id])
    #expect(store.activityOverview(at: date).activities.map(\.id) == ["writing"])

    archives.unarchiveActivity(id: "writing")
    colors.setColor(.green, forActivityID: "writing")
    #expect(colors.customColors["writing"] == .green)
    goals.removeGoal(forActivityID: "writing")
    #expect(goals.goals.isEmpty)
    #expect(store.deleteSession(id: writing.id))
}

@Test @MainActor
func runningActivitiesMustBeFinishedBeforeArchiving() throws {
    let archives = ActivityArchivePreferences(userDefaults: nil)
    let clock = TestClock(Date())
    let store = try makeStore(clock: clock, archivePreferences: archives)
    store.startActivity(named: "Writing")
    #expect(!store.archiveActivity(named: " WRITING "))
    #expect(!archives.isArchived("writing"))
    #expect(store.activeActivity?.name == "Writing")
    _ = store.finishActivity()
    #expect(store.archiveActivity(named: "Writing"))
    #expect(archives.isArchived("writing"))
}
