import AppKit
import Combine
import SwiftUI
@preconcurrency import UserNotifications

struct HistorySettingsWindowView: View {
    @EnvironmentObject private var controller: TimerAppController

    var body: some View {
        TabView(selection: $controller.selectedDetailWindowTab) {
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(DetailWindowTab.history)

            StatisticsView()
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar.xaxis")
                }
                .tag(DetailWindowTab.statistics)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(DetailWindowTab.settings)
        }
        .frame(minWidth: 440, minHeight: 520)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var controller: TimerAppController
    @EnvironmentObject private var menuBarPreferences: MenuBarPreferences
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus?
    @State private var notificationAlertStyle: UNAlertStyle?

    var body: some View {
        Form {
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
                Text("Pomodoro")
            } footer: {
                Text("Duration changes apply to the next timer.")
            }

            Section("Behavior") {
                Toggle(
                    "Notify when a timer finishes",
                    isOn: notificationsEnabledBinding
                )
                .accessibilityIdentifier("pomodoroNotificationsToggle")

                Toggle(
                    "Show activity time in the menu bar",
                    isOn: showTimerValueBinding
                )
                .accessibilityIdentifier("showTimerValueToggle")

                Toggle(
                    "Show Pomodoro icon in the menu bar",
                    isOn: showPomodoroIconBinding
                )
                .accessibilityIdentifier("showPomodoroMenuBarIconToggle")

                if
                    controller.pomodoro.settings.notificationsEnabled,
                    notificationAuthorizationStatus == .denied
                        || notificationAlertStyle == UNAlertStyle.none
                {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            notificationWarningMessage,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)

                        Button("Open Notification Settings…") {
                            openNotificationSettings()
                        }
                        .accessibilityIdentifier("openNotificationSettingsButton")
                    }
                }
            }

            Section {
                Button("Restore Defaults") {
                    controller.restorePomodoroSettings()
                    menuBarPreferences.restoreDefaults()
                }
                .accessibilityIdentifier("restorePomodoroDefaultsButton")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear { refreshNotificationAuthorizationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshNotificationAuthorizationStatus()
        }
    }

    private func durationRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        accessibilityIdentifier: String
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("Minutes", value: value, format: .number)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
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

    private var showTimerValueBinding: Binding<Bool> {
        Binding(
            get: { controller.pomodoro.settings.showTimerValueInMenuBar },
            set: { controller.setShowTimerValueInMenuBar($0) }
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
