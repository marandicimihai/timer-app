import AppKit
import Foundation
import SwiftData
import Testing
@testable import MinimalTimer

@Test @MainActor
func activityLoggingWorksWithoutPomodoro() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)
    let pomodoro = PomodoroTimer(
        settings: makeTestPomodoroSettings(),
        now: { clock.date },
        notifier: TestNotifier()
    )
    let controller = TimerAppController(activityStore: store, pomodoro: pomodoro, now: { clock.date })

    controller.startActivity(named: "Deep work")
    #expect(store.activeActivity?.name == "Deep work")
    #expect(pomodoro.activePhase == nil)

    clock.date.addTimeInterval(600)
    controller.finishActivity()

    #expect(store.sessions.first?.name == "Deep work")
    #expect(store.sessions.first?.duration == 600)
    #expect(pomodoro.activePhase == nil)
}

@Test @MainActor
func recentActivityStartsWithoutPomodoro() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)
    let pomodoro = PomodoroTimer(
        settings: makeTestPomodoroSettings(),
        now: { clock.date },
        notifier: TestNotifier()
    )
    let controller = TimerAppController(activityStore: store, pomodoro: pomodoro, now: { clock.date })

    controller.startActivity(named: "Planning")
    clock.date.addTimeInterval(300)
    controller.finishActivity()
    let recentName = store.recentActivityNames().first!

    controller.startActivity(named: recentName)

    #expect(store.activeActivity?.name == "Planning")
    #expect(pomodoro.activePhase == nil)
}

@Test @MainActor
func finishingAnActivityKeepsTheIndependentPomodoroRunning() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)
    let pomodoro = PomodoroTimer(
        settings: makeTestPomodoroSettings(),
        now: { clock.date },
        notifier: TestNotifier()
    )
    let controller = TimerAppController(activityStore: store, pomodoro: pomodoro, now: { clock.date })

    controller.startActivity(named: "Email")
    controller.startPomodoro(.focus)
    clock.date.addTimeInterval(45)
    controller.finishActivity()

    #expect(store.activeActivity == nil)
    #expect(store.sessions.first?.duration == 45)
    #expect(pomodoro.activePhase == .focus)
}

@Test @MainActor
func switchingActivitiesKeepsTheIndependentPomodoroRunning() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)
    let pomodoro = PomodoroTimer(
        settings: makeTestPomodoroSettings(),
        now: { clock.date },
        notifier: TestNotifier()
    )
    let controller = TimerAppController(activityStore: store, pomodoro: pomodoro, now: { clock.date })

    controller.startActivity(named: "Email")
    controller.startPomodoro(.focus)
    clock.date.addTimeInterval(60)
    controller.startActivity(named: "Design")

    #expect(store.sessions.first?.name == "Email")
    #expect(store.activeActivity?.name == "Design")
    #expect(pomodoro.activePhase == .focus)
}

@Test @MainActor
func pomodoroCanRunWithoutAnActivityFromTheMenuFlow() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)
    let pomodoro = PomodoroTimer(
        settings: makeTestPomodoroSettings(),
        now: { clock.date },
        notifier: TestNotifier()
    )
    let controller = TimerAppController(activityStore: store, pomodoro: pomodoro, now: { clock.date })

    controller.startPomodoro(.focus)

    #expect(store.activeActivity == nil)
    #expect(pomodoro.activePhase == .focus)
    #expect(!controller.showsTimerValueInMenuBar)
    #expect(controller.menuBarTime(at: clock.date).isEmpty)
}

@Test @MainActor
func menuBarTimerValueCanBeHiddenFromSettings() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)
    let settings = makeTestPomodoroSettings()
    let pomodoro = PomodoroTimer(
        settings: settings,
        now: { clock.date },
        notifier: TestNotifier()
    )
    let controller = TimerAppController(activityStore: store, pomodoro: pomodoro, now: { clock.date })

    #expect(!controller.showsTimerValueInMenuBar)

    controller.startActivity(named: "Writing")
    #expect(controller.showsTimerValueInMenuBar)

    controller.finishActivity()
    #expect(!controller.showsTimerValueInMenuBar)

    controller.startActivity(named: "Writing")
    #expect(controller.showsTimerValueInMenuBar)

    controller.setShowTimerValueInMenuBar(false)
    #expect(!controller.showsTimerValueInMenuBar)
    #expect(controller.isTimerRunning)
}

@Test @MainActor
func detailWindowButtonsSelectTheirRequestedTabs() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)
    let pomodoro = PomodoroTimer(
        settings: makeTestPomodoroSettings(),
        now: { clock.date },
        notifier: TestNotifier()
    )
    let controller = TimerAppController(activityStore: store, pomodoro: pomodoro, now: { clock.date })

    controller.showSettingsTab()
    #expect(controller.selectedDetailWindowTab == .settings)

    controller.showHistoryTab()
    #expect(controller.selectedDetailWindowTab == .history)

    controller.showStatisticsTab()
    #expect(controller.selectedDetailWindowTab == .statistics)
}

@Test @MainActor
func openingAMenuBarPopoverCancelsOnlyPendingDetailWindowFocus() {
    let coordinator = DetailWindowCoordinator()

    #expect(!coordinator.hasPendingFocusRequest)
    coordinator.requestFocus()
    #expect(coordinator.hasPendingFocusRequest)

    coordinator.cancelPendingFocus()
    #expect(!coordinator.hasPendingFocusRequest)
}

@Test @MainActor
func statisticsUsesAMiniOverlayScrollbar() {
    let scrollView = NSScrollView()
    scrollView.verticalScroller = NSScroller()

    StatisticsScrollAppearance.apply(to: scrollView)

    #expect(scrollView.scrollerStyle == .overlay)
    #expect(scrollView.autohidesScrollers)
    #expect(scrollView.verticalScroller?.controlSize == .mini)
}

@Test @MainActor
func pomodoroMenuBarIconPreferenceDefaultsToEnabledAndPersists() throws {
    let suiteName = "MinimalTimerTests.MenuBarPreferences.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    defer { userDefaults.removePersistentDomain(forName: suiteName) }
    userDefaults.removePersistentDomain(forName: suiteName)

    let preference = MenuBarPreferences(userDefaults: userDefaults)
    #expect(preference.showsPomodoroIcon)

    preference.setShowsPomodoroIcon(false)

    let reloadedPreference = MenuBarPreferences(userDefaults: userDefaults)
    #expect(!reloadedPreference.showsPomodoroIcon)

    reloadedPreference.restoreDefaults()
    #expect(reloadedPreference.showsPomodoroIcon)
    #expect(MenuBarPreferences(userDefaults: userDefaults).showsPomodoroIcon)
}

@Test @MainActor
func pomodoroMenuBarSpaceStaysReservedWhileItsIconReflectsTimerState() {
    #expect(PomodoroStatusItemController.shouldReserveStatusItem(preferenceEnabled: true))
    #expect(!PomodoroStatusItemController.shouldReserveStatusItem(preferenceEnabled: false))

    #expect(
        !PomodoroStatusItemController.shouldDisplayIcon(
            activePhase: nil,
            isAwaitingNextPhase: false
        )
    )
    #expect(
        PomodoroStatusItemController.shouldDisplayIcon(
            activePhase: .focus,
            isAwaitingNextPhase: false
        )
    )
    #expect(
        PomodoroStatusItemController.shouldDisplayIcon(
            activePhase: .break,
            isAwaitingNextPhase: false
        )
    )
    #expect(
        PomodoroStatusItemController.shouldDisplayIcon(
            activePhase: nil,
            isAwaitingNextPhase: true
        )
    )

    #expect(
        PomodoroStatusItemController.shouldClosePopover(
            preferenceEnabled: true,
            displaysIcon: false
        )
    )
    #expect(
        !PomodoroStatusItemController.shouldClosePopover(
            preferenceEnabled: true,
            displaysIcon: true
        )
    )
}

@Test @MainActor
func mainPopoverPomodoroFlowOffersOnlyTheNextPhase() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)
    let settings = makeTestPomodoroSettings(focusMinutes: 1, breakMinutes: 1)
    let pomodoro = PomodoroTimer(
        settings: settings,
        now: { clock.date },
        notifier: TestNotifier()
    )
    let controller = TimerAppController(activityStore: store, pomodoro: pomodoro, now: { clock.date })

    #expect(pomodoro.suggestedPhase == .focus)
    #expect(!controller.startPomodoro(.break))
    #expect(controller.startSuggestedPomodoro())
    #expect(pomodoro.activePhase == .focus)
    #expect(!controller.startPomodoro(.focus))
    #expect(!controller.startPomodoro(.break))

    clock.date.addTimeInterval(60)
    pomodoro.tick()
    #expect(pomodoro.activePhase == nil)
    #expect(pomodoro.completedPhase == .focus)
    #expect(pomodoro.suggestedPhase == .break)

    #expect(!controller.startPomodoro(.focus))
    #expect(controller.startSuggestedPomodoro())
    #expect(pomodoro.activePhase == .break)

    clock.date.addTimeInterval(60)
    pomodoro.tick()
    #expect(pomodoro.activePhase == nil)
    #expect(pomodoro.completedPhase == .break)
    #expect(pomodoro.suggestedPhase == .focus)
}

@Test
func pomodoroStatusIconProgressIsClamped() {
    #expect(PomodoroStatusIconRenderer.normalized(-1) == 0)
    #expect(PomodoroStatusIconRenderer.normalized(0.4) == 0.4)
    #expect(PomodoroStatusIconRenderer.normalized(2) == 1)
    #expect(PomodoroStatusIconRenderer.normalized(.infinity) == 0)
}

@Test @MainActor
func activityElapsedTimeRemainsInItsMenuBarItemWhilePomodoroRuns() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)
    let settings = makeTestPomodoroSettings(focusMinutes: 25)
    let pomodoro = PomodoroTimer(
        settings: settings,
        now: { clock.date },
        notifier: TestNotifier()
    )
    let controller = TimerAppController(activityStore: store, pomodoro: pomodoro, now: { clock.date })

    controller.startActivity(named: "Writing")
    clock.date.addTimeInterval(60)
    controller.startPomodoro(.focus)

    #expect(controller.menuBarTime(at: clock.date) == "01:00")
    #expect(controller.showsTimerValueInMenuBar)
    #expect(pomodoro.activePhase == .focus)
}

@Test @MainActor
func stoppingPomodoroLeavesTheIndependentActivityRunning() throws {
    let clock = TestClock(Date(timeIntervalSince1970: 1_000))
    let store = try makeStore(clock: clock)
    let pomodoro = PomodoroTimer(
        settings: makeTestPomodoroSettings(),
        now: { clock.date },
        notifier: TestNotifier()
    )
    let controller = TimerAppController(activityStore: store, pomodoro: pomodoro, now: { clock.date })

    controller.startActivity(named: "Review")
    controller.startPomodoro(.focus)
    controller.stopPomodoro()

    #expect(store.activeActivity?.name == "Review")
    #expect(pomodoro.activePhase == nil)
    #expect(controller.showsTimerValueInMenuBar)
}
