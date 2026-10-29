import AppKit
import SwiftUI

struct TimerPopoverView: View {
    @EnvironmentObject private var controller: TimerAppController
    @EnvironmentObject private var detailWindowCoordinator: DetailWindowCoordinator
    @EnvironmentObject private var activityColorPreferences: ActivityColorPreferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var activityName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Minimal Timer")
                .font(.headline)

            if let activity = controller.activityStore.activeActivity {
                currentActivityStatus(activity)
            }

            activityCard
            WeeklyGoalsView(activityStore: controller.activityStore, referenceDate: controller.currentDate)
            if controller.pomodoro.settings.isEnabled {
                Divider()
                PomodoroMainControls(controller: controller)
                Divider()
            }
            HStack {
                Button("Settings") {
                    controller.showSettingsTab()
                    openDetailWindow()
                }
                .accessibilityIdentifier("settingsButton")

                Spacer()

                Button("Quit Timer") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 330)
        .onAppear {
            detailWindowCoordinator.cancelPendingFocus()
            NotificationCenter.default.post(name: .minimalTimerActivityPopoverDidOpen, object: nil)
            controller.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .minimalTimerPomodoroPopoverWillOpen)
        ) { _ in
            dismiss()
        }
    }

    private var activityCard: some View {
        let recentActivities = controller.activityStore.recentActivityNames()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Start a new activity", text: $activityName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(startActivity)
                    .accessibilityIdentifier("activityNameField")

                Button("Start") {
                    startActivity()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("startActivityButton")
            }

            if !recentActivities.isEmpty {
                RecentActivitiesScrollView {
                    HStack(spacing: 6) {
                        ForEach(
                            Array(recentActivities.enumerated()),
                            id: \.element
                        ) { index, name in
                            Button(name) {
                                startRecentActivity(named: name)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .accessibilityIdentifier("recentActivityButton\(index)")
                            .help("Start \(name)")
                            .contextMenu {
                                Button("Delete Activity and History", role: .destructive) {
                                    controller.deleteActivityHistory(named: name)
                                }
                                .disabled(controller.activityStore.isArchived(activityNamed: name))
                            }
                        }
                    }
                }
                .padding(.bottom, 6)
            }

            TimelineView(.everyMinute) { context in
                ActivityMiniChart(
                    overview: controller.activityStore.activityOverview(at: max(context.date, controller.currentDate)),
                    customColors: activityColorPreferences.customColors
                )
            }
            .padding(.top, 2)
        }
    }

    private func currentActivityStatus(_ activity: ActiveActivity) -> some View {
        let activityColor = ActivityColorPalette.color(
            forActivityNamed: activity.name,
            customColors: activityColorPreferences.customColors
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(activityColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                Text("Current activity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(activity.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(DurationFormatter.clock(context.date.timeIntervalSince(activity.startedAt)))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Button("Finish Activity") {
                controller.finishActivity()
            }
            .controlSize(.small)
            .accessibilityIdentifier("finishActivityButton")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            activityColor.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(activityColor.opacity(0.2), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Current activity: \(activity.name)")
    }

    private func startActivity() {
        controller.startActivity(named: activityName)
        activityName = ""
    }

    private func startRecentActivity(named name: String) {
        controller.startActivity(named: name)
        activityName = ""
    }

    private func openDetailWindow() {
        dismiss()
        DispatchQueue.main.async {
            openWindow(id: "history")
            detailWindowCoordinator.requestFocus()
        }
    }
}

struct RecentActivitiesScrollView<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var metrics = RecentActivitiesScrollMetrics()
    @State private var showsIndicator = false

    var body: some View {
        ScrollView(.horizontal) {
            content
                .background(RecentActivitiesScrollObserver { updated in
                    if metrics.width > 0, abs(updated.offset - metrics.offset) > 0.1 {
                        showsIndicator = true
                    }
                    metrics = updated
                })
                .padding(.bottom, 5)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottomLeading) {
            GeometryReader { geometry in
                let viewport = geometry.size.width
                if metrics.width > metrics.viewport, metrics.viewport > 0 {
                    let thumbWidth = min(viewport, max(20, viewport * viewport / metrics.width))
                    let fraction = min(1, max(0, metrics.offset / (metrics.width - metrics.viewport)))
                    Capsule()
                        .fill(Color.primary.opacity(0.65))
                        .frame(width: thumbWidth, height: 2)
                        .offset(x: fraction * (viewport - thumbWidth), y: geometry.size.height - 2)
                        .opacity(showsIndicator ? 1 : 0)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .task(id: metrics.offset) {
            do {
                try await Task.sleep(for: .milliseconds(1_200))
                withAnimation(.easeOut(duration: 0.2)) {
                    showsIndicator = false
                }
            } catch {
                // Further scrolling restarts the fade delay.
            }
        }
    }
}

struct RecentActivitiesScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var width: CGFloat = 0
    var viewport: CGFloat = 0
}

private struct RecentActivitiesScrollObserver: NSViewRepresentable {
    let onScroll: (RecentActivitiesScrollMetrics) -> Void

    func makeNSView(context: Context) -> RecentActivitiesScrollViewProbe {
        RecentActivitiesScrollViewProbe()
    }

    func updateNSView(_ nsView: RecentActivitiesScrollViewProbe, context: Context) {
        nsView.onScroll = onScroll
        nsView.configureSoon()
    }
}

final class RecentActivitiesScrollViewProbe: NSView {
    var onScroll: ((RecentActivitiesScrollMetrics) -> Void)?
    private(set) var latestMetrics = RecentActivitiesScrollMetrics()
    private weak var observedScrollView: NSScrollView?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureSoon()
    }

    func configureSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.configure()
        }
    }

    func configure() {
        guard let scrollView = enclosingScrollView else { return }
        if observedScrollView !== scrollView {
            NotificationCenter.default.removeObserver(self)
            observedScrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollView.documentView?.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(scrollGeometryChanged),
                name: NSView.boundsDidChangeNotification, object: scrollView.contentView
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(scrollGeometryChanged),
                name: NSView.frameDidChangeNotification, object: scrollView.documentView
            )
        }
        reportMetrics()
    }

    @objc private func scrollGeometryChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.reportMetrics()
        }
    }

    private func reportMetrics() {
        guard let scrollView = observedScrollView, let document = scrollView.documentView else { return }
        latestMetrics = RecentActivitiesScrollMetrics(
            offset: scrollView.contentView.bounds.minX - document.bounds.minX,
            width: document.bounds.width,
            viewport: scrollView.contentView.bounds.width
        )
        onScroll?(latestMetrics)
    }
}

private struct PomodoroMainControls: View {
    @ObservedObject private var controller: TimerAppController
    @ObservedObject private var pomodoro: PomodoroTimer

    init(controller: TimerAppController) {
        self.controller = controller
        self.pomodoro = controller.pomodoro
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pomodoro", systemImage: "circle.circle")
                .font(.headline)

            if let activePhase = pomodoro.activePhase {
                HStack {
                    Text("\(activePhase.title) in progress")
                    Spacer()
                    Button("Stop Pomodoro", role: .destructive) {
                        controller.stopPomodoro()
                    }
                    .accessibilityIdentifier("stopPomodoroButton")
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ProgressView(value: pomodoro.progress(at: context.date))
                }
            } else {
                if pomodoro.isAwaitingNextPhase, let completedPhase = pomodoro.completedPhase {
                    Text("\(completedPhase.title) complete")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Start \(pomodoro.suggestedPhase.title)") {
                        controller.startSuggestedPomodoro()
                    }
                    .accessibilityIdentifier("startPomodoroButton")

                    if pomodoro.isAwaitingNextPhase {
                        Spacer()
                        Button("Stop Pomodoro", role: .destructive) {
                            controller.stopPomodoro()
                        }
                        .accessibilityIdentifier("stopAwaitingPomodoroButton")
                    }
                }
            }
        }
    }
}
