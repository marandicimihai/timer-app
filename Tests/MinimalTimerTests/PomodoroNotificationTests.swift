import Testing
@preconcurrency import UserNotifications
@testable import MinimalTimer

@Test
func completionNotificationCopyDescribesBothPhaseTransitions() {
    let focus = PomodoroCompletionNotificationCopy(phase: .focus)
    #expect(focus.title == "Focus complete")
    #expect(focus.body == "Your break is ready when you are.")
    #expect(focus.symbolName == "checkmark.circle.fill")
    #expect(focus.actionTitle == "Start Break")
    #expect(focus.nextPhase == .break)

    let rest = PomodoroCompletionNotificationCopy(phase: .break)
    #expect(rest.title == "Break complete")
    #expect(rest.body == "Ready for another focus session?")
    #expect(rest.symbolName == "timer.circle.fill")
    #expect(rest.actionTitle == "Start Focus")
    #expect(rest.nextPhase == .focus)
}

@Test
func notificationCenterEntryDoesNotCompeteWithTheAppCornerBanner() {
    #expect(PomodoroNotificationPresentationPolicy.interruptionLevel == .passive)
    #expect(PomodoroNotificationPresentationPolicy.foregroundOptions.contains(.list))
    #expect(!PomodoroNotificationPresentationPolicy.foregroundOptions.contains(.banner))
    #expect(!PomodoroNotificationPresentationPolicy.foregroundOptions.contains(.sound))
}
