import Foundation
import Testing
@testable import MinimalTimer

@Test @MainActor
func pomodoroSettingsPersistAndRestoreDefaults() throws {
    let suiteName = "MinimalTimerTests.PomodoroSettings.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    defer { userDefaults.removePersistentDomain(forName: suiteName) }
    userDefaults.removePersistentDomain(forName: suiteName)

    let settings = PomodoroSettings(userDefaults: userDefaults)
    #expect(settings.focusDurationMinutes == 25)
    #expect(settings.breakDurationMinutes == 5)
    #expect(settings.notificationsEnabled)
    #expect(settings.showTimerValueInMenuBar)

    settings.setFocusDurationMinutes(45)
    settings.setBreakDurationMinutes(15)
    settings.setNotificationsEnabled(false)
    settings.setShowTimerValueInMenuBar(false)

    let reloadedSettings = PomodoroSettings(userDefaults: userDefaults)
    #expect(reloadedSettings.focusDurationMinutes == 45)
    #expect(reloadedSettings.breakDurationMinutes == 15)
    #expect(!reloadedSettings.notificationsEnabled)
    #expect(!reloadedSettings.showTimerValueInMenuBar)

    reloadedSettings.restoreDefaults()
    let restoredSettings = PomodoroSettings(userDefaults: userDefaults)
    #expect(restoredSettings.focusDurationMinutes == 25)
    #expect(restoredSettings.breakDurationMinutes == 5)
    #expect(restoredSettings.notificationsEnabled)
    #expect(restoredSettings.showTimerValueInMenuBar)
}

@Test @MainActor
func pomodoroSettingsClampValuesToSupportedRanges() {
    let settings = PomodoroSettings(userDefaults: nil)

    settings.setFocusDurationMinutes(0)
    settings.setBreakDurationMinutes(1_000)

    #expect(settings.focusDurationMinutes == PomodoroSettings.focusDurationRange.lowerBound)
    #expect(settings.breakDurationMinutes == PomodoroSettings.breakDurationRange.upperBound)
}
