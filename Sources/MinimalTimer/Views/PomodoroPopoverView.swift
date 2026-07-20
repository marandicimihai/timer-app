import SwiftUI

struct PomodoroPopoverView: View {
    @ObservedObject private var controller: TimerAppController
    @ObservedObject private var pomodoro: PomodoroTimer

    init(controller: TimerAppController) {
        self.controller = controller
        self.pomodoro = controller.pomodoro
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Pomodoro", systemImage: "circle.circle")
                .font(.headline)

            if let phase = pomodoro.activePhase {
                activeTimer(phase)
            } else if pomodoro.isAwaitingNextPhase {
                nextPhasePrompt
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear { controller.refresh() }
    }

    private func activeTimer(_ phase: PomodoroPhase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(phase.title)
                Spacer()
                Text(DurationFormatter.clock(pomodoro.remainingDuration(at: controller.currentDate)))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: pomodoro.progress(at: controller.currentDate))

            Button("Stop Pomodoro", role: .destructive) {
                controller.stopPomodoro()
            }
            .accessibilityIdentifier("stopPomodoroButton")
        }
    }

    private var nextPhasePrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let completedPhase = pomodoro.completedPhase {
                Text("\(completedPhase.title) complete")
                    .foregroundStyle(.secondary)
            }

            Button("Start \(pomodoro.suggestedPhase.title)") {
                controller.startSuggestedPomodoro()
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("startNextPomodoroButton")
        }
    }
}
