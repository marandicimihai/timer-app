import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject private var controller: TimerAppController

    private let summaryColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var statistics: ActivityStatisticsSnapshot {
        controller.activityStore.activityStatistics(at: controller.currentDate)
    }

    var body: some View {
        Group {
            if statistics.activities.isEmpty {
                ContentUnavailableView(
                    "No statistics yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Finish a few activities to see your trends and consistency.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        overview
                        dailyActivity
                        activityBreakdown
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Statistics")
        .accessibilityIdentifier("statisticsView")
        .onAppear { controller.refresh() }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Last 30 days", subtitle: overviewSubtitle)

            LazyVGrid(columns: summaryColumns, spacing: 10) {
                statisticCard(
                    title: "Time tracked",
                    value: DurationFormatter.concise(statistics.totalDuration),
                    detail: "\(statistics.sessionCount) \(statistics.sessionCount == 1 ? "session" : "sessions")",
                    symbol: "timer"
                )
                statisticCard(
                    title: "Active days",
                    value: "\(statistics.activeDayCount) of \(statistics.dayCount)",
                    detail: DurationFormatter.concise(statistics.averagePerActiveDay) + " per active day",
                    symbol: "calendar"
                )
                statisticCard(
                    title: "Current streak",
                    value: dayCountLabel(statistics.currentStreak),
                    detail: streakDetail,
                    symbol: "flame.fill"
                )
                statisticCard(
                    title: "Consistency",
                    value: statistics.consistency.formatted(.percent.precision(.fractionLength(0))),
                    detail: "Days with tracked activity",
                    symbol: "checkmark.circle.fill"
                )
            }
        }
    }

    private var dailyActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Daily activity", subtitle: "Your tracked time across the last 30 days")
            DailyActivityChart(days: statistics.days)
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private var activityBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Activities", subtitle: "Time, frequency, and consistency by activity")

            ForEach(Array(statistics.activities.enumerated()), id: \.element.id) { index, activity in
                if index > 0 {
                    Divider()
                }
                ActivityStatisticsRow(
                    activity: activity,
                    maximumDuration: statistics.activities.first?.totalDuration ?? 1,
                    dayCount: statistics.dayCount
                )
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statisticCard(
        title: String,
        value: String,
        detail: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSubtitle: String {
        guard let leadingActivity = statistics.activities.first else {
            return "Your activity at a glance"
        }
        return "Most time spent on \(leadingActivity.name)"
    }

    private var streakDetail: String {
        guard statistics.bestStreak > 0 else { return "No streak recorded yet" }
        return "Best: \(dayCountLabel(statistics.bestStreak))"
    }

    private func dayCountLabel(_ count: Int) -> String {
        "\(count) \(count == 1 ? "day" : "days")"
    }
}

private struct DailyActivityChart: View {
    let days: [ActivityDayStatistics]

    private var maximumDuration: TimeInterval {
        max(60, days.map(\.duration).max() ?? 0)
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(days) { day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(day.duration > 0 ? Color.accentColor : Color.secondary.opacity(0.16))
                            .frame(
                                maxWidth: .infinity,
                                minHeight: day.duration > 0 ? 3 : 2,
                                maxHeight: barHeight(for: day.duration, availableHeight: proxy.size.height)
                            )
                            .help(tooltip(for: day))
                            .accessibilityLabel(day.day.formatted(date: .complete, time: .omitted))
                            .accessibilityValue(DurationFormatter.concise(day.duration))
                    }
                }
            }
            .frame(height: 76)

            HStack {
                if let firstDay = days.first {
                    Text(firstDay.day, format: .dateTime.month(.abbreviated).day())
                }
                Spacer()
                Text("Today")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("dailyActivityChart")
    }

    private func barHeight(for duration: TimeInterval, availableHeight: CGFloat) -> CGFloat {
        guard duration > 0 else { return 2 }
        return max(3, availableHeight * duration / maximumDuration)
    }

    private func tooltip(for day: ActivityDayStatistics) -> String {
        let date = day.day.formatted(date: .abbreviated, time: .omitted)
        return "\(date): \(DurationFormatter.concise(day.duration))"
    }
}

private struct ActivityStatisticsRow: View {
    let activity: ActivityStatistics
    let maximumDuration: TimeInterval
    let dayCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(activity.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text(DurationFormatter.concise(activity.totalDuration))
                    .monospacedDigit()
            }

            ProgressView(value: activity.totalDuration, total: max(1, maximumDuration))
                .progressViewStyle(.linear)

            HStack(spacing: 5) {
                Text("\(activity.activeDayCount)/\(dayCount) active days")
                Text("·")
                Text("\(activity.sessionCount) \(activity.sessionCount == 1 ? "session" : "sessions")")
                Text("·")
                Text(activity.consistency.formatted(.percent.precision(.fractionLength(0))) + " consistent")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Label(streakText, systemImage: "flame")
                .font(.caption2)
                .foregroundStyle(activity.currentStreak > 0 ? .orange : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activity.name) statistics")
    }

    private var streakText: String {
        if activity.currentStreak > 0 {
            return "\(activity.currentStreak)-day current streak · \(activity.bestStreak)-day best"
        }
        return "Best streak: \(activity.bestStreak) \(activity.bestStreak == 1 ? "day" : "days")"
    }
}
