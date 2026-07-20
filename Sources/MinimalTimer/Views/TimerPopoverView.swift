import AppKit
import SwiftUI

struct TimerPopoverView: View {
    @EnvironmentObject private var controller: TimerAppController
    @EnvironmentObject private var detailWindowCoordinator: DetailWindowCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var activityName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Minimal Timer")
                .font(.headline)

            activityCard
            Divider()
            PomodoroMainControls(controller: controller)
            Divider()
            HStack {
                Button("History") {
                    controller.showHistoryTab()
                    openDetailWindow()
                }
                .accessibilityIdentifier("historyButton")

                Button("Settings") {
                    controller.showSettingsTab()
                    openDetailWindow()
                }
                .accessibilityIdentifier("settingsButton")

                Spacer()

                Button("Quit Timer") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 330)
        .onAppear {
            NotificationCenter.default.post(name: .minimalTimerActivityPopoverDidOpen, object: nil)
            controller.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .minimalTimerPomodoroPopoverWillOpen)
        ) { _ in
            dismiss()
        }
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start a new activity")
                .font(.subheadline)

            HStack(spacing: 8) {
                TextField("What are you doing?", text: $activityName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(startActivity)
                    .accessibilityIdentifier("activityNameField")

                Button("Start") {
                    startActivity()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("startActivityButton")
            }

            if !controller.activityStore.recentActivityNames().isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Or continue a recent one:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(
                                Array(controller.activityStore.recentActivityNames().enumerated()),
                                id: \.element
                            ) { index, name in
                                Button(name) {
                                    startRecentActivity(named: name)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .lineLimit(1)
                                .accessibilityIdentifier("recentActivityButton\(index)")
                                .help("Start \(name)")
                                .contextMenu {
                                    Button("Delete Activity and History", role: .destructive) {
                                        controller.deleteActivityHistory(named: name)
                                    }
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }

            if let activity = controller.activityStore.activeActivity {
                HStack(alignment: .firstTextBaseline) {
                    Text(activity.name)
                        .lineLimit(1)
                    Spacer()
                    Text(DurationFormatter.clock(controller.currentDate.timeIntervalSince(activity.startedAt)))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Button("Finish Activity") {
                    controller.finishActivity()
                }
                .accessibilityIdentifier("finishActivityButton")
            }

            ActivityMiniChart(
                overview: controller.activityStore.activityOverview(at: controller.currentDate)
            )
        }
    }

    private func startActivity() {
        controller.startActivity(named: activityName)
        activityName = ""
    }

    private func startRecentActivity(named name: String) {
        controller.startActivity(named: name)
        activityName = ""
    }

    private func openDetailWindow() {
        dismiss()
        DispatchQueue.main.async {
            openWindow(id: "history")
            detailWindowCoordinator.requestFocus()
        }
    }
}

private struct PomodoroMainControls: View {
    @ObservedObject private var controller: TimerAppController
    @ObservedObject private var pomodoro: PomodoroTimer

    init(controller: TimerAppController) {
        self.controller = controller
        self.pomodoro = controller.pomodoro
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pomodoro", systemImage: "circle.circle")
                .font(.headline)

            if let activePhase = pomodoro.activePhase {
                HStack {
                    Text("\(activePhase.title) in progress")
                    Spacer()
                    Button("Stop Pomodoro", role: .destructive) {
                        controller.stopPomodoro()
                    }
                    .accessibilityIdentifier("stopPomodoroButton")
                }

                ProgressView(value: pomodoro.progress(at: controller.currentDate))
            } else {
                if pomodoro.isAwaitingNextPhase, let completedPhase = pomodoro.completedPhase {
                    Text("\(completedPhase.title) complete")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Start \(pomodoro.suggestedPhase.title)") {
                        controller.startSuggestedPomodoro()
                    }
                    .accessibilityIdentifier("startPomodoroButton")

                    if pomodoro.isAwaitingNextPhase {
                        Spacer()
                        Button("Stop Pomodoro", role: .destructive) {
                            controller.stopPomodoro()
                        }
                        .accessibilityIdentifier("stopAwaitingPomodoroButton")
                    }
                }
            }
        }
    }
}
