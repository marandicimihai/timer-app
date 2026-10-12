import SwiftUI

struct DetailWindowView: View {
    @EnvironmentObject private var controller: TimerAppController

    var body: some View {
        VStack(spacing: 0) {
            Picker("Navigation", selection: $controller.selectedDetailWindowTab) {
                ForEach(DetailWindowTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("detailNavigationPicker")
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            content(for: controller.selectedDetailWindowTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private func content(for tab: DetailWindowTab) -> some View {
        switch tab {
        case .settings: SettingsView()
        case .statistics: StatisticsView()
        case .goals: GoalsSettingsView()
        case .manageActivities: ManageActivitiesView()
        case .pomodoro: PomodoroSettingsView()
        case .history: HistoryView()
        }
    }
}
