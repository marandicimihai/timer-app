import SwiftUI

struct WeeklyGoalsView: View {
    @ObservedObject var activityStore: ActivityStore
    let referenceDate: Date
    @EnvironmentObject private var goalPreferences: ActivityGoalPreferences

    var body: some View {
        if !goalPreferences.goals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Weekly goals")
                    .font(.subheadline.weight(.semibold))

                TimelineView(.everyMinute) { context in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(activityStore.weeklyGoalProgress(
                                for: goalPreferences.goals,
                                at: max(context.date, referenceDate)
                            )) { progress in
                                goalRow(progress)
                            }
                        }
                    }
                    .frame(height: min(CGFloat(goalPreferences.goals.count) * 52 - 10, 230))
                }
            }
            .accessibilityIdentifier("weeklyGoals")
        }
    }

    private func goalRow(_ progress: ActivityGoalProgress) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(progress.goal.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .help(progress.goal.name)

            HStack {
                if !progress.isComplete {
                    Text("\(DurationFormatter.concise((progress.remainingDuration / 60).rounded(.up) * 60)) left")
                }
                Spacer(minLength: 4)
                Text("\(progress.percentage)% complete")
                    .foregroundStyle(progress.isComplete ? Color.green : Color.secondary)
            }
            .font(.caption2.monospacedDigit())

            GeometryReader { geometry in
                Capsule()
                    .fill(.quaternary)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(progress.isComplete ? Color.green : Color.gray)
                            .frame(width: geometry.size.width * min(1, max(0, progress.fraction)))
                    }
            }
            .frame(height: 3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("weeklyGoal.\(progress.id)")
    }

}
