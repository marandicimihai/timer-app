import Foundation
import SwiftData

@MainActor
struct ActivityPersistence {
    let storeURL: URL
    let legacyStoreURL: URL?
    let migrationMarkerURL: URL

    init(
        storeURL: URL = Self.defaultStoreURL,
        legacyStoreURL: URL? = Self.defaultLegacyStoreURL,
        migrationMarkerURL: URL? = nil
    ) {
        self.storeURL = storeURL
        self.legacyStoreURL = legacyStoreURL
        self.migrationMarkerURL = migrationMarkerURL
            ?? storeURL.deletingLastPathComponent().appendingPathComponent(".legacy-store-imported")
    }

    func makeContainer() throws -> ModelContainer {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let schema = Schema([ActivitySession.self])
        let configuration = ModelConfiguration(
            "ActivityHistory",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: configuration)

        do {
            try importLegacyStoreIfNeeded(into: container, schema: schema, fileManager: fileManager)
        } catch {
            NSLog("MinimalTimer could not import its legacy activity store: %@", error.localizedDescription)
        }

        return container
    }

    private func importLegacyStoreIfNeeded(
        into destinationContainer: ModelContainer,
        schema: Schema,
        fileManager: FileManager
    ) throws {
        guard
            !fileManager.fileExists(atPath: migrationMarkerURL.path),
            let legacyStoreURL,
            legacyStoreURL.standardizedFileURL != storeURL.standardizedFileURL,
            fileManager.fileExists(atPath: legacyStoreURL.path)
        else { return }

        let legacyConfiguration = ModelConfiguration(
            "LegacyActivityHistory",
            schema: schema,
            url: legacyStoreURL,
            cloudKitDatabase: .none
        )
        let legacyContainer = try ModelContainer(for: schema, configurations: legacyConfiguration)
        let legacySessions = try legacyContainer.mainContext.fetch(FetchDescriptor<ActivitySession>())
        let existingSessions = try destinationContainer.mainContext.fetch(FetchDescriptor<ActivitySession>())
        var existingIDs = Set(existingSessions.map(\.id))

        for session in legacySessions where existingIDs.insert(session.id).inserted {
            destinationContainer.mainContext.insert(ActivitySession(
                id: session.id,
                name: session.name,
                startedAt: session.startedAt,
                endedAt: session.endedAt
            ))
        }
        try destinationContainer.mainContext.save()
        try Data().write(to: migrationMarkerURL, options: .atomic)
    }

    private static var applicationSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    }

    static var defaultStoreURL: URL {
        applicationSupportURL
            .appendingPathComponent("MinimalTimer", isDirectory: true)
            .appendingPathComponent("activity-history.sqlite")
    }

    static var defaultLegacyStoreURL: URL {
        applicationSupportURL.appendingPathComponent("default.store")
    }
}
