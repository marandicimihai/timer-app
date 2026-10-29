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

struct KnownActivity: Codable, Identifiable, Equatable {
    let id: String
    let name: String
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
    let days: [ActivityDayStatistics]
    let totalDuration: TimeInterval
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
    @Published private(set) var historyRevision = 0
    let archivePreferences: ActivityArchivePreferences

    // Analytics can request all sessions, but opening History only fetches its
    // visible date ranges. Keep the full-history cache lazy and invalidate on writes.
    private var cachedSessions: [ActivitySession]?
    var sessions: [ActivitySession] {
        if let cachedSessions { return cachedSessions }
        let descriptor = FetchDescriptor<ActivitySession>(
            sortBy: [SortDescriptor(\ActivitySession.startedAt, order: .reverse)]
        )
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        cachedSessions = fetched
        return fetched
    }

    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let now: () -> Date
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        archivePreferences: ActivityArchivePreferences? = nil
    ) {
        self.modelContainer = modelContext.container
        self.modelContext = modelContext
        self.now = now
        self.calendar = calendar
        self.archivePreferences = archivePreferences ?? ActivityArchivePreferences(userDefaults: nil)
    }

    func startActivity(named rawName: String, at date: Date? = nil) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        archivePreferences.unarchiveActivity(id: normalizedActivityName(name))

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
        self.activeActivity = nil
        return session
    }

    func endActivityForTermination() {
        _ = finishActivity()
    }

    func clearHistory() {
        let removable = sessions.filter { !isArchived(activityNamed: $0.name) }
        for session in removable {
            modelContext.delete(session)
        }
        saveHistory()
    }

    @discardableResult
    func deleteSession(id: UUID) -> Bool {
        let descriptor = FetchDescriptor<ActivitySession>(predicate: #Predicate { $0.id == id })
        guard let session = try? modelContext.fetch(descriptor).first,
              !isArchived(activityNamed: session.name) else { return false }
        modelContext.delete(session)
        saveHistory()
        return true
    }

    @discardableResult
    func deleteHistory(on day: Date) -> Int {
        guard let interval = calendar.dateInterval(of: .day, for: day),
              let daySessions = try? historySessions(from: interval.start, to: interval.end) else { return 0 }
        let removable = daySessions.filter { !isArchived(activityNamed: $0.name) }
        guard !removable.isEmpty else { return 0 }
        for session in removable {
            modelContext.delete(session)
        }
        saveHistory()
        return removable.count
    }

    @discardableResult
    func deleteActivityHistory(named rawName: String) -> Int {
        let normalizedName = normalizedActivityName(rawName)
        guard !normalizedName.isEmpty, !archivePreferences.isArchived(normalizedName) else { return 0 }

        let matchingSessions = sessions.filter {
            normalizedActivityName($0.name) == normalizedName
        }
        guard !matchingSessions.isEmpty else { return 0 }

        for session in matchingSessions {
            modelContext.delete(session)
        }
        saveHistory()
        return matchingSessions.count
    }

    // Explicit activity deletion also removes archived history. Ordinary history
    // deletion continues to protect archives.
    @discardableResult
    func deleteActivity(named rawName: String) throws -> Bool {
        let id = normalizedActivityName(rawName)
        guard !id.isEmpty,
              activeActivity.map({ normalizedActivityName($0.name) }) != id else { return false }

        let matchingSessions = try modelContext.fetch(FetchDescriptor<ActivitySession>()).filter {
            normalizedActivityName($0.name) == id
        }
        for session in matchingSessions {
            modelContext.delete(session)
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        archivePreferences.unarchiveActivity(id: id)
        cachedSessions = nil
        historyRevision += 1
        return true
    }

    var dailySummaries: [DailyActivitySummary] {
        dailySummaries(for: sessions)
    }

    func recentHistoryInterval(at date: Date) -> DateInterval {
        let today = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? date
        return DateInterval(start: start, end: end)
    }

    func historySummaries(from start: Date, to end: Date) throws -> [DailyActivitySummary] {
        dailySummaries(for: try historySessions(from: start, to: end))
    }

    // Discover only months that contain older entries. One date per month is
    // fetched; the month's sessions are fetched only when its disclosure opens.
    func historyMonths(before cutoff: Date) throws -> [DateInterval] {
        var months: [DateInterval] = []
        var upperBound = cutoff
        while true {
            let bound = upperBound
            var descriptor = FetchDescriptor<ActivitySession>(
                predicate: #Predicate { $0.startedAt < bound },
                sortBy: [SortDescriptor(\ActivitySession.startedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            descriptor.propertiesToFetch = [\ActivitySession.startedAt]
            guard let latest = try modelContext.fetch(descriptor).first,
                  let month = calendar.dateInterval(of: .month, for: latest.startedAt) else { break }
            months.append(DateInterval(start: month.start, end: min(month.end, cutoff)))
            upperBound = month.start
        }
        return months
    }

    func hasUnarchivedHistory() throws -> Bool {
        if archivePreferences.archivedActivities.isEmpty {
            var descriptor = FetchDescriptor<ActivitySession>()
            descriptor.fetchLimit = 1
            return try modelContext.fetchCount(descriptor) > 0
        }

        var descriptor = FetchDescriptor<ActivitySession>()
        descriptor.propertiesToFetch = [\ActivitySession.name]
        descriptor.fetchLimit = 100
        while true {
            let batch = try modelContext.fetch(descriptor)
            if batch.contains(where: { !isArchived(activityNamed: $0.name) }) { return true }
            if batch.count < 100 { return false }
            descriptor.fetchOffset = (descriptor.fetchOffset ?? 0) + batch.count
        }
    }

    private func historySessions(from start: Date, to end: Date) throws -> [ActivitySession] {
        try modelContext.fetch(FetchDescriptor<ActivitySession>(
            predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end },
            sortBy: [SortDescriptor(\ActivitySession.startedAt, order: .reverse)]
        ))
    }

    private func dailySummaries(for sessions: [ActivitySession]) -> [DailyActivitySummary] {
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

    func recentActivityNames(limit: Int = .max) -> [String] {
        guard limit > 0 else { return [] }
        let activeName = activeActivity.map { normalizedActivityName($0.name) }
        var seenNames: Set<String> = []
        var names: [String] = []
        var descriptor = FetchDescriptor<ActivitySession>(
            sortBy: [SortDescriptor(\ActivitySession.startedAt, order: .reverse)]
        )
        descriptor.propertiesToFetch = [\ActivitySession.name, \ActivitySession.startedAt]
        descriptor.fetchLimit = 100
        while let batch = try? modelContext.fetch(descriptor) {
            for session in batch {
                let normalizedName = normalizedActivityName(session.name)
                guard normalizedName != activeName, seenNames.insert(normalizedName).inserted else { continue }
                names.append(session.name)
                if names.count == limit { return names }
            }
            if batch.count < 100 { break }
            descriptor.fetchOffset = (descriptor.fetchOffset ?? 0) + batch.count
        }
        return names
    }

    var knownActivities: [KnownActivity] {
        var activityData: [String: (name: String, latestStart: Date)] = [:]

        for activity in archivePreferences.archivedActivities {
            activityData[activity.id] = (name: activity.name, latestStart: .distantPast)
        }

        var descriptor = FetchDescriptor<ActivitySession>()
        descriptor.propertiesToFetch = [\ActivitySession.name, \ActivitySession.startedAt]
        for session in (try? modelContext.fetch(descriptor)) ?? [] {
            let id = normalizedActivityName(session.name)
            guard !id.isEmpty else { continue }
            if let existing = activityData[id], existing.latestStart >= session.startedAt {
                continue
            }
            activityData[id] = (name: session.name, latestStart: session.startedAt)
        }

        if let activeActivity {
            let id = normalizedActivityName(activeActivity.name)
            if !id.isEmpty {
                activityData[id] = (name: activeActivity.name, latestStart: activeActivity.startedAt)
            }
        }

        return activityData.sorted {
            if $0.value.latestStart != $1.value.latestStart {
                return $0.value.latestStart > $1.value.latestStart
            }
            return $0.key < $1.key
        }
        .map { id, data in
            KnownActivity(id: id, name: data.name)
        }
    }

    func isArchived(activityNamed name: String) -> Bool {
        archivePreferences.isArchived(normalizedActivityName(name))
    }

    @discardableResult
    func archiveActivity(named name: String) -> Bool {
        let id = normalizedActivityName(name)
        guard !id.isEmpty,
              activeActivity.map({ normalizedActivityName($0.name) }) != id else { return false }
        archivePreferences.archiveActivity(named: name)
        return true
    }

    func weeklyGoalProgress(
        for goals: [WeeklyActivityGoal],
        at referenceDate: Date
    ) -> [ActivityGoalProgress] {
        let today = calendar.startOfDay(for: referenceDate)
        // Calendar weekdays are Sunday = 1, Monday = 2. Goals reset on Monday
        // in the user's time zone, independently of the chart's rolling week.
        let daysSinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        let weekStart = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        var durations: [String: TimeInterval] = [:]

        func accumulate(name: String, start: Date, end: Date) {
            let duration = max(0, min(end, referenceDate).timeIntervalSince(max(start, weekStart)))
            durations[normalizedActivityName(name), default: 0] += duration
        }

        for session in sessionsOverlapping(from: weekStart, to: referenceDate) {
            accumulate(name: session.name, start: session.startedAt, end: session.endedAt)
        }
        if let activeActivity {
            accumulate(name: activeActivity.name, start: activeActivity.startedAt, end: referenceDate)
        }

        return goals.map { ActivityGoalProgress(goal: $0, duration: durations[$0.id, default: 0]) }
    }

    func activityOverview(at referenceDate: Date) -> ActivityOverview {
        let today = calendar.startOfDay(for: referenceDate)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        var activityData: [String: (name: String, latestStart: Date, durations: [TimeInterval])] = [:]
        var intervals = sessionsOverlapping(from: weekStart, to: referenceDate)
            .map { (name: $0.name, start: $0.startedAt, end: $0.endedAt) }
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
                dailyDurations: [TimeInterval]
            )
        ] = [:]
        var intervals = sessionsOverlapping(from: days.first ?? today, to: referenceDate)
            .map { (name: $0.name, start: $0.startedAt, end: $0.endedAt) }
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
                    dailyDurations: Array(repeating: 0, count: dayCount)
                )
            if interval.start > data.latestStart {
                data.name = interval.name
                data.latestStart = interval.start
            }

            for (index, day) in days.enumerated() {
                let duration = overlapDuration(
                    from: interval.start,
                    to: interval.end,
                    on: day,
                    through: referenceDate
                )
                data.dailyDurations[index] += duration
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
                days: zip(days, data.dailyDurations).map {
                    ActivityDayStatistics(day: $0.0, duration: $0.1)
                },
                totalDuration: totalDuration,
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
            activeDayCount: dailyDurations.count(where: { $0 > 0 }),
            currentStreak: currentStreak(in: dailyDurations),
            bestStreak: bestStreak(in: dailyDurations)
        )
    }

    private func sessionsOverlapping(from start: Date, to end: Date) -> [ActivitySession] {
        let descriptor = FetchDescriptor<ActivitySession>(
            predicate: #Predicate { $0.endedAt > start && $0.startedAt < end }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func saveHistory() {
        try? modelContext.save()
        cachedSessions = nil
        historyRevision += 1
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
