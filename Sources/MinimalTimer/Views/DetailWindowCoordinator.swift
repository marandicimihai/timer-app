import AppKit
import SwiftUI

@MainActor
final class DetailWindowCoordinator: ObservableObject {
    private weak var window: NSWindow?
    private var shouldFocusWhenAvailable = false
    private var focusRequestID: UInt = 0
    private var focusTask: Task<Void, Never>?

    var hasPendingFocusRequest: Bool {
        shouldFocusWhenAvailable
    }

    func requestFocus() {
        shouldFocusWhenAvailable = true
        focusRequestID &+= 1
        focusTask?.cancel()
        focusTask = nil
        scheduleFocusAttempts(for: focusRequestID)
    }

    func cancelPendingFocus() {
        shouldFocusWhenAvailable = false
        focusRequestID &+= 1
        focusTask?.cancel()
        focusTask = nil
    }

    func register(window: NSWindow?) {
        guard let window else { return }
        let windowChanged = self.window !== window
        self.window = window

        // SwiftUI can call updateNSView whenever making the window key changes
        // its scene state. Re-registering that same window must not restart the
        // focus task, or the task continuously cancels and recreates itself.
        guard windowChanged, shouldFocusWhenAvailable, focusTask == nil else { return }
        scheduleFocusAttempts(for: focusRequestID)
    }

    private func focusWindowIfPossible() {
        guard let window else { return }

        if !NSApplication.shared.isActive {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        if !window.isKeyWindow || !window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
        if window.canBecomeMain, !window.isMainWindow {
            window.makeMain()
        }
    }

    private func scheduleFocusAttempts(for requestID: UInt) {
        guard focusTask == nil else { return }
        focusTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if focusRequestID == requestID {
                    focusTask = nil
                }
            }

            // A MenuBarExtra can briefly reclaim key-window status while its
            // popover dismisses. Reassert focus over a few bounded run-loop
            // turns so the detail window finishes opening as the key window.
            for delay in [Duration.zero, .milliseconds(50), .milliseconds(150), .milliseconds(300)] {
                if delay != .zero {
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled else { return }
                } else {
                    await Task.yield()
                }

                guard shouldFocusWhenAvailable, focusRequestID == requestID else { return }
                focusWindowIfPossible()
            }

            guard focusRequestID == requestID else { return }
            shouldFocusWhenAvailable = false
        }
    }
}

struct DetailWindowReader: NSViewRepresentable {
    let coordinator: DetailWindowCoordinator

    func makeNSView(context: Context) -> NSView {
        let view = DetailWindowReaderView()
        view.coordinator = coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? DetailWindowReaderView else { return }
        view.coordinator = coordinator
        coordinator.register(window: view.window)
    }
}

private final class DetailWindowReaderView: NSView {
    weak var coordinator: DetailWindowCoordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.register(window: window)
    }
}
