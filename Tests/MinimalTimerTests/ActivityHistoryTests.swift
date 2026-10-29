import Foundation
import SwiftData
import Testing
@testable import MinimalTimer

private func historyCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Chisinau")!
    return calendar
}

private func historyDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
    historyCalendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

@MainActor @discardableResult
private func record(_ name: String, at start: Date, in store: ActivityStore) -> ActivitySession {
    store.startActivity(named: name, at: start)
    return store.finishActivity(at: start.addingTimeInterval(60))!
}

@Test @MainActor
func historyPartitionsThirtyLocalDaysAndOlderMonthsWithoutDuplicates() throws {
    let date = historyDate(2026, 10, 29, hour: 12)
    let store = try makeStore(clock: TestClock(date), calendar: historyCalendar())
    let oldest = record("Last year", at: historyDate(2025, 12, 31, hour: 12), in: store)
    let august = record("August", at: historyDate(2026, 8, 1), in: store)
    let september = record("Before cutoff", at: historyDate(2026, 9, 29, hour: 23), in: store)
    let cutoff = record("At cutoff", at: historyDate(2026, 9, 30), in: store)
    let today = record("Today", at: date, in: store)

    let recent = store.recentHistoryInterval(at: date)
    #expect(recent.start == historyDate(2026, 9, 30))
    #expect(recent.end == historyDate(2026, 10, 30))
    // The local 30-day window includes the autumn daylight-saving transition.
    #expect(recent.duration == 30 * 86_400 + 3_600)

    let recentIDs = try store.historySummaries(from: recent.start, to: recent.end)
        .flatMap(\.sessions).map(\.id)
    #expect(recentIDs == [today.id, cutoff.id])
    let months = try store.historyMonths(before: recent.start)
    #expect(months.map(\.start) == [historyDate(2026, 9, 1), historyDate(2026, 8, 1), historyDate(2025, 12, 1)])
    #expect(months.first?.end == recent.start)
    let olderIDs = try months.flatMap {
        try store.historySummaries(from: $0.start, to: $0.end).flatMap(\.sessions).map(\.id)
    }
    #expect(olderIDs == [september.id, august.id, oldest.id])
    #expect(Set(recentIDs).isDisjoint(with: olderIDs))
}

@Test @MainActor
func monthHistoryLoadsOnlyOnExpansionAndIsReleasedOnCollapse() throws {
    let date = historyDate(2026, 10, 29)
    let store = try makeStore(clock: TestClock(date), calendar: historyCalendar())
    record("August", at: historyDate(2026, 8, 12), in: store)
    let september = record("September", at: historyDate(2026, 9, 12), in: store)
    let browser = ActivityHistoryBrowser(store: store)

    #expect(!browser.hasLoaded)
    browser.reload(at: date)
    #expect(browser.errorMessage == nil)
    #expect(browser.hasLoaded)
    #expect(browser.recentDays.isEmpty)
    #expect(browser.months.count == 2)
    #expect(browser.loadedMonths.isEmpty)
    #expect(browser.expandedMonths.isEmpty)

    let month = try #require(browser.months.first)
    browser.setExpanded(true, month: month)
    #expect(browser.loadedMonths.count == 1)
    #expect(browser.loadedMonths[month.start]?.flatMap(\.sessions).map(\.id) == [september.id])
    browser.setExpanded(false, month: month)
    #expect(browser.loadedMonths.isEmpty)
    #expect(browser.expandedMonths.isEmpty)

    let added = record("Another", at: historyDate(2026, 9, 13), in: store)
    browser.setExpanded(true, month: month)
    #expect(browser.loadedMonths[month.start]?.flatMap(\.sessions).map(\.id) == [added.id, september.id])
}

@Test @MainActor
func deletingADayUsesLocalBoundariesPreservesArchivesAndPersists() throws {
    let day = historyDate(2026, 10, 25)
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: ActivitySession.self, configurations: config)
    let store = ActivityStore(modelContext: container.mainContext, calendar: historyCalendar())
    let previous = record("Previous", at: day.addingTimeInterval(-60), in: store)
    record("Morning", at: day, in: store)
    let archived = record("Protected", at: historyDate(2026, 10, 25, hour: 12), in: store)
    record("Evening", at: historyDate(2026, 10, 26).addingTimeInterval(-60), in: store)
    let next = record("Next", at: historyDate(2026, 10, 26), in: store)
    #expect(store.archiveActivity(named: "Protected"))
    store.startActivity(named: "Running", at: historyDate(2026, 10, 25, hour: 15))

    #expect(store.deleteHistory(on: day) == 2)
    #expect(Set(store.sessions.map(\.id)) == [previous.id, archived.id, next.id])
    #expect(store.activeActivity?.name == "Running")
    #expect(store.deleteHistory(on: day) == 0)
    let reloaded = ActivityStore(modelContext: container.mainContext, calendar: historyCalendar())
    #expect(Set(reloaded.sessions.map(\.id)) == [previous.id, archived.id, next.id])
}

@Test @MainActor
func historyReloadUpdatesOpenMonthsAndRemovesEmptyMonths() throws {
    let date = historyDate(2026, 10, 29)
    let store = try makeStore(clock: TestClock(date), calendar: historyCalendar())
    let august = record("August", at: historyDate(2026, 8, 12), in: store)
    let september = record("September", at: historyDate(2026, 9, 12), in: store)
    let browser = ActivityHistoryBrowser(store: store)
    browser.reload(at: date)
    let month = try #require(browser.months.first)
    browser.setExpanded(true, month: month)
    let added = record("Another", at: historyDate(2026, 9, 13), in: store)
    browser.reload(at: date)
    #expect(browser.expandedMonths == [month.start])
    #expect(browser.loadedMonths[month.start]?.flatMap(\.sessions).map(\.id) == [added.id, september.id])
    #expect(browser.loadedMonths.count == 1)

    #expect(store.deleteSession(id: added.id))
    #expect(store.deleteSession(id: september.id))
    browser.reload(at: date)
    #expect(browser.months.count == 1)
    #expect(browser.loadedMonths.isEmpty)
    #expect(browser.expandedMonths.isEmpty)
    #expect(store.deleteSession(id: august.id))
    browser.reload(at: date)
    #expect(browser.months.isEmpty)
    #expect(browser.recentDays.isEmpty)
    #expect(!browser.hasUnarchivedHistory)
}

@Test @MainActor
func historyClearAvailabilityIncludesOlderUnarchivedEntries() throws {
    let date = historyDate(2026, 10, 29)
    let store = try makeStore(clock: TestClock(date), calendar: historyCalendar())
    for index in 0..<101 {
        record("Protected", at: date.addingTimeInterval(Double(index) * 60), in: store)
    }
    #expect(store.archiveActivity(named: "Protected"))
    #expect(try !store.hasUnarchivedHistory())
    record("Older", at: historyDate(2025, 1, 1), in: store)
    #expect(try store.hasUnarchivedHistory())
    store.clearHistory()
    #expect(try !store.hasUnarchivedHistory())
    #expect(store.sessions.count == 101)
}
