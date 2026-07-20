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

enum ActivityChartPeriod: String, CaseIterable, Identifiable {
    case today
    case yesterday
    case sevenDayAverage

    var id: String { rawValue }

    func duration(for activity: ActivitySeries) -> TimeInterval {
        switch self {
        case .today:
            activity.todayDuration
        case .yesterday:
            activity.yesterdayDuration
        case .sevenDayAverage:
            activity.weeklyDailyAverage
        }
    }
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

    func chartSeries(
        for period: ActivityChartPeriod,
        maxNamedActivities: Int = 5
    ) -> [ActivitySeries] {
        chartSeries(maxNamedActivities: maxNamedActivities).filter {
            period.duration(for: $0) > 0
        }
    }
}

struct ActivityDayStatistics: Identifiable, Equatable {
    let day: Date
    let duration: TimeInterval

    var id: Date { day }
}

struct ActivityStatistics: Identifiable, Equatable {
    let id: String
    let name: String
    let totalDuration: TimeInterval
    let sessionCount: Int
    let activeDayCount: Int
    let currentStreak: Int
    let bestStreak: Int
    let consistency: Double
}

struct ActivityStatisticsSnapshot: Equatable {
    let dayCount: Int
    let days: [ActivityDayStatistics]
    let activities: [ActivityStatistics]
    let totalDuration: TimeInterval
    let sessionCount: Int
    let activeDayCount: Int
    let currentStreak: Int
    let bestStreak: Int

    var consistency: Double {
        guard dayCount > 0 else { return 0 }
        return Double(activeDayCount) / Double(dayCount)
    }

    var averagePerActiveDay: TimeInterval {
        guard activeDayCount > 0 else { return 0 }
        return totalDuration / Double(activeDayCount)
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

    @discardableResult
    func deleteSession(id: UUID) -> Bool {
        guard let session = sessions.first(where: { $0.id == id }) else { return false }
        modelContext.delete(session)
        saveHistory()
        sessions.removeAll { $0.id == id }
        return true
    }

    @discardableResult
    func deleteActivityHistory(named rawName: String) -> Int {
        let normalizedName = normalizedActivityName(rawName)
        guard !normalizedName.isEmpty else { return 0 }

        let matchingSessions = sessions.filter {
            normalizedActivityName($0.name) == normalizedName
        }
        guard !matchingSessions.isEmpty else { return 0 }

        let matchingIDs = Set(matchingSessions.map(\.id))
        for session in matchingSessions {
            modelContext.delete(session)
        }
        saveHistory()
        sessions.removeAll { matchingIDs.contains($0.id) }
        return matchingSessions.count
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
        let activeName = activeActivity.map { normalizedActivityName($0.name) }
        var seenNames: Set<String> = []
        var names: [String] = []

        for session in sessions.sorted(by: { $0.startedAt > $1.startedAt }) {
            let normalizedName = normalizedActivityName(session.name)
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
            let normalizedName = normalizedActivityName(interval.name)
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

    func activityStatistics(
        at referenceDate: Date,
        dayCount requestedDayCount: Int = 30
    ) -> ActivityStatisticsSnapshot {
        let dayCount = max(1, requestedDayCount)
        let today = calendar.startOfDay(for: referenceDate)
        let days = (0..<dayCount).reversed().map { daysAgo in
            calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
        }
        var activityData: [
            String: (
                name: String,
                latestStart: Date,
                dailyDurations: [TimeInterval],
                sessionCount: Int
            )
        ] = [:]
        var intervals = sessions.map { (name: $0.name, start: $0.startedAt, end: $0.endedAt) }
        if let activeActivity {
            intervals.append((
                name: activeActivity.name,
                start: activeActivity.startedAt,
                end: max(referenceDate, activeActivity.startedAt)
            ))
        }

        for interval in intervals {
            let normalizedName = normalizedActivityName(interval.name)
            var data = activityData[normalizedName]
                ?? (
                    name: interval.name,
                    latestStart: interval.start,
                    dailyDurations: Array(repeating: 0, count: dayCount),
                    sessionCount: 0
                )
            if interval.start > data.latestStart {
                data.name = interval.name
                data.latestStart = interval.start
            }

            var overlapsPeriod = false
            for (index, day) in days.enumerated() {
                let duration = overlapDuration(
                    from: interval.start,
                    to: interval.end,
                    on: day,
                    through: referenceDate
                )
                data.dailyDurations[index] += duration
                overlapsPeriod = overlapsPeriod || duration > 0
            }
            if overlapsPeriod {
                data.sessionCount += 1
            }
            activityData[normalizedName] = data
        }

        let activities = activityData.compactMap { normalizedName, data -> ActivityStatistics? in
            let totalDuration = data.dailyDurations.reduce(0, +)
            guard totalDuration > 0 else { return nil }
            let activeDayCount = data.dailyDurations.count(where: { $0 > 0 })
            return ActivityStatistics(
                id: normalizedName,
                name: data.name,
                totalDuration: totalDuration,
                sessionCount: data.sessionCount,
                activeDayCount: activeDayCount,
                currentStreak: currentStreak(in: data.dailyDurations),
                bestStreak: bestStreak(in: data.dailyDurations),
                consistency: Double(activeDayCount) / Double(dayCount)
            )
        }
        .sorted {
            if $0.totalDuration == $1.totalDuration {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.totalDuration > $1.totalDuration
        }

        let dailyDurations = days.indices.map { index in
            activities.reduce(0) { total, activity in
                guard let data = activityData[activity.id] else { return total }
                return total + data.dailyDurations[index]
            }
        }
        let dayStatistics = zip(days, dailyDurations).map {
            ActivityDayStatistics(day: $0.0, duration: $0.1)
        }

        return ActivityStatisticsSnapshot(
            dayCount: dayCount,
            days: dayStatistics,
            activities: activities,
            totalDuration: dailyDurations.reduce(0, +),
            sessionCount: activities.reduce(0) { $0 + $1.sessionCount },
            activeDayCount: dailyDurations.count(where: { $0 > 0 }),
            currentStreak: currentStreak(in: dailyDurations),
            bestStreak: bestStreak(in: dailyDurations)
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

    private func normalizedActivityName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

    private func currentStreak(in dailyDurations: [TimeInterval]) -> Int {
        guard !dailyDurations.isEmpty else { return 0 }
        var index = dailyDurations.count - 1

        // A streak remains current through the end of today, even before the
        // user has recorded today's first activity.
        if dailyDurations[index] <= 0 {
            index -= 1
        }

        var streak = 0
        while index >= 0, dailyDurations[index] > 0 {
            streak += 1
            index -= 1
        }
        return streak
    }

    private func bestStreak(in dailyDurations: [TimeInterval]) -> Int {
        var best = 0
        var current = 0
        for duration in dailyDurations {
            if duration > 0 {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }
}
