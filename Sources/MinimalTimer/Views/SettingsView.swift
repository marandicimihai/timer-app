import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var controller: TimerAppController

    var body: some View {
        Form {
            Section("Menu bar") {
                Toggle("Show activity time in the menu bar", isOn: showTimerValueBinding)
                    .accessibilityIdentifier("showTimerValueToggle")
            }

            Section {
                Button("Restore Settings Defaults") {
                    controller.setShowTimerValueInMenuBar(PomodoroSettings.defaultShowTimerValueInMenuBar)
                }
                .accessibilityIdentifier("restoreSettingsDefaultsButton")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private var showTimerValueBinding: Binding<Bool> {
        Binding(
            get: { controller.pomodoro.settings.showTimerValueInMenuBar },
            set: { controller.setShowTimerValueInMenuBar($0) }
        )
    }
}
