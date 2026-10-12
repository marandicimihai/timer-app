import SwiftUI

struct ManageActivitiesView: View {
    @EnvironmentObject private var controller: TimerAppController
    @EnvironmentObject private var archivePreferences: ActivityArchivePreferences
    @EnvironmentObject private var colorPreferences: ActivityColorPreferences
    @EnvironmentObject private var goalPreferences: ActivityGoalPreferences

    var body: some View {
        Form {
            Section {
                if unarchivedActivities.isEmpty {
                    Text("Start an activity to manage it here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(unarchivedActivities) { activity in
                        activityRow(activity, archived: false)
                    }
                }
            } header: {
                Text("Activities and colors")
            } footer: {
                Text("Colors are used in summaries and statistics. Finish a running activity before archiving it.")
            }

            if !archivedActivities.isEmpty {
                Section {
                    ForEach(archivedActivities) { activity in
                        activityRow(activity, archived: true)
                    }
                } header: {
                    Text("Archived activities")
                } footer: {
                    Text("Archived activities stay visible in charts, goals, and history. Their settings and history are protected. Starting the same name automatically unarchives it.")
                }
            }

            Section {
                Button("Reset Activity Colors") {
                    colorPreferences.restoreDefaults()
                }
                .disabled(!unarchivedActivities.contains { colorPreferences.customColors[$0.id] != nil })
                .accessibilityIdentifier("resetActivityColorsButton")
                Text("Resets colors for unarchived activities only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Manage activities")
    }

    private var activities: [KnownActivity] {
        let known = controller.activityStore.knownActivities
        let knownIDs = Set(known.map(\.id))
        return known + goalPreferences.goals.filter { !knownIDs.contains($0.id) }.map {
            KnownActivity(id: $0.id, name: $0.name)
        }
    }

    private var unarchivedActivities: [KnownActivity] {
        activities.filter { !archivePreferences.isArchived($0.id) }
    }

    private var archivedActivities: [KnownActivity] {
        activities.filter { archivePreferences.isArchived($0.id) }
    }

    private func activityRow(_ activity: KnownActivity, archived: Bool) -> some View {
        let isRunning = controller.activityStore.activeActivity.map {
            ActivityColorPalette.normalizedIdentifier(for: $0.name)
        } == activity.id

        return HStack(spacing: 12) {
            Text(activity.name)
                .lineLimit(1)
                .help(activity.name)
            if isRunning {
                Text("Running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ColorPicker(
                "Color for \(activity.name)",
                selection: colorPreferences.colorBinding(forActivityID: activity.id),
                supportsOpacity: false
            )
            .labelsHidden()
            .disabled(archived)
            .accessibilityLabel("Color for \(activity.name)")
            .accessibilityIdentifier("activityColorPicker.\(activity.id)")

            if archived {
                Button("Unarchive") { controller.unarchiveActivity(id: activity.id) }
                    .accessibilityIdentifier("unarchiveActivity.\(activity.id)")
            } else {
                Button("Archive") { controller.archiveActivity(named: activity.name) }
                    .disabled(isRunning)
                    .help(isRunning ? "Finish this activity before archiving it" : "Keep history and lock activity settings")
                    .accessibilityIdentifier("archiveActivity.\(activity.id)")
            }
        }
    }
}
