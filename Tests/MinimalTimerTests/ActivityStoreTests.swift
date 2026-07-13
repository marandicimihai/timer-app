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
}
