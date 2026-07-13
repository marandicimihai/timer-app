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
}
