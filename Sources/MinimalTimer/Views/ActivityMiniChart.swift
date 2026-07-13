import SwiftUI

struct ActivityMiniChart: View {
    let overview: ActivityOverview

    private struct Bar: Identifiable {
        let id: String
        let label: String
        let duration: TimeInterval
        let isPrimary: Bool
    }

    private var bars: [Bar] {
        [
            Bar(id: "today", label: "Today", duration: overview.todayDuration, isPrimary: true),
            Bar(id: "yesterday", label: "Yesterday", duration: overview.yesterdayDuration, isPrimary: false),
            Bar(id: "average", label: "7-day avg", duration: overview.weeklyDailyAverage, isPrimary: false)
        ]
    }

    private var maximumDuration: TimeInterval {
        max(60, bars.map(\.duration).max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Logged time")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: 12) {
                ForEach(bars) { bar in
                    VStack(spacing: 3) {
                        Text(DurationFormatter.concise(bar.duration))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(bar.isPrimary ? Color.accentColor : Color.secondary.opacity(0.35))
                            .frame(width: 28, height: barHeight(for: bar.duration))

                        Text(bar.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(bar.label)
                    .accessibilityValue(DurationFormatter.concise(bar.duration))
                }
            }
            .frame(height: 64, alignment: .bottom)
        }
        .accessibilityIdentifier("activitySummaryChart")
    }

    private func barHeight(for duration: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 2 }
        return max(5, 34 * duration / maximumDuration)
    }
}
