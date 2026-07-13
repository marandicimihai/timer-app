import SwiftUI

struct ActivityMiniChart: View {
    let overview: ActivityOverview

    private enum Period: String, CaseIterable, Identifiable {
        case today
        case yesterday
        case average

        var id: String { rawValue }

        var label: String {
            switch self {
            case .today: "Today"
            case .yesterday: "Yesterday"
            case .average: "7-day avg"
            }
        }

        func duration(for activity: ActivitySeries) -> TimeInterval {
            switch self {
            case .today: activity.todayDuration
            case .yesterday: activity.yesterdayDuration
            case .average: activity.weeklyDailyAverage
            }
        }
    }

    private let colors: [Color] = [.blue, .orange, .green, .purple, .pink]
    private let legendColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private var activities: [ActivitySeries] {
        overview.chartSeries()
    }

    private var maximumDuration: TimeInterval {
        max(
            60,
            activities.flatMap { activity in
                Period.allCases.map { $0.duration(for: activity) }
            }.max() ?? 0
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Logged time")
                .font(.caption)
                .foregroundStyle(.secondary)

            if activities.isEmpty {
                Text("No activity logged this week")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(Period.allCases) { period in
                        VStack(spacing: 3) {
                            HStack(alignment: .bottom, spacing: 3) {
                                ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                                    let duration = period.duration(for: activity)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(color(for: index, activity: activity).opacity(duration > 0 ? 1 : 0.15))
                                        .frame(width: barWidth, height: barHeight(for: duration))
                                        .accessibilityLabel("\(activity.name), \(period.label)")
                                        .accessibilityValue(DurationFormatter.concise(duration))
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .bottom)

                            Text(period.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: legendColumns, alignment: .leading, spacing: 4) {
                    ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(color(for: index, activity: activity))
                                .frame(width: 7, height: 7)
                            Text(activity.name)
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .help(activity.name)
                    }
                }
            }
        }
        .accessibilityIdentifier("activitySummaryChart")
    }

    private var barWidth: CGFloat {
        activities.count <= 3 ? 10 : 7
    }

    private func barHeight(for duration: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 2 }
        return max(4, 38 * duration / maximumDuration)
    }

    private func color(for index: Int, activity: ActivitySeries) -> Color {
        activity.id == "aggregate:other" ? .secondary : colors[index % colors.count]
    }
}
