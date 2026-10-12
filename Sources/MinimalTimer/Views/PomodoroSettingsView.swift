import AppKit
import SwiftUI
@preconcurrency import UserNotifications

struct PomodoroSettingsView: View {
    @EnvironmentObject private var controller: TimerAppController
    @EnvironmentObject private var menuBarPreferences: MenuBarPreferences
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus?
    @State private var notificationAlertStyle: UNAlertStyle?

    var body: some View {
        Form {
            Section {
                Toggle("Enable Pomodoro", isOn: enabledBinding)
                    .accessibilityIdentifier("enablePomodoroToggle")
            } footer: {
                Text("Turning Pomodoro off stops its timer and hides its controls and icon from the menu bar.")
            }

            Section {
                durationRow(
                    title: "Focus duration",
                    value: focusDurationBinding,
                    range: PomodoroSettings.focusDurationRange,
                    accessibilityIdentifier: "focusDurationStepper"
                )
                durationRow(
                    title: "Break duration",
                    value: breakDurationBinding,
                    range: PomodoroSettings.breakDurationRange,
                    accessibilityIdentifier: "breakDurationStepper"
                )
            } header: {
                Text("Durations")
            } footer: {
                Text("Duration changes apply to the next timer.")
            }
            .disabled(!controller.pomodoro.settings.isEnabled)

            Section("Behavior") {
                Toggle("Notify when a timer finishes", isOn: notificationsEnabledBinding)
                    .accessibilityIdentifier("pomodoroNotificationsToggle")
                Toggle("Show Pomodoro icon in the menu bar", isOn: showPomodoroIconBinding)
                    .accessibilityIdentifier("showPomodoroMenuBarIconToggle")

                if controller.pomodoro.settings.isEnabled,
                   controller.pomodoro.settings.notificationsEnabled,
                   notificationAuthorizationStatus == .denied || notificationAlertStyle == UNAlertStyle.none {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(notificationWarningMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Open Notification Settings…") { openNotificationSettings() }
                            .accessibilityIdentifier("openNotificationSettingsButton")
                    }
                }
            }
            .disabled(!controller.pomodoro.settings.isEnabled)

            Section {
                Button("Restore Pomodoro Defaults") {
                    controller.restorePomodoroSettings()
                    menuBarPreferences.restoreDefaults()
                }
                .accessibilityIdentifier("restorePomodoroDefaultsButton")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Pomodoro")
        .onAppear { refreshNotificationAuthorizationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshNotificationAuthorizationStatus()
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { controller.pomodoro.settings.isEnabled },
            set: { controller.setPomodoroEnabled($0) }
        )
    }

    private func durationRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        accessibilityIdentifier: String
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 5) {
                Text("Minutes")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                TextField("", value: value, format: .number)
                    .labelsHidden()
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    .accessibilityLabel(title)
                    .accessibilityValue("\(value.wrappedValue) minutes")
                    .accessibilityIdentifier("\(accessibilityIdentifier)Field")

                Text("min")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Stepper("", value: value, in: range)
                    .labelsHidden()
                    .accessibilityLabel("Adjust \(title.lowercased())")
                    .accessibilityValue("\(value.wrappedValue) minutes")
                    .accessibilityIdentifier(accessibilityIdentifier)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var focusDurationBinding: Binding<Int> {
        Binding(
            get: { controller.pomodoro.settings.focusDurationMinutes },
            set: { controller.setFocusDurationMinutes($0) }
        )
    }

    private var breakDurationBinding: Binding<Int> {
        Binding(
            get: { controller.pomodoro.settings.breakDurationMinutes },
            set: { controller.setBreakDurationMinutes($0) }
        )
    }

    private var notificationsEnabledBinding: Binding<Bool> {
        Binding(
            get: { controller.pomodoro.settings.notificationsEnabled },
            set: { controller.setPomodoroNotificationsEnabled($0) }
        )
    }

    private var showPomodoroIconBinding: Binding<Bool> {
        Binding(
            get: { menuBarPreferences.showsPomodoroIcon },
            set: { menuBarPreferences.setShowsPomodoroIcon($0) }
        )
    }

    private func refreshNotificationAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationAuthorizationStatus = settings.authorizationStatus
                notificationAlertStyle = settings.alertStyle
            }
        }
    }

    private var notificationWarningMessage: String {
        if notificationAuthorizationStatus == .denied {
            return "Notifications are blocked by macOS. Minimal Timer will show its own corner alert."
        }
        return "macOS notification banners are turned off. Minimal Timer will show its own corner alert."
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
