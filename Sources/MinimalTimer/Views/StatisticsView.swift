import AppKit
import Charts
import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject private var controller: TimerAppController
    @State private var selectedActivityID = ""
    @State private var selectedPeriod: StatisticsPeriod = .sevenDays

    var body: some View {
        TimelineView(.everyMinute) { context in
            StatisticsContentView(
                statistics: controller.activityStore.activityStatistics(
                    at: max(context.date, controller.currentDate),
                    dayCount: selectedPeriod.dayCount
                ),
                selectedActivityID: $selectedActivityID,
                selectedPeriod: $selectedPeriod
            )
        }
        .onAppear { controller.refresh() }
    }
}

private struct StatisticsContentView: View {
    private static let allActivitiesID = "statistics:all-activities"

    @EnvironmentObject private var activityColorPreferences: ActivityColorPreferences
    // Share one snapshot across the picker, charts, and totals for this render.
    let statistics: ActivityStatisticsSnapshot
    @Binding var selectedActivityID: String
    @Binding var selectedPeriod: StatisticsPeriod

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
                    systemImage: "chart.bar.xaxis",
                    description: Text("Finish a few activities to see their trends and averages.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        controls

                        if showsAllActivities {
                            AllActivitiesBarChart(
                                activities: statistics.activities,
                                period: selectedPeriod,
                                customColors: activityColorPreferences.customColors
                            )
                        } else if let selectedActivity {
                            ActivityBarChart(
                                activity: selectedActivity,
                                period: selectedPeriod,
                                color: ActivityColorPalette.color(
                                    forActivityID: selectedActivity.id,
                                    customColors: activityColorPreferences.customColors
                                )
                            )
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
}

private struct AllActivitiesBarChart: View {
    let activities: [ActivityStatistics]
    let period: StatisticsPeriod
    let customColors: [String: Color]

    private let legendColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var axisDates: [Date] {
        period.axisDates(for: activities.first?.days ?? [])
    }

    private var maximumDuration: TimeInterval {
        let maximum = activities.flatMap(\.days).map(\.duration).max() ?? 0
        return max(3600, ceil(maximum / 3600) * 3600)
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
                        BarMark(
                            x: .value("Day", day.day, unit: .day),
                            y: .value("Time", day.duration)
                        )
                        .foregroundStyle(by: .value("Activity", activity.id))
                        .position(by: .value("Activity", activity.id))
                    }
                }
            }
            .chartForegroundStyleScale(mapping: { (activityID: String) in
                ActivityColorPalette.color(forActivityID: activityID, customColors: customColors)
            })
            .chartLegend(.hidden)
            .chartYScale(domain: 0...maximumDuration)
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisTick()
                    AxisValueLabel(centered: false, anchor: .top) {
                        if let date = value.as(Date.self) {
                            Text(date, format: axisDateFormat)
                                .fixedSize()
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 3600.0)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let duration = value.as(Double.self) {
                            Text("\(Int(duration / 3600))h")
                        }
                    }
                }
            }
            .frame(height: 280)
            .accessibilityIdentifier("allActivityStatisticsBarChart")

            LazyVGrid(columns: legendColumns, alignment: .leading, spacing: 6) {
                ForEach(activities) { activity in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ActivityColorPalette.color(forActivityID: activity.id, customColors: customColors))
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

    func axisDates(for days: [ActivityDayStatistics]) -> [Date] {
        let calendar = Calendar.current
        return days.enumerated().compactMap { index, day in
            guard index.isMultiple(of: xAxisStride) || index == days.count - 1 else { return nil }
            // Leave room for the final date when it falls close to a regular label.
            if index != days.count - 1 && days.count - 1 - index < xAxisStride / 2 {
                return nil
            }
            guard let interval = calendar.dateInterval(of: .day, for: day.day) else { return day.day }
            // Match the center of the daily bar, including days with daylight-saving changes.
            return interval.start.addingTimeInterval(interval.duration / 2)
        }
    }
}

private struct ActivityBarChart: View {
    let activity: ActivityStatistics
    let period: StatisticsPeriod
    let color: Color

    private var dailyAverage: TimeInterval {
        activity.totalDuration / Double(period.dayCount)
    }

    private var axisDates: [Date] {
        period.axisDates(for: activity.days)
    }

    private var maximumDuration: TimeInterval {
        let maximum = activity.days.map(\.duration).max() ?? 0
        return max(3600, ceil(maximum / 3600) * 3600)
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
                    BarMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("Time", day.duration)
                    )
                    .foregroundStyle(color)
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
            .chartYScale(domain: 0...maximumDuration)
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisTick()
                    AxisValueLabel(centered: false, anchor: .top) {
                        if let date = value.as(Date.self) {
                            Text(date, format: axisDateFormat)
                                .fixedSize()
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 3600.0)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let duration = value.as(Double.self) {
                            Text("\(Int(duration / 3600))h")
                        }
                    }
                }
            }
            .frame(height: 245)
            .accessibilityIdentifier("activityStatisticsBarChart")
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
