import SwiftUI

struct WeeklyGoalsView: View {
    @ObservedObject var activityStore: ActivityStore
    let referenceDate: Date
    @EnvironmentObject private var goalPreferences: ActivityGoalPreferences

    var body: some View {
        if !goalPreferences.goals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Weekly goals")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("Mon–Sun")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

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
                Text("\(progress.completedHours.formatted(.number.precision(.fractionLength(0...1))))/\(progress.goal.hours.formatted(.number.precision(.fractionLength(0...2)))) hours")
                Spacer(minLength: 4)
                Text("\(progress.percentage)% complete")
                    .foregroundStyle(color(for: progress.level))
            }
            .font(.caption2.monospacedDigit())

            GeometryReader { geometry in
                Capsule()
                    .fill(.quaternary)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color(for: progress.level))
                            .frame(width: geometry.size.width * min(1, max(0, progress.fraction)))
                    }
            }
            .frame(height: 3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("weeklyGoal.\(progress.id)")
    }

    private func color(for level: ActivityGoalProgressLevel) -> Color {
        switch level {
        case .red: .red
        case .yellow: .yellow
        case .green: .green
        }
    }
}
