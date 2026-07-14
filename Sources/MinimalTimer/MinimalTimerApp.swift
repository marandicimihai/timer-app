import AppKit
import SwiftData
import SwiftUI

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    var terminationHandler: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        terminationHandler?()
    }
}

@main
struct MinimalTimerApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    private let modelContainer: ModelContainer
    @StateObject private var controller: TimerAppController

    init() {
        do {
            let container = try ActivityPersistence().makeContainer()
            modelContainer = container
            let store = ActivityStore(modelContext: container.mainContext)
            _controller = StateObject(wrappedValue: TimerAppController(
                activityStore: store,
                pomodoro: PomodoroTimer()
            ))
        } catch {
            fatalError("Unable to prepare local activity history: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            TimerPopoverView()
                .environmentObject(controller)
                .onAppear {
                    applicationDelegate.terminationHandler = controller.applicationWillTerminate
                }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: controller.menuBarSymbol)
                if controller.isTimerRunning {
                    Text(controller.menuBarTime)
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("History", id: "history") {
            HistoryView()
                .environmentObject(controller)
        }
        .defaultSize(width: 440, height: 520)
        .modelContainer(modelContainer)
    }
}
