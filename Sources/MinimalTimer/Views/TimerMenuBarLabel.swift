import Combine
import SwiftUI

struct TimerMenuBarLabel: View {
    @ObservedObject var controller: TimerAppController

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")

            if controller.showsTimerValueInMenuBar, let activity = controller.activityStore.activeActivity {
                ActivityMenuBarTime(activity: activity)
            }
        }
    }
}

private struct ActivityMenuBarTime: View {
    let activity: ActiveActivity
    @State private var currentDate = Date()
    private let ticker = Timer.publish(every: 1, tolerance: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        // A TimelineView inside MenuBarExtra's label can cause continuous
        // status-button layout. Keep a plain Text with a local clock instead.
        Text(DurationFormatter.clock(currentDate.timeIntervalSince(activity.startedAt)))
            .monospacedDigit()
            .onReceive(ticker) { currentDate = $0 }
    }
}
