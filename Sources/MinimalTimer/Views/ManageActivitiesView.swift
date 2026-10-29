import SwiftUI

struct ManageActivitiesView: View {
    @EnvironmentObject private var controller: TimerAppController
    @EnvironmentObject private var archivePreferences: ActivityArchivePreferences
    @EnvironmentObject private var colorPreferences: ActivityColorPreferences
    @EnvironmentObject private var goalPreferences: ActivityGoalPreferences
    @State private var activityToDelete: KnownActivity?
    @State private var deletionError: String?

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
                Text("Colors are used in summaries and statistics. Finish a running activity before archiving or deleting it.")
            }

            if !archivedActivities.isEmpty {
                Section {
                    ForEach(archivedActivities) { activity in
                        activityRow(activity, archived: true)
                    }
                } header: {
                    Text("Archived activities")
                } footer: {
                    Text("Archived activities stay visible in charts, goals, and history. Their settings and history are protected unless you delete the activity. Starting the same name automatically unarchives it.")
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
        .alert("Delete Activity?", isPresented: Binding(
            get: { activityToDelete != nil },
            set: { if !$0 { activityToDelete = nil } }
        ), presenting: activityToDelete) { activity in
            Button("Delete Activity", role: .destructive) {
                deleteActivity(activity)
            }
            Button("Cancel", role: .cancel) { activityToDelete = nil }
        } message: { activity in
            Text("Delete “\(activity.name)” and all of its history, including archived entries? Its weekly goal and custom color will also be removed. This cannot be undone.")
        }
        .alert("Could Not Delete Activity", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "Please try again.")
        }
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

            Button("Delete", role: .destructive) { activityToDelete = activity }
                .disabled(isRunning)
                .help(isRunning ? "Finish this activity before deleting it" : "Delete this activity and all its history")
                .accessibilityLabel("Delete \(activity.name)")
                .accessibilityIdentifier("deleteActivity.\(activity.id)")
        }
    }

    private func deleteActivity(_ activity: KnownActivity) {
        activityToDelete = nil
        do {
            if try !controller.deleteActivity(
                named: activity.name,
                goalPreferences: goalPreferences,
                colorPreferences: colorPreferences
            ) {
                deletionError = "Finish this activity before deleting it."
            }
        } catch {
            deletionError = "The activity could not be deleted. Please try again."
        }
    }
}
