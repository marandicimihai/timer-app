import Combine
import Foundation
import SwiftData

struct DailyActivitySummary: Identifiable {
    let day: Date
    let sessions: [ActivitySession]

    var id: Date { day }
    var totalDuration: TimeInterval { sessions.reduce(0) { $0 + $1.duration } }
}

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var activeActivity: ActiveActivity?
    @Published private(set) var sessions: [ActivitySession] = []

    private let modelContext: ModelContext
    private let now: () -> Date
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
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

    private func reloadHistory() {
        let descriptor = FetchDescriptor<ActivitySession>(
            sortBy: [SortDescriptor(\ActivitySession.startedAt, order: .reverse)]
        )
        sessions = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func saveHistory() {
        try? modelContext.save()
    }
}
