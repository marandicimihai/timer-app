import AppKit
import Charts
import SwiftUI

struct StatisticsView: View {
    private static let allActivitiesID = "statistics:all-activities"

    @EnvironmentObject private var controller: TimerAppController
    @State private var selectedActivityID = ""
    @State private var selectedPeriod: StatisticsPeriod = .sevenDays

    private var statistics: ActivityStatisticsSnapshot {
        controller.activityStore.activityStatistics(
            at: controller.currentDate,
            dayCount: selectedPeriod.dayCount
        )
    }

    private var selectedActivity: ActivityStatistics? {
        guard selectedActivityID != Self.allActivitiesID else { return nil }
        return statistics.activities.first { $0.id == selectedActivityID }
            ?? statistics.activities.first
    }

    private var showsAllActivities: Bool {
        selectedActivityID == Self.allActivitiesID
    }

    private var activitySelection: Binding<String> {
        Binding(
            get: {
                showsAllActivities
                    ? Self.allActivitiesID
                    : selectedActivity?.id ?? ""
            },
            set: { selectedActivityID = $0 }
        )
    }

    var body: some View {
        Group {
            if statistics.activities.isEmpty {
                ContentUnavailableView(
                    "No statistics yet",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Finish a few activities to see their trends and averages.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        controls

                        if showsAllActivities {
                            AllActivitiesLineChart(
                                activities: statistics.activities,
                                period: selectedPeriod
                            )
                        } else if let selectedActivity {
                            ActivityLineChart(
                                activity: selectedActivity,
                                period: selectedPeriod,
                                color: ActivityColorPalette.color(
                                    forActivityID: selectedActivity.id
                                )
                            )
                            selectedActivityInsights(selectedActivity)
                        }

                        overallInsights
                    }
                    .padding(20)
                    .background(StatisticsScrollViewConfigurator())
                }
            }
        }
        .navigationTitle("Statistics")
        .accessibilityIdentifier("statisticsView")
        .onAppear {
            controller.refresh()
            if selectedActivityID.isEmpty {
                selectedActivityID = statistics.activities.first?.id ?? ""
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent {
                Picker("Activity", selection: activitySelection) {
                    Text("All activities").tag(Self.allActivitiesID)
                    ForEach(statistics.activities) { activity in
                        Text(activity.name).tag(activity.id)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
                .accessibilityIdentifier("statisticsActivityPicker")
            } label: {
                Text("Activity")
                    .font(.headline)
            }

            LabeledContent {
                Picker("Days", selection: $selectedPeriod) {
                    ForEach(StatisticsPeriod.allCases) { period in
                        Text(period.shortLabel).tag(period)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 230)
                .accessibilityIdentifier("statisticsPeriodPicker")
            } label: {
                Text("Days")
                    .font(.headline)
            }
        }
    }

    private func selectedActivityInsights(_ activity: ActivityStatistics) -> some View {
        HStack(spacing: 0) {
            compactMetric(
                value: "\(activity.activeDayCount)/\(selectedPeriod.dayCount)",
                label: "Active days"
            )
            Divider().frame(height: 34)
            compactMetric(
                value: "\(activity.currentStreak) d",
                label: "Current streak"
            )
            Divider().frame(height: 34)
            compactMetric(
                value: activity.consistency.formatted(.percent.precision(.fractionLength(0))),
                label: "Consistency"
            )
        }
        .padding(.vertical, 8)
    }

    private var overallInsights: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Text("All activities · \(selectedPeriod.longLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 18) {
                Label(DurationFormatter.concise(statistics.totalDuration), systemImage: "timer")
                    .help("Total time tracked")
                Label("\(statistics.activeDayCount) active days", systemImage: "calendar")
            }
            .font(.callout)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Overall statistics for \(selectedPeriod.longLabel)")
    }

    private func compactMetric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AllActivitiesLineChart: View {
    let activities: [ActivityStatistics]
    let period: StatisticsPeriod

    private let legendColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var axisDates: [Date] {
        guard let days = activities.first?.days else { return [] }
        let selected = days.enumerated().compactMap { index, day in
            index.isMultiple(of: period.xAxisStride) ? day.day : nil
        }
        guard let last = days.last?.day, selected.last != last else { return selected }
        return selected + [last]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("All activities")
                    .font(.headline)
                Text(period.longLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(activities) { activity in
                    ForEach(activity.days) { day in
                        LineMark(
                            x: .value("Day", day.day, unit: .day),
                            y: .value("Time", day.duration)
                        )
                        .foregroundStyle(by: .value("Activity", activity.id))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)

                        if period.dayCount <= 14 {
                            PointMark(
                                x: .value("Day", day.day, unit: .day),
                                y: .value("Time", day.duration)
                            )
                            .foregroundStyle(by: .value("Activity", activity.id))
                            .symbolSize(period == .sevenDays ? 24 : 10)
                        }
                    }
                }
            }
            .chartForegroundStyleScale(mapping: { (activityID: String) in
                ActivityColorPalette.color(forActivityID: activityID)
            })
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisTick()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: axisDateFormat)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let duration = value.as(Double.self) {
                            Text(DurationFormatter.concise(duration))
                        }
                    }
                }
            }
            .frame(height: 280)
            .accessibilityIdentifier("allActivityStatisticsLineChart")

            LazyVGrid(columns: legendColumns, alignment: .leading, spacing: 6) {
                ForEach(activities) { activity in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ActivityColorPalette.color(forActivityID: activity.id))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(activity.name)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .help(activity.name)
                }
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private var axisDateFormat: Date.FormatStyle {
        if period == .sevenDays || period == .fourteenDays {
            return .dateTime.weekday(.narrow)
        }
        return .dateTime.month(.abbreviated).day()
    }
}

private struct StatisticsScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> StatisticsScrollViewProbe {
        StatisticsScrollViewProbe()
    }

    func updateNSView(_ nsView: StatisticsScrollViewProbe, context: Context) {
        nsView.configureSoon()
    }
}

private final class StatisticsScrollViewProbe: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureSoon()
    }

    func configureSoon() {
        DispatchQueue.main.async { [weak self] in
            guard let scrollView = self?.enclosingScrollView else { return }
            StatisticsScrollAppearance.apply(to: scrollView)
        }
    }
}

enum StatisticsScrollAppearance {
    @MainActor
    static func apply(to scrollView: NSScrollView) {
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScroller?.controlSize = .mini
    }
}

private enum StatisticsPeriod: Int, CaseIterable, Identifiable {
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30
    case ninetyDays = 90

    var id: Int { rawValue }
    var dayCount: Int { rawValue }
    var shortLabel: String { "\(rawValue)d" }
    var longLabel: String { "Last \(rawValue) days" }

    var xAxisStride: Int {
        switch self {
        case .sevenDays: 1
        case .fourteenDays: 2
        case .thirtyDays: 7
        case .ninetyDays: 14
        }
    }
}

private struct ActivityLineChart: View {
    let activity: ActivityStatistics
    let period: StatisticsPeriod
    let color: Color

    private var dailyAverage: TimeInterval {
        activity.totalDuration / Double(period.dayCount)
    }

    private var axisDates: [Date] {
        let selected = activity.days.enumerated().compactMap { index, day in
            index.isMultiple(of: period.xAxisStride) ? day.day : nil
        }
        guard let last = activity.days.last?.day, selected.last != last else { return selected }
        return selected + [last]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(activity.name)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    Text(period.longLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                graphMetric(title: "Total", duration: activity.totalDuration)
                graphMetric(title: "Daily average", duration: dailyAverage)
            }

            Chart {
                ForEach(activity.days) { day in
                    AreaMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("Time", day.duration)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [color.opacity(0.22), color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("Time", day.duration)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)

                    if period.dayCount <= 14 {
                        PointMark(
                            x: .value("Day", day.day, unit: .day),
                            y: .value("Time", day.duration)
                        )
                        .foregroundStyle(color)
                        .symbolSize(period == .sevenDays ? 28 : 12)
                    }
                }

                RuleMark(y: .value("Daily average", dailyAverage))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisTick()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: axisDateFormat)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let duration = value.as(Double.self) {
                            Text(DurationFormatter.concise(duration))
                        }
                    }
                }
            }
            .frame(height: 245)
            .accessibilityIdentifier("activityStatisticsLineChart")
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private var axisDateFormat: Date.FormatStyle {
        if period == .sevenDays || period == .fourteenDays {
            return .dateTime.weekday(.narrow)
        }
        return .dateTime.month(.abbreviated).day()
    }

    private func graphMetric(title: String, duration: TimeInterval) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(DurationFormatter.concise(duration))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .frame(minWidth: 76, alignment: .trailing)
    }
}
