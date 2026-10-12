import SwiftUI

struct GoalsSettingsView: View {
    @EnvironmentObject private var controller: TimerAppController
    @EnvironmentObject private var activityGoalPreferences: ActivityGoalPreferences
    @EnvironmentObject private var archivePreferences: ActivityArchivePreferences

    var body: some View {
        Form {
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
                Text("Goals run Monday–Sunday and include your current activity. Hours can include decimals (0.1–168). Turn a goal off to remove it.")
            }

            if !archivePreferences.archivedActivities.isEmpty {
                Section {
                    Text("Archived activities keep their existing goals. Unarchive them in Manage activities to change a goal.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Goals")
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

        let isArchived = archivePreferences.isArchived(activity.id)

        return HStack {
            Toggle(activity.name, isOn: enabled)
                .toggleStyle(.checkbox)
                .lineLimit(1)
                .help(activity.name)
                .accessibilityIdentifier("weeklyGoalToggle.\(activity.id)")
            if isArchived {
                Label("Archived", systemImage: "archivebox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        .disabled(isArchived)
    }

}
