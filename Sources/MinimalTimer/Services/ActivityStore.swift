import Combine
import Foundation
import SwiftData

struct DailyActivitySummary: Identifiable {
    let day: Date
    let sessions: [ActivitySession]

    var id: Date { day }
    var totalDuration: TimeInterval { sessions.reduce(0) { $0 + $1.duration } }
}

struct ActivitySeries: Identifiable, Equatable {
    let id: String
    let name: String
    let todayDuration: TimeInterval
    let yesterdayDuration: TimeInterval
    let sevenDayDuration: TimeInterval

    var weeklyDailyAverage: TimeInterval { sevenDayDuration / 7 }
}

struct ActivityOverview: Equatable {
    let activities: [ActivitySeries]

    var todayDuration: TimeInterval {
        activities.reduce(0) { $0 + $1.todayDuration }
    }

    var yesterdayDuration: TimeInterval {
        activities.reduce(0) { $0 + $1.yesterdayDuration }
    }

    var weeklyDailyAverage: TimeInterval {
        activities.reduce(0) { $0 + $1.sevenDayDuration } / 7
    }

    func chartSeries(maxNamedActivities: Int = 5) -> [ActivitySeries] {
        guard maxNamedActivities > 0, activities.count > maxNamedActivities else { return activities }

        let namedActivities = Array(activities.prefix(maxNamedActivities))
        let remainingActivities = activities.dropFirst(maxNamedActivities)
        let other = ActivitySeries(
            id: "aggregate:other",
            name: "Other activities",
            todayDuration: remainingActivities.reduce(0) { $0 + $1.todayDuration },
            yesterdayDuration: remainingActivities.reduce(0) { $0 + $1.yesterdayDuration },
            sevenDayDuration: remainingActivities.reduce(0) { $0 + $1.sevenDayDuration }
        )
        return namedActivities + [other]
    }
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
        var activityData: [String: (name: String, latestStart: Date, durations: [TimeInterval])] = [:]
        var intervals = sessions.map { (name: $0.name, start: $0.startedAt, end: $0.endedAt) }
        if let activeActivity {
            intervals.append((
                name: activeActivity.name,
                start: activeActivity.startedAt,
                end: max(referenceDate, activeActivity.startedAt)
            ))
        }

        for interval in intervals {
            let normalizedName = interval.name.lowercased()
            var data = activityData[normalizedName]
                ?? (name: interval.name, latestStart: interval.start, durations: Array(repeating: 0, count: 7))
            if interval.start > data.latestStart {
                data.name = interval.name
                data.latestStart = interval.start
            }

            for daysAgo in 0..<7 {
                let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
                data.durations[daysAgo] += overlapDuration(
                    from: interval.start,
                    to: interval.end,
                    on: day,
                    through: referenceDate
                )
            }
            activityData[normalizedName] = data
        }

        let activities = activityData.compactMap { normalizedName, data -> ActivitySeries? in
            let sevenDayDuration = data.durations.reduce(0, +)
            guard sevenDayDuration > 0 else { return nil }
            return ActivitySeries(
                id: normalizedName,
                name: data.name,
                todayDuration: data.durations[0],
                yesterdayDuration: data.durations[1],
                sevenDayDuration: sevenDayDuration
            )
        }
        .sorted {
            if $0.sevenDayDuration == $1.sevenDayDuration {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.sevenDayDuration > $1.sevenDayDuration
        }

        return ActivityOverview(activities: activities)
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

    private func overlapDuration(
        from intervalStart: Date,
        to intervalEnd: Date,
        on day: Date,
        through referenceDate: Date
    ) -> TimeInterval {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }
        let overlapStart = max(intervalStart, dayStart)
        let overlapEnd = min(intervalEnd, dayEnd, referenceDate)
        return max(0, overlapEnd.timeIntervalSince(overlapStart))
    }
}
