import AppKit
import SwiftData
import SwiftUI

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private var didFinishLaunching = false
    private var didScheduleStartup = false
    private var controller: TimerAppController?
    private var pomodoroStatusItemController: PomodoroStatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        didFinishLaunching = true
        scheduleStartupIfPossible()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.applicationWillTerminate()
    }

    func configureLifecycle(
        controller: TimerAppController,
        pomodoroStatusItemController: PomodoroStatusItemController
    ) {
        self.controller = controller
        self.pomodoroStatusItemController = pomodoroStatusItemController
        scheduleStartupIfPossible()
    }

    private func scheduleStartupIfPossible() {
        guard
            didFinishLaunching,
            !didScheduleStartup,
            let pomodoroStatusItemController
        else { return }
        didScheduleStartup = true
        DispatchQueue.main.async {
            pomodoroStatusItemController.start()
        }
    }
}

@main
struct MinimalTimerApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    private let modelContainer: ModelContainer
    @StateObject private var controller: TimerAppController
    @StateObject private var detailWindowCoordinator: DetailWindowCoordinator
    @StateObject private var menuBarPreferences: MenuBarPreferences
    @StateObject private var activityColorPreferences: ActivityColorPreferences
    @StateObject private var activityGoalPreferences: ActivityGoalPreferences
    @StateObject private var activityArchivePreferences: ActivityArchivePreferences
    @StateObject private var pomodoroStatusItemController: PomodoroStatusItemController

    init() {
        let detailWindowCoordinator = DetailWindowCoordinator()
        _detailWindowCoordinator = StateObject(wrappedValue: detailWindowCoordinator)
        do {
            let container = try ActivityPersistence().makeContainer()
            modelContainer = container
            let archives = ActivityArchivePreferences()
            let store = ActivityStore(modelContext: container.mainContext, archivePreferences: archives)
            let pomodoroSettings = PomodoroSettings()
            let timerController = TimerAppController(
                activityStore: store,
                pomodoro: PomodoroTimer(settings: pomodoroSettings)
            )
            let menuBarPreferences = MenuBarPreferences()
            let activityColorPreferences = ActivityColorPreferences(archivePreferences: archives)
            _controller = StateObject(wrappedValue: timerController)
            _menuBarPreferences = StateObject(wrappedValue: menuBarPreferences)
            _activityColorPreferences = StateObject(wrappedValue: activityColorPreferences)
            _activityGoalPreferences = StateObject(wrappedValue: ActivityGoalPreferences(archivePreferences: archives))
            _activityArchivePreferences = StateObject(wrappedValue: archives)
            _pomodoroStatusItemController = StateObject(
                wrappedValue: PomodoroStatusItemController(
                    controller: timerController,
                    preferences: menuBarPreferences,
                    detailWindowCoordinator: detailWindowCoordinator
                )
            )
        } catch {
            fatalError("Unable to prepare local activity history: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            TimerPopoverView()
                .environmentObject(controller)
                .environmentObject(detailWindowCoordinator)
                .environmentObject(activityColorPreferences)
                .environmentObject(activityGoalPreferences)
                .environmentObject(activityArchivePreferences)
        } label: {
            TimerMenuBarLabel(controller: controller)
                .onAppear {
                    applicationDelegate.configureLifecycle(
                        controller: controller,
                        pomodoroStatusItemController: pomodoroStatusItemController
                    )
                }
        }
        .menuBarExtraStyle(.window)

        Window("Minimal Timer", id: "history") {
            DetailWindowView()
                .environmentObject(controller)
                .environmentObject(menuBarPreferences)
                .environmentObject(activityColorPreferences)
                .environmentObject(activityGoalPreferences)
                .environmentObject(activityArchivePreferences)
                .background(DetailWindowReader(coordinator: detailWindowCoordinator))
        }
        .defaultSize(width: 780, height: 600)
        .modelContainer(modelContainer)
    }
}
