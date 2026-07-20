import Combine
import Foundation

@MainActor
final class MenuBarPreferences: ObservableObject {
    static let showPomodoroIconKey = "menuBar.showPomodoroProgressIcon"
    static let defaultShowPomodoroIcon = true

    @Published private(set) var showsPomodoroIcon: Bool

    private let userDefaults: UserDefaults?

    init(userDefaults: UserDefaults? = .standard) {
        self.userDefaults = userDefaults
        if let userDefaults, userDefaults.object(forKey: Self.showPomodoroIconKey) != nil {
            showsPomodoroIcon = userDefaults.bool(forKey: Self.showPomodoroIconKey)
        } else {
            showsPomodoroIcon = Self.defaultShowPomodoroIcon
        }
    }

    func setShowsPomodoroIcon(_ isVisible: Bool) {
        guard isVisible != showsPomodoroIcon else { return }
        showsPomodoroIcon = isVisible
        userDefaults?.set(isVisible, forKey: Self.showPomodoroIconKey)
    }

    func restoreDefaults() {
        setShowsPomodoroIcon(Self.defaultShowPomodoroIcon)
    }
}

@MainActor
final class PomodoroSettings: ObservableObject {
    static let defaultFocusDurationMinutes = 25
    static let defaultBreakDurationMinutes = 5
    static let defaultNotificationsEnabled = true
    static let defaultShowTimerValueInMenuBar = true

    static let focusDurationRange = 1...180
    static let breakDurationRange = 1...60

    @Published private(set) var focusDurationMinutes: Int
    @Published private(set) var breakDurationMinutes: Int
    @Published private(set) var notificationsEnabled: Bool
    @Published private(set) var showTimerValueInMenuBar: Bool

    private let userDefaults: UserDefaults?

    private enum Key {
        static let focusDurationMinutes = "pomodoro.focusDurationMinutes"
        static let breakDurationMinutes = "pomodoro.breakDurationMinutes"
        static let notificationsEnabled = "pomodoro.notificationsEnabled"
        static let showTimerValueInMenuBar = "menuBar.showTimerValue"
    }

    init(userDefaults: UserDefaults? = .standard) {
        self.userDefaults = userDefaults
        focusDurationMinutes = Self.storedInteger(
            forKey: Key.focusDurationMinutes,
            in: userDefaults,
            defaultValue: Self.defaultFocusDurationMinutes,
            allowedRange: Self.focusDurationRange
        )
        breakDurationMinutes = Self.storedInteger(
            forKey: Key.breakDurationMinutes,
            in: userDefaults,
            defaultValue: Self.defaultBreakDurationMinutes,
            allowedRange: Self.breakDurationRange
        )
        notificationsEnabled = Self.storedBoolean(
            forKey: Key.notificationsEnabled,
            in: userDefaults,
            defaultValue: Self.defaultNotificationsEnabled
        )
        showTimerValueInMenuBar = Self.storedBoolean(
            forKey: Key.showTimerValueInMenuBar,
            in: userDefaults,
            defaultValue: Self.defaultShowTimerValueInMenuBar
        )
    }

    func duration(for phase: PomodoroPhase) -> TimeInterval {
        let minutes = phase == .focus ? focusDurationMinutes : breakDurationMinutes
        return TimeInterval(minutes * 60)
    }

    func setFocusDurationMinutes(_ minutes: Int) {
        let value = min(max(minutes, Self.focusDurationRange.lowerBound), Self.focusDurationRange.upperBound)
        guard value != focusDurationMinutes else { return }
        focusDurationMinutes = value
        userDefaults?.set(value, forKey: Key.focusDurationMinutes)
    }

    func setBreakDurationMinutes(_ minutes: Int) {
        let value = min(max(minutes, Self.breakDurationRange.lowerBound), Self.breakDurationRange.upperBound)
        guard value != breakDurationMinutes else { return }
        breakDurationMinutes = value
        userDefaults?.set(value, forKey: Key.breakDurationMinutes)
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        guard enabled != notificationsEnabled else { return }
        notificationsEnabled = enabled
        userDefaults?.set(enabled, forKey: Key.notificationsEnabled)
    }

    func setShowTimerValueInMenuBar(_ enabled: Bool) {
        guard enabled != showTimerValueInMenuBar else { return }
        showTimerValueInMenuBar = enabled
        userDefaults?.set(enabled, forKey: Key.showTimerValueInMenuBar)
    }

    func restoreDefaults() {
        setFocusDurationMinutes(Self.defaultFocusDurationMinutes)
        setBreakDurationMinutes(Self.defaultBreakDurationMinutes)
        setNotificationsEnabled(Self.defaultNotificationsEnabled)
        setShowTimerValueInMenuBar(Self.defaultShowTimerValueInMenuBar)
    }

    private static func storedInteger(
        forKey key: String,
        in userDefaults: UserDefaults?,
        defaultValue: Int,
        allowedRange: ClosedRange<Int>
    ) -> Int {
        guard let userDefaults, userDefaults.object(forKey: key) != nil else { return defaultValue }
        return min(max(userDefaults.integer(forKey: key), allowedRange.lowerBound), allowedRange.upperBound)
    }

    private static func storedBoolean(
        forKey key: String,
        in userDefaults: UserDefaults?,
        defaultValue: Bool
    ) -> Bool {
        guard let userDefaults, userDefaults.object(forKey: key) != nil else { return defaultValue }
        return userDefaults.bool(forKey: key)
    }
}
