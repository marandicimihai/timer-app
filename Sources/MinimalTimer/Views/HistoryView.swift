import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var controller: TimerAppController
    @State private var showingClearConfirmation = false

    var body: some View {
        List {
            if controller.activityStore.dailySummaries.isEmpty {
                ContentUnavailableView(
                    "No activity history",
                    systemImage: "clock",
                    description: Text("Finished activities will appear here.")
                )
            } else {
                ForEach(controller.activityStore.dailySummaries) { summary in
                    Section {
                        ForEach(summary.sessions, id: \.id) { session in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(session.name)
                                    Text(session.startedAt, format: .dateTime.hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(DurationFormatter.concise(session.duration))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Delete Entry", role: .destructive) {
                                    controller.deleteActivitySession(id: session.id)
                                }
                                .disabled(controller.activityStore.isArchived(activityNamed: session.name))
                            }
                        }
                    } header: {
                        HStack {
                            Text(summary.day, format: .dateTime.weekday(.wide).month().day())
                            Spacer()
                            Text(DurationFormatter.concise(summary.totalDuration))
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            if hasUnarchivedHistory {
                Button(clearHistoryTitle, role: .destructive) {
                    showingClearConfirmation = true
                }
                .accessibilityIdentifier("clearHistoryButton")
            }
        }
        .alert("\(clearHistoryTitle)?", isPresented: $showingClearConfirmation) {
            Button(clearHistoryTitle, role: .destructive) {
                controller.clearActivityHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes completed entries for unarchived activities. Archived activity history is kept.")
        }
    }

    private var hasUnarchivedHistory: Bool {
        controller.activityStore.sessions.contains {
            !controller.activityStore.isArchived(activityNamed: $0.name)
        }
    }

    private var clearHistoryTitle: String {
        controller.activityStore.archivePreferences.archivedActivities.isEmpty
            ? "Clear History" : "Clear Unarchived History"
    }
}
