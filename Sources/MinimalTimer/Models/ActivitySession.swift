import Foundation
import SwiftData

@Model
final class ActivitySession {
    @Attribute(.unique) var id: UUID
    var name: String
    var startedAt: Date
    var endedAt: Date

    init(id: UUID = UUID(), name: String, startedAt: Date, endedAt: Date) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }
}

struct ActiveActivity: Identifiable, Equatable {
    let id: UUID
    let name: String
    let startedAt: Date

    init(id: UUID = UUID(), name: String, startedAt: Date) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
    }
}
