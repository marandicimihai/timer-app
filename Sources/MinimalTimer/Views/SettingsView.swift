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
    @EnvironmentObject private var activityColorPreferences: ActivityColorPreferences
    @EnvironmentObject private var activityGoalPreferences: ActivityGoalPreferences
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
                if goalActivities.isEmpty {
                    Text("Start an activity to set its weekly hour goal.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(goalActivities) { activity in
                        weeklyGoalRow(for: activity)
                    }
                }
            } header: {
                Text("Weekly goals")
            } footer: {
                Text("Goals run Monday–Sunday and include your current activity. Turn a goal off to remove it. Hours can include decimals (0.1–168).")
            }

            Section("Appearance") {
                if controller.activityStore.knownActivities.isEmpty {
                    Text("Start or finish an activity to customize its color.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(controller.activityStore.knownActivities) { activity in
                        LabeledContent(activity.name) {
                            ColorPicker(
                                "Color for \(activity.name)",
                                selection: activityColorPreferences.colorBinding(
                                    forActivityID: activity.id
                                ),
                                supportsOpacity: false
                            )
                            .labelsHidden()
                            .accessibilityLabel("Color for \(activity.name)")
                            .accessibilityIdentifier("activityColorPicker.\(activity.id)")
                        }
                    }
                }

                Text("Used for this activity in summaries and statistics charts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Reset Activity Colors") {
                    activityColorPreferences.restoreDefaults()
                }
                .accessibilityIdentifier("resetActivityColorsButton")
            }

            Section {
                Button("Restore Defaults") {
                    controller.restorePomodoroSettings()
                    menuBarPreferences.restoreDefaults()
                    activityColorPreferences.restoreDefaults()
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

    private var goalActivities: [KnownActivity] {
        var activities = Dictionary(uniqueKeysWithValues: activityGoalPreferences.goals.map {
            ($0.id, KnownActivity(id: $0.id, name: $0.name))
        })
        for activity in controller.activityStore.knownActivities {
            activities[activity.id] = activity
        }
        return activities.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func weeklyGoalRow(for activity: KnownActivity) -> some View {
        let enabled = Binding(
            get: { activityGoalPreferences.goal(forActivityID: activity.id) != nil },
            set: { isEnabled in
                if isEnabled {
                    activityGoalPreferences.setGoal(hours: 5, forActivityNamed: activity.name)
                } else {
                    activityGoalPreferences.removeGoal(forActivityID: activity.id)
                }
            }
        )
        let hours = Binding(
            get: { activityGoalPreferences.goal(forActivityID: activity.id)?.hours ?? 5 },
            set: { activityGoalPreferences.setGoal(hours: $0, forActivityNamed: activity.name) }
        )

        return HStack {
            Toggle(activity.name, isOn: enabled)
                .toggleStyle(.checkbox)
                .lineLimit(1)
                .help(activity.name)
                .accessibilityIdentifier("weeklyGoalToggle.\(activity.id)")
            Spacer()
            HStack(spacing: 5) {
                TextField("", value: hours, format: .number.precision(.fractionLength(0...2)))
                    .labelsHidden()
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .accessibilityLabel("Weekly hours for \(activity.name)")
                    .accessibilityIdentifier("weeklyGoalHours.\(activity.id)")
                Text("hours/week")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Stepper("", value: hours, in: ActivityGoalPreferences.hoursRange, step: 0.5)
                    .labelsHidden()
                    .accessibilityLabel("Adjust weekly hours for \(activity.name)")
                    .accessibilityIdentifier("weeklyGoalStepper.\(activity.id)")
            }
            .fixedSize(horizontal: true, vertical: false)
            .disabled(!enabled.wrappedValue)
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
