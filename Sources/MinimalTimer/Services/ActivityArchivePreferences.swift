import Combine
import Foundation

@MainActor
final class ActivityArchivePreferences: ObservableObject {
    @Published private(set) var archivedActivities: [KnownActivity]

    private let userDefaults: UserDefaults?
    private static let storageKey = "activities.archived"

    init(userDefaults: UserDefaults? = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults?.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode([KnownActivity].self, from: data) {
            var seen: Set<String> = []
            archivedActivities = stored.filter {
                !$0.id.isEmpty && $0.id == ActivityColorPalette.normalizedIdentifier(for: $0.name)
                    && seen.insert($0.id).inserted
            }
        } else {
            archivedActivities = []
        }
    }

    func isArchived(_ activityID: String) -> Bool {
        archivedActivities.contains { $0.id == activityID }
    }

    func archiveActivity(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = ActivityColorPalette.normalizedIdentifier(for: name)
        guard !id.isEmpty, !isArchived(id) else { return }
        archivedActivities.append(KnownActivity(id: id, name: name))
        save()
    }

    func unarchiveActivity(id: String) {
        guard isArchived(id) else { return }
        archivedActivities.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(archivedActivities) else { return }
        userDefaults?.set(data, forKey: Self.storageKey)
    }
}
