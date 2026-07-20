import Foundation
import SwiftData
import Testing
@testable import MinimalTimer

@MainActor
final class TestClock {
    var date: Date

    init(_ date: Date) {
        self.date = date
    }
}

@MainActor
func makeStore(clock: TestClock, calendar: Calendar = .current) throws -> ActivityStore {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: ActivitySession.self, configurations: configuration)
    return ActivityStore(modelContext: container.mainContext, now: { clock.date }, calendar: calendar)
}

@Test @MainActor
func finishingAnActivityPersistsItsDuration() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)

    store.startActivity(named: "Writing")
    clock.date.addTimeInterval(90)
    let session = store.finishActivity()

    #expect(session?.name == "Writing")
    #expect(session?.duration == 90)
    #expect(store.activeActivity == nil)
    #expect(store.sessions.count == 1)
}

@Test @MainActor
func startingAnotherActivityFinishesTheFirst() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)

    store.startActivity(named: "Planning")
    clock.date.addTimeInterval(120)
    store.startActivity(named: "Coding")

    #expect(store.sessions.count == 1)
    #expect(store.sessions.first?.name == "Planning")
    #expect(store.sessions.first?.duration == 120)
    #expect(store.activeActivity?.name == "Coding")
}

@Test @MainActor
func historyReloadsFromTheSameLocalStore() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: ActivitySession.self, configurations: configuration)
    let store = ActivityStore(modelContext: container.mainContext, now: { clock.date })

    store.startActivity(named: "Research")
    clock.date.addTimeInterval(300)
    _ = store.finishActivity()

    let reloadedStore = ActivityStore(modelContext: container.mainContext, now: { clock.date })
    #expect(reloadedStore.sessions.count == 1)
    #expect(reloadedStore.sessions.first?.duration == 300)
}

@Test @MainActor
func dailySummariesGroupActivitiesAndHistoryCanBeCleared() throws {
    let calendar = Calendar(identifier: .gregorian)
    let dayOne = Date(timeIntervalSince1970: 86_400 * 20 + 10 * 3_600)
    let clock = TestClock(dayOne)
    let store = try makeStore(clock: clock, calendar: calendar)

    store.startActivity(named: "Morning")
    clock.date.addTimeInterval(600)
    _ = store.finishActivity()

    clock.date = Date(timeIntervalSince1970: 86_400 * 21 + 11 * 3_600)
    store.startActivity(named: "Afternoon")
    clock.date.addTimeInterval(900)
    _ = store.finishActivity()

    #expect(store.dailySummaries.count == 2)
    #expect(store.dailySummaries.map(\.totalDuration).sorted() == [600, 900])

    store.clearHistory()
    #expect(store.sessions.isEmpty)
    #expect(store.dailySummaries.isEmpty)
    #expect(store.recentActivityNames().isEmpty)
}

@Test @MainActor
func recentActivityNamesAreUniqueAndNewestFirst() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)

    for name in ["Writing", "Email", "writing", "Planning"] {
        store.startActivity(named: name)
        clock.date.addTimeInterval(60)
        _ = store.finishActivity()
    }

    #expect(store.recentActivityNames(limit: 3) == ["Planning", "writing", "Email"])

    store.startActivity(named: "Planning")
    #expect(store.recentActivityNames(limit: 3) == ["writing", "Email"])
}

@Test @MainActor
func deletingOneSessionKeepsTheRestOfHistory() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)

    store.startActivity(named: "Writing")
    clock.date.addTimeInterval(60)
    let sessionToDelete = store.finishActivity()!

    store.startActivity(named: "Writing")
    clock.date.addTimeInterval(120)
    _ = store.finishActivity()

    store.startActivity(named: "Planning")
    clock.date.addTimeInterval(180)
    _ = store.finishActivity()

    #expect(store.deleteSession(id: sessionToDelete.id))
    #expect(store.sessions.count == 2)
    #expect(store.sessions.map(\.duration).sorted() == [120, 180])
    #expect(store.dailySummaries.first?.totalDuration == 300)
    #expect(!store.deleteSession(id: sessionToDelete.id))
}

@Test @MainActor
func deletingActivityHistoryRemovesEveryCaseVariantAndPersists() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: ActivitySession.self, configurations: configuration)
    let store = ActivityStore(modelContext: container.mainContext, now: { clock.date })

    for name in ["Writng", "Planning", "writng"] {
        store.startActivity(named: name)
        clock.date.addTimeInterval(60)
        _ = store.finishActivity()
    }

    #expect(store.deleteActivityHistory(named: "  WRITNG  ") == 2)
    #expect(store.sessions.map(\.name) == ["Planning"])
    #expect(store.recentActivityNames() == ["Planning"])
    #expect(store.deleteActivityHistory(named: "Missing") == 0)

    let reloadedStore = ActivityStore(modelContext: container.mainContext, now: { clock.date })
    #expect(reloadedStore.sessions.map(\.name) == ["Planning"])
}

@Test @MainActor
func activityOverviewIncludesActiveTimeAndSplitsSessionsAcrossMidnight() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13))!
    let referenceDate = calendar.date(byAdding: .hour, value: 12, to: today)!
    let clock = TestClock(referenceDate)
    let store = try makeStore(clock: clock, calendar: calendar)

    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
    store.startActivity(named: "Yesterday", at: calendar.date(byAdding: .hour, value: 10, to: yesterday)!)
    _ = store.finishActivity(at: calendar.date(byAdding: .hour, value: 12, to: yesterday)!)

    store.startActivity(named: "Across midnight", at: calendar.date(byAdding: .minute, value: -30, to: today)!)
    _ = store.finishActivity(at: calendar.date(byAdding: .minute, value: 30, to: today)!)

    let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
    store.startActivity(named: "Earlier", at: calendar.date(byAdding: .hour, value: 8, to: twoDaysAgo)!)
    _ = store.finishActivity(at: calendar.date(byAdding: .minute, value: 690, to: twoDaysAgo)!)

    store.startActivity(named: "Today", at: calendar.date(byAdding: .hour, value: 9, to: today)!)
    _ = store.finishActivity(at: calendar.date(byAdding: .hour, value: 10, to: today)!)

    store.startActivity(named: "Active", at: calendar.date(byAdding: .minute, value: 690, to: today)!)

    let overview = store.activityOverview(at: referenceDate)
    #expect(overview.todayDuration == 7_200)
    #expect(overview.yesterdayDuration == 9_000)
    #expect(overview.weeklyDailyAverage == 28_800.0 / 7.0)

    let midnightActivity = overview.activities.first { $0.name == "Across midnight" }
    #expect(midnightActivity?.todayDuration == 1_800)
    #expect(midnightActivity?.yesterdayDuration == 1_800)
    #expect(midnightActivity?.weeklyDailyAverage == 3_600.0 / 7.0)

    let activeActivity = overview.activities.first { $0.name == "Active" }
    #expect(activeActivity?.todayDuration == 1_800)
    #expect(activeActivity?.yesterdayDuration == 0)

    let todayNames = Set(overview.chartSeries(for: .today).map(\.name))
    let yesterdayNames = Set(overview.chartSeries(for: .yesterday).map(\.name))
    #expect(todayNames == ["Across midnight", "Today", "Active"])
    #expect(yesterdayNames == ["Yesterday", "Across midnight"])
}

@Test
func chartSeriesOmitsActivitiesWithNoTimeInTheRequestedPeriod() {
    let overview = ActivityOverview(activities: [
        ActivitySeries(
            id: "today",
            name: "Today only",
            todayDuration: 600,
            yesterdayDuration: 0,
            sevenDayDuration: 600
        ),
        ActivitySeries(
            id: "yesterday",
            name: "Yesterday only",
            todayDuration: 0,
            yesterdayDuration: 900,
            sevenDayDuration: 900
        )
    ])

    #expect(overview.chartSeries(for: .today).map(\.name) == ["Today only"])
    #expect(overview.chartSeries(for: .yesterday).map(\.name) == ["Yesterday only"])
    #expect(
        overview.chartSeries(for: .sevenDayAverage).map(\.name)
            == ["Today only", "Yesterday only"]
    )
}

@Test @MainActor
func chartKeepsFiveActivitiesAndCombinesTheRestAsOther() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13))!
    let referenceDate = calendar.date(byAdding: .hour, value: 12, to: today)!
    let clock = TestClock(referenceDate)
    let store = try makeStore(clock: clock, calendar: calendar)

    for index in 1...7 {
        let start = calendar.date(byAdding: .minute, value: index * 10, to: today)!
        store.startActivity(named: "Activity \(index)", at: start)
        _ = store.finishActivity(at: start.addingTimeInterval(TimeInterval(index * 60)))
    }

    let series = store.activityOverview(at: referenceDate).chartSeries()
    #expect(series.count == 6)
    #expect(series.prefix(5).map(\.name) == ["Activity 7", "Activity 6", "Activity 5", "Activity 4", "Activity 3"])
    #expect(series.last?.name == "Other activities")
    #expect(series.last?.todayDuration == 180)
}

@Test @MainActor
func activityStatisticsReportTimeConsistencyAndStreaks() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20))!
    let referenceDate = calendar.date(byAdding: .hour, value: 12, to: today)!
    let clock = TestClock(referenceDate)
    let store = try makeStore(clock: clock, calendar: calendar)

    func addSession(name: String, daysAgo: Int, duration: TimeInterval) {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
        let start = calendar.date(byAdding: .hour, value: 9, to: day)!
        store.startActivity(named: name, at: start)
        _ = store.finishActivity(at: start.addingTimeInterval(duration))
    }

    addSession(name: "Writing", daysAgo: 4, duration: 600)
    addSession(name: "writing", daysAgo: 3, duration: 1_200)
    addSession(name: "Writing", daysAgo: 2, duration: 1_800)
    addSession(name: "Exercise", daysAgo: 1, duration: 900)
    addSession(name: "Exercise", daysAgo: 0, duration: 1_500)

    let statistics = store.activityStatistics(at: referenceDate, dayCount: 7)

    #expect(statistics.totalDuration == 6_000)
    #expect(statistics.sessionCount == 5)
    #expect(statistics.activeDayCount == 5)
    #expect(statistics.currentStreak == 5)
    #expect(statistics.bestStreak == 5)
    #expect(statistics.days.count == 7)
    #expect(statistics.activities.map(\.name) == ["Writing", "Exercise"])

    let writing = statistics.activities.first { $0.id == "writing" }
    #expect(writing?.totalDuration == 3_600)
    #expect(writing?.sessionCount == 3)
    #expect(writing?.activeDayCount == 3)
    #expect(writing?.currentStreak == 0)
    #expect(writing?.bestStreak == 3)
    #expect(writing?.consistency == 3.0 / 7.0)

    let exercise = statistics.activities.first { $0.id == "exercise" }
    #expect(exercise?.currentStreak == 2)
    #expect(exercise?.bestStreak == 2)
}

@Test @MainActor
func activityStatisticsKeepYesterdayStreakCurrentUntilTodayIsLogged() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20))!
    let referenceDate = calendar.date(byAdding: .hour, value: 8, to: today)!
    let clock = TestClock(referenceDate)
    let store = try makeStore(clock: clock, calendar: calendar)

    for daysAgo in [2, 1] {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
        let start = calendar.date(byAdding: .hour, value: 9, to: day)!
        store.startActivity(named: "Reading", at: start)
        _ = store.finishActivity(at: start.addingTimeInterval(600))
    }

    let statistics = store.activityStatistics(at: referenceDate, dayCount: 7)
    #expect(statistics.currentStreak == 2)
    #expect(statistics.activities.first?.currentStreak == 2)
}
