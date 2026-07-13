import Foundation
import SwiftData
import Testing
@testable import MinimalTimer

@Test @MainActor
func activityHistoryPersistsInAnExplicitSQLiteFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appendingPathComponent("activity-history.sqlite")
    let persistence = ActivityPersistence(storeURL: storeURL, legacyStoreURL: nil)

    do {
        let container = try persistence.makeContainer()
        let store = ActivityStore(modelContext: container.mainContext, now: {
            Date(timeIntervalSince1970: 1_000)
        })
        store.startActivity(named: "Local work", at: Date(timeIntervalSince1970: 900))
        _ = store.finishActivity(at: Date(timeIntervalSince1970: 1_000))
    }

    #expect(FileManager.default.fileExists(atPath: storeURL.path))

    let reopenedContainer = try persistence.makeContainer()
    let reopenedStore = ActivityStore(modelContext: reopenedContainer.mainContext)
    #expect(reopenedStore.sessions.count == 1)
    #expect(reopenedStore.sessions.first?.name == "Local work")
    #expect(reopenedStore.sessions.first?.duration == 100)
}

@Test @MainActor
func existingDefaultStoreIsImportedIntoTheNamedSQLiteFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let legacyURL = directory.appendingPathComponent("default.store")
    let storeURL = directory
        .appendingPathComponent("MinimalTimer", isDirectory: true)
        .appendingPathComponent("activity-history.sqlite")
    let markerURL = directory.appendingPathComponent("legacy-imported")

    do {
        let legacyPersistence = ActivityPersistence(
            storeURL: legacyURL,
            legacyStoreURL: nil,
            migrationMarkerURL: directory.appendingPathComponent("unused-marker")
        )
        let legacyContainer = try legacyPersistence.makeContainer()
        legacyContainer.mainContext.insert(ActivitySession(
            name: "Existing log",
            startedAt: Date(timeIntervalSince1970: 500),
            endedAt: Date(timeIntervalSince1970: 800)
        ))
        try legacyContainer.mainContext.save()
    }

    let persistence = ActivityPersistence(
        storeURL: storeURL,
        legacyStoreURL: legacyURL,
        migrationMarkerURL: markerURL
    )
    let container = try persistence.makeContainer()
    let sessions = try container.mainContext.fetch(FetchDescriptor<ActivitySession>())

    #expect(sessions.count == 1)
    #expect(sessions.first?.name == "Existing log")
    #expect(FileManager.default.fileExists(atPath: markerURL.path))
    #expect(FileManager.default.fileExists(atPath: legacyURL.path))
}
