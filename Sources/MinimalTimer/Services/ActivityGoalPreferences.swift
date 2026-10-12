import Combine
import Foundation

struct WeeklyActivityGoal: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let hours: Double
}

enum ActivityGoalProgressLevel {
    case red, yellow, green
}

struct ActivityGoalProgress: Identifiable, Equatable {
    let goal: WeeklyActivityGoal
    let duration: TimeInterval

    var id: String { goal.id }
    var completedHours: Double { duration / 3_600 }
    var fraction: Double { completedHours / goal.hours }
    var percentage: Int { Int((fraction * 100).rounded(.down)) }
    var level: ActivityGoalProgressLevel {
        if fraction < 0.2 { return .red }
        if fraction < 0.7 { return .yellow }
        return .green
    }
}

@MainActor
final class ActivityGoalPreferences: ObservableObject {
    @Published private(set) var goals: [WeeklyActivityGoal]

    static let hoursRange = 0.1...168.0
    private static let storageKey = "activityGoals.weekly"
    private let userDefaults: UserDefaults?
    private let archivePreferences: ActivityArchivePreferences?

    init(userDefaults: UserDefaults? = .standard, archivePreferences: ActivityArchivePreferences? = nil) {
        self.userDefaults = userDefaults
        self.archivePreferences = archivePreferences
        if let data = userDefaults?.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode([WeeklyActivityGoal].self, from: data) {
            var seen: Set<String> = []
            goals = stored.filter {
                !$0.id.isEmpty && $0.id == ActivityColorPalette.normalizedIdentifier(for: $0.name)
                    && Self.hoursRange.contains($0.hours) && seen.insert($0.id).inserted
            }
        } else {
            goals = []
        }
    }

    func goal(forActivityID id: String) -> WeeklyActivityGoal? {
        goals.first { $0.id == id }
    }

    func setGoal(hours: Double, forActivityNamed rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = ActivityColorPalette.normalizedIdentifier(for: name)
        guard !id.isEmpty, archivePreferences?.isArchived(id) != true,
              hours.isFinite, Self.hoursRange.contains(hours) else { return }
        let goal = WeeklyActivityGoal(id: id, name: name, hours: hours)
        if let index = goals.firstIndex(where: { $0.id == id }) {
            goals[index] = goal
        } else {
            goals.append(goal)
        }
        goals.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save()
    }

    func removeGoal(forActivityID id: String) {
        guard archivePreferences?.isArchived(id) != true else { return }
        goals.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(goals) else { return }
        userDefaults?.set(data, forKey: Self.storageKey)
    }
}
