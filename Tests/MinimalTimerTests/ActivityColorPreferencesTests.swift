import AppKit
import SwiftUI
import Testing
@testable import MinimalTimer

@Test @MainActor
func activityChartColorsPersistAndCanBeReset() throws {
    let suiteName = "MinimalTimerTests.ActivityColorPreferences.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    defer { userDefaults.removePersistentDomain(forName: suiteName) }

    let preferences = ActivityColorPreferences(userDefaults: userDefaults)
    preferences.setColor(.red, forActivityID: "writing")

    let reloadedPreferences = ActivityColorPreferences(userDefaults: userDefaults)
    let storedColor = try #require(
        NSColor(reloadedPreferences.color(forActivityID: "writing")).usingColorSpace(.sRGB)
    )
    let expectedColor = try #require(NSColor(Color.red).usingColorSpace(.sRGB))
    #expect(abs(storedColor.redComponent - expectedColor.redComponent) < 0.001)
    #expect(abs(storedColor.greenComponent - expectedColor.greenComponent) < 0.001)
    #expect(abs(storedColor.blueComponent - expectedColor.blueComponent) < 0.001)

    reloadedPreferences.restoreDefaults()
    #expect(userDefaults.object(forKey: "activityColors.custom") == nil)
}
