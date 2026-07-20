import SwiftUI

struct TimerMenuBarLabel: View {
    @ObservedObject var controller: TimerAppController

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")

            if controller.showsTimerValueInMenuBar {
                Text(controller.menuBarTime(at: controller.currentDate))
                    .monospacedDigit()
            }
        }
    }
}
