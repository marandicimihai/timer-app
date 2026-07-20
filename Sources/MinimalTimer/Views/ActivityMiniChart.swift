import SwiftUI

struct ActivityMiniChart: View {
    let overview: ActivityOverview

    @State private var hoveredBar: HoveredBar?

    private struct HoveredBar: Equatable {
        let activityID: String
        let period: ActivityChartPeriod
        let location: CGPoint
    }

    private static let chartCoordinateSpace = "activityMiniChart"
    private static let tooltipWidth: CGFloat = 164
    private static let tooltipHeight: CGFloat = 42

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
                ActivityChartPeriod.allCases.map { $0.duration(for: activity) }
            }.max() ?? 0
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if activities.isEmpty {
                Text("No activity logged this week")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(ActivityChartPeriod.allCases) { period in
                        VStack(spacing: 3) {
                            HStack(alignment: .bottom, spacing: 3) {
                                ForEach(activities(for: period)) { activity in
                                    bar(for: activity, period: period)
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
        .coordinateSpace(name: Self.chartCoordinateSpace)
        .overlay {
            GeometryReader { proxy in
                if
                    let hoveredBar,
                    let activity = activities.first(where: { $0.id == hoveredBar.activityID })
                {
                    tooltip(for: activity, period: hoveredBar.period)
                        .position(tooltipPosition(for: hoveredBar, in: proxy.size))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityIdentifier("activitySummaryChart")
        .onDisappear { hoveredBar = nil }
    }

    private var barWidth: CGFloat {
        activities.count <= 3 ? 10 : 7
    }

    private func activities(for period: ActivityChartPeriod) -> [ActivitySeries] {
        overview.chartSeries(for: period)
    }

    private func barHeight(for duration: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 2 }
        return max(4, 38 * duration / maximumDuration)
    }

    private func bar(for activity: ActivitySeries, period: ActivityChartPeriod) -> some View {
        let duration = period.duration(for: activity)

        return ZStack(alignment: .bottom) {
            Color.clear
            RoundedRectangle(cornerRadius: 2)
                .fill(color(for: activity))
                .frame(width: barWidth, height: barHeight(for: duration))
        }
        .frame(width: max(10, barWidth), height: 40)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .named(Self.chartCoordinateSpace)) { phase in
            switch phase {
            case let .active(location):
                hoveredBar = HoveredBar(
                    activityID: activity.id,
                    period: period,
                    location: location
                )
            case .ended:
                if
                    hoveredBar?.activityID == activity.id,
                    hoveredBar?.period == period
                {
                    hoveredBar = nil
                }
            }
        }
        .accessibilityLabel("\(activity.name), \(period.label)")
        .accessibilityValue(DurationFormatter.concise(duration))
    }

    private func tooltip(for activity: ActivitySeries, period: ActivityChartPeriod) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(activity.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(period.label)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Text(DurationFormatter.clock(period.duration(for: activity)))
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .frame(width: Self.tooltipWidth, height: Self.tooltipHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(.separator.opacity(0.5))
        }
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }

    private func tooltipPosition(for hoveredBar: HoveredBar, in size: CGSize) -> CGPoint {
        let horizontalInset = Self.tooltipWidth / 2 + 4
        let x = min(
            max(hoveredBar.location.x, horizontalInset),
            max(horizontalInset, size.width - horizontalInset)
        )
        let verticalOffset = Self.tooltipHeight / 2 + 8
        let belowCursor = hoveredBar.location.y + verticalOffset
        let fitsBelow = belowCursor + Self.tooltipHeight / 2 <= size.height
        let y = fitsBelow ? belowCursor : hoveredBar.location.y - verticalOffset
        return CGPoint(x: x, y: y)
    }

    private func color(for activity: ActivitySeries) -> Color {
        let index = activities.firstIndex { $0.id == activity.id } ?? 0
        return color(for: index, activity: activity)
    }

    private func color(for index: Int, activity: ActivitySeries) -> Color {
        activity.id == "aggregate:other" ? .secondary : colors[index % colors.count]
    }
}

private extension ActivityChartPeriod {
    var label: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .sevenDayAverage: "7-day avg"
        }
    }
}
