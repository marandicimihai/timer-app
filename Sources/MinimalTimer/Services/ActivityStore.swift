import Combine
import Foundation
import SwiftData

struct DailyActivitySummary: Identifiable {
    let day: Date
    let sessions: [ActivitySession]

    var id: Date { day }
    var totalDuration: TimeInterval { sessions.reduce(0) { $0 + $1.duration } }
}

struct ActivityOverview: Equatable {
    let todayDuration: TimeInterval
    let yesterdayDuration: TimeInterval
    let weeklyDailyAverage: TimeInterval
}

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var activeActivity: ActiveActivity?
    @Published private(set) var sessions: [ActivitySession] = []

    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let now: () -> Date
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.modelContainer = modelContext.container
        self.modelContext = modelContext
        self.now = now
        self.calendar = calendar
        reloadHistory()
    }

    func startActivity(named rawName: String, at date: Date? = nil) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if activeActivity != nil {
            _ = finishActivity(at: date ?? now())
        }
        activeActivity = ActiveActivity(name: name, startedAt: date ?? now())
    }

    @discardableResult
    func finishActivity(at date: Date? = nil) -> ActivitySession? {
        guard let activeActivity else { return nil }
        let end = max(date ?? now(), activeActivity.startedAt)
        let session = ActivitySession(
            id: activeActivity.id,
            name: activeActivity.name,
            startedAt: activeActivity.startedAt,
            endedAt: end
        )
        modelContext.insert(session)
        saveHistory()
        sessions.insert(session, at: 0)
        self.activeActivity = nil
        return session
    }

    func endActivityForTermination() {
        _ = finishActivity()
    }

    func clearHistory() {
        for session in sessions {
            modelContext.delete(session)
        }
        saveHistory()
        sessions = []
    }

    var dailySummaries: [DailyActivitySummary] {
        let grouped = Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.startedAt)
        }

        return grouped
            .map { day, sessions in
                DailyActivitySummary(
                    day: day,
                    sessions: sessions.sorted { $0.startedAt > $1.startedAt }
                )
            }
            .sorted { $0.day > $1.day }
    }

    func recentActivityNames(limit: Int = 3) -> [String] {
        guard limit > 0 else { return [] }
        let activeName = activeActivity?.name.lowercased()
        var seenNames: Set<String> = []
        var names: [String] = []

        for session in sessions.sorted(by: { $0.startedAt > $1.startedAt }) {
            let normalizedName = session.name.lowercased()
            guard normalizedName != activeName, seenNames.insert(normalizedName).inserted else { continue }
            names.append(session.name)
            if names.count == limit { break }
        }
        return names
    }

    func activityOverview(at referenceDate: Date) -> ActivityOverview {
        let today = calendar.startOfDay(for: referenceDate)
        let durations = (0..<7).map { daysAgo -> TimeInterval in
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            return loggedDuration(on: day, through: referenceDate)
        }

        return ActivityOverview(
            todayDuration: durations[0],
            yesterdayDuration: durations[1],
            weeklyDailyAverage: durations.reduce(0, +) / 7
        )
    }

    private func reloadHistory() {
        let descriptor = FetchDescriptor<ActivitySession>(
            sortBy: [SortDescriptor(\ActivitySession.startedAt, order: .reverse)]
        )
        sessions = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func saveHistory() {
        try? modelContext.save()
    }

    private func loggedDuration(on day: Date, through referenceDate: Date) -> TimeInterval {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }

        var intervals = sessions.map { ($0.startedAt, $0.endedAt) }
        if let activeActivity {
            intervals.append((activeActivity.startedAt, max(referenceDate, activeActivity.startedAt)))
        }

        return intervals.reduce(0) { total, interval in
            let overlapStart = max(interval.0, dayStart)
            let overlapEnd = min(interval.1, dayEnd, referenceDate)
            return total + max(0, overlapEnd.timeIntervalSince(overlapStart))
        }
    }
}
