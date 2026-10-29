import Combine
import Foundation

@MainActor
final class ActivityHistoryBrowser: ObservableObject {
    @Published private(set) var recentDays: [DailyActivitySummary] = []
    @Published private(set) var months: [DateInterval] = []
    @Published private(set) var loadedMonths: [Date: [DailyActivitySummary]] = [:]
    @Published private(set) var expandedMonths: Set<Date> = []
    @Published private(set) var hasUnarchivedHistory = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasLoaded = false

    private let store: ActivityStore

    init(store: ActivityStore) {
        self.store = store
    }

    func reload(at date: Date = .now) {
        do {
            let recent = store.recentHistoryInterval(at: date)
            let recentDays = try store.historySummaries(from: recent.start, to: recent.end)
            let months = try store.historyMonths(before: recent.start)
            let expanded = expandedMonths.intersection(months.map(\.start))
            var loaded: [Date: [DailyActivitySummary]] = [:]
            for month in months where expanded.contains(month.start) {
                loaded[month.start] = try store.historySummaries(from: month.start, to: month.end)
            }
            hasUnarchivedHistory = try store.hasUnarchivedHistory()
            self.recentDays = recentDays
            self.months = months
            expandedMonths = expanded
            loadedMonths = loaded
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = "History could not be loaded. Please try again."
        }
    }

    func setExpanded(_ expanded: Bool, month: DateInterval) {
        if expanded {
            do {
                loadedMonths[month.start] = try store.historySummaries(from: month.start, to: month.end)
                expandedMonths.insert(month.start)
                errorMessage = nil
            } catch {
                errorMessage = "This month's history could not be loaded. Please try again."
            }
        } else {
            expandedMonths.remove(month.start)
            loadedMonths.removeValue(forKey: month.start)
        }
    }
}
