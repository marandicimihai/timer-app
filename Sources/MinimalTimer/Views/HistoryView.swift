import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var controller: TimerAppController

    var body: some View {
        HistoryContentView(store: controller.activityStore)
    }
}

private struct HistoryContentView: View {
    @EnvironmentObject private var controller: TimerAppController
    @ObservedObject var store: ActivityStore
    @StateObject private var browser: ActivityHistoryBrowser
    @State private var showingClearConfirmation = false
    @State private var dayToDelete: Date?

    init(store: ActivityStore) {
        self.store = store
        _browser = StateObject(wrappedValue: ActivityHistoryBrowser(store: store))
    }

    var body: some View {
        List {
            if let errorMessage = browser.errorMessage {
                HStack {
                    Text(errorMessage)
                    Spacer()
                    Button("Retry") { browser.reload() }
                }
            }

            if !browser.hasLoaded {
                if browser.errorMessage == nil {
                    ProgressView("Loading history…")
                }
            } else if browser.recentDays.isEmpty && browser.months.isEmpty {
                ContentUnavailableView(
                    "No activity history",
                    systemImage: "clock",
                    description: Text("Finished activities will appear here.")
                )
            } else {
                Section("Last 30 Days") {
                    if browser.recentDays.isEmpty {
                        Text("No activity in the last 30 days.")
                            .foregroundStyle(.secondary)
                    }
                    days(browser.recentDays)
                }

                if !browser.months.isEmpty {
                    Section("Older History") {
                        ForEach(browser.months, id: \.start) { month in
                            DisclosureGroup(isExpanded: Binding(
                                get: { browser.expandedMonths.contains(month.start) },
                                set: { browser.setExpanded($0, month: month) }
                            )) {
                                // DisclosureGroup can build its content while collapsed.
                                // Only an explicit expansion fetches this month's entries.
                                if browser.expandedMonths.contains(month.start) {
                                    days(browser.loadedMonths[month.start] ?? [])
                                }
                            } label: {
                                Text(month.start, format: .dateTime.month(.wide).year())
                                    .font(.headline)
                                    .padding(.vertical, 6)
                            }
                            .accessibilityIdentifier("historyMonth.\(month.start.timeIntervalSince1970)")
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .task { browser.reload() }
        .onChange(of: store.historyRevision) { _, _ in browser.reload() }
        .onChange(of: store.archivePreferences.archivedActivities) { _, _ in browser.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            browser.reload()
        }
        .toolbar {
            if browser.hasUnarchivedHistory {
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
        .alert("Delete Day’s History?", isPresented: Binding(
            get: { dayToDelete != nil },
            set: { if !$0 { dayToDelete = nil } }
        ), presenting: dayToDelete) { day in
            Button("Delete History", role: .destructive) {
                controller.deleteActivityHistory(on: day)
                dayToDelete = nil
            }
            Button("Cancel", role: .cancel) { dayToDelete = nil }
        } message: { day in
            Text("Remove completed entries for \(day.formatted(date: .complete, time: .omitted))? Archived activity history is kept.")
        }
    }

    private func days(_ summaries: [DailyActivitySummary]) -> some View {
        ForEach(summaries) { summary in
            dayHeader(summary)
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
                    .disabled(store.isArchived(activityNamed: session.name))
                }
            }
        }
    }

    private func dayHeader(_ summary: DailyActivitySummary) -> some View {
        let hasArchivedEntries = summary.sessions.contains { store.isArchived(activityNamed: $0.name) }
        let hasDeletableEntries = summary.sessions.contains { !store.isArchived(activityNamed: $0.name) }

        return HStack {
            Text(summary.day, format: .dateTime.weekday(.wide).month().day())
            Spacer()
            Text(DurationFormatter.concise(summary.totalDuration))
                .monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button(
                hasArchivedEntries ? "Delete Unarchived Entries for Day" : "Delete Day’s History",
                role: .destructive
            ) {
                dayToDelete = summary.day
            }
            .disabled(!hasDeletableEntries)
        }
        .accessibilityIdentifier("historyDay.\(summary.day.timeIntervalSince1970)")
    }

    private var clearHistoryTitle: String {
        store.archivePreferences.archivedActivities.isEmpty ? "Clear History" : "Clear Unarchived History"
    }
}
