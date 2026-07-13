import Combine
import SwiftUI

struct TimerPopoverView: View {
    @EnvironmentObject private var controller: TimerAppController
    @Environment(\.openWindow) private var openWindow
    @State private var activityName = ""

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            activityCard
            Divider()
            pomodoroCard
            Divider()
            HStack {
                Button("History") {
                    openWindow(id: "history")
                }
                .accessibilityIdentifier("historyButton")

                Spacer()

                Button("Quit Timer") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 330)
        .onAppear { controller.refresh() }
        .onReceive(ticker) { _ in controller.refresh() }
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Activity", systemImage: "checkmark.circle")
                .font(.headline)

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

            TextField(
                controller.activityStore.activeActivity == nil ? "What are you doing?" : "Start another activity",
                text: $activityName
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit(startActivity)
            .accessibilityIdentifier("activityNameField")

            Button(controller.activityStore.activeActivity == nil ? "Start Activity" : "Switch Activity") {
                startActivity()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("startActivityButton")

            if !controller.activityStore.recentActivityNames().isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Recent")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(Array(controller.activityStore.recentActivityNames().enumerated()), id: \.offset) { index, name in
                                Button(name) {
                                    startRecentActivity(named: name)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .lineLimit(1)
                                .accessibilityIdentifier("recentActivityButton\(index)")
                                .help("Start \(name)")
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }

            ActivityMiniChart(
                overview: controller.activityStore.activityOverview(at: controller.currentDate)
            )
        }
    }

    private var pomodoroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pomodoro", systemImage: "leaf")
                .font(.headline)

            if let phase = controller.pomodoro.activePhase {
                HStack {
                    Text(phase.title)
                    Spacer()
                    Text(DurationFormatter.clock(controller.pomodoro.remainingDuration))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: controller.pomodoro.progress)
                Button("Stop Pomodoro") {
                    controller.stopPomodoro()
                }
                .accessibilityIdentifier("stopPomodoroButton")
            } else {
                if let completed = controller.pomodoro.completedPhase {
                    Text("\(completed.title) complete")
                        .foregroundStyle(.secondary)
                } else {
                    Text("25-minute focus, then a 5-minute break.")
                        .foregroundStyle(.secondary)
                }

                Button("Start \(controller.pomodoro.suggestedPhase.title)") {
                    controller.startPomodoro(controller.pomodoro.suggestedPhase)
                }
                .accessibilityIdentifier("startPomodoroButton")
            }
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
}
