import AppKit
import Carbon
import OSLog
import SwiftUI

@MainActor
final class RecentActivityWheel {
    private let controller: TimerAppController
    private let colors: ActivityColorPreferences
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var panel: NSPanel?
    private var trackingTimer: Timer?
    private var model: WheelSelection?
    private var origin = NSPoint.zero
    private var center = NSPoint.zero
    private var openedAt: TimeInterval = 0
    private var tapDeadline: TimeInterval?
    private static let diameter = 2 * (WheelGeometry.radius + WheelGeometry.hoverGrowth + 1)

    init(controller: TimerAppController, colors: ActivityColorPreferences) {
        self.controller = controller
        self.colors = colors
    }

    func start() {
        guard eventHandler == nil else { return }
        let events = [UInt32(kEventHotKeyPressed), UInt32(kEventHotKeyReleased)].map {
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: $0)
        }
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                guard GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id
                ) == noErr, id.signature == 0x4D54574C, id.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }
                let kind = GetEventKind(event)
                MainActor.assumeIsolated {
                    let wheel = Unmanaged<RecentActivityWheel>.fromOpaque(context).takeUnretainedValue()
                    if kind == kEventHotKeyPressed { wheel.open() } else { wheel.release() }
                }
                return noErr
            },
            events.count, events, Unmanaged.passUnretained(self).toOpaque(), &eventHandler
        )
        guard status == noErr else { return }
        let registration = RegisterEventHotKey(
            UInt32(kVK_ANSI_T), UInt32(optionKey), EventHotKeyID(signature: 0x4D54574C, id: 1),
            GetApplicationEventTarget(), 0, &hotKey
        )
        if registration != noErr {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "MinimalTimer", category: "Shortcuts")
                .error("Could not register Option-T: \(registration)")
            stop()
        }
    }

    func stop() {
        close()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
    }

    private func open() {
        if panel != nil {
            if tapDeadline != nil { close() }
            return
        }
        let activities = controller.wheelActivities()
        guard !activities.isEmpty else { return }
        origin = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) }) ?? NSScreen.main else { return }
        let size = Self.diameter
        let radius = size / 2
        let bounds = screen.visibleFrame
        center = NSPoint(
            x: min(max(origin.x, bounds.minX + radius), bounds.maxX - radius),
            y: min(max(origin.y, bounds.minY + radius), bounds.maxY - radius)
        )
        let selection = WheelSelection(activities: activities)
        let panel = NSPanel(
            contentRect: NSRect(x: center.x - radius, y: center.y - radius, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: WheelView(selection: selection, colors: colors.customColors))
        model = selection
        self.panel = panel
        openedAt = ProcessInfo.processInfo.systemUptime
        panel.orderFrontRegardless()

        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.track() }
        }
        trackingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func track() {
        updateSelection()
        guard let tapDeadline else { return }
        if ProcessInfo.processInfo.systemUptime >= tapDeadline {
            close()
        } else if let model, let index = model.selected {
            let cursor = NSEvent.mouseLocation
            if hypot(cursor.x - center.x, cursor.y - center.y) >= 38 {
                choose(model.activities[index])
            }
        }
    }

    private func updateSelection() {
        guard let model else { return }
        let cursor = NSEvent.mouseLocation
        let x = cursor.x - center.x
        let y = cursor.y - center.y
        let moved = hypot(cursor.x - origin.x, cursor.y - origin.y)
        // At screen edges, wait for the pointer to reach the repositioned wheel.
        let shifted = origin != center
        let index = moved >= 12 && (!shifted || hypot(x, y) <= Self.diameter / 2)
            ? WheelGeometry.selection(x: x, y: y, count: model.activities.count)
            : nil
        if model.selected != index { model.selected = index }
    }

    private func release() {
        guard let model, tapDeadline == nil else { return }
        updateSelection()
        if let index = model.selected {
            choose(model.activities[index])
        } else if ProcessInfo.processInfo.systemUptime - openedAt < 0.22 {
            tapDeadline = ProcessInfo.processInfo.systemUptime + 2
        } else {
            close()
        }
    }

    private func choose(_ activity: TimerAppController.WheelActivity) {
        close()
        controller.selectWheelActivity(activity)
    }

    private func close() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
        tapDeadline = nil
    }
}

enum WheelGeometry {
    static let radius: CGFloat = 76
    static let innerRadius: CGFloat = 20
    static let hoverGrowth: CGFloat = 5

    static func selection(x: CGFloat, y: CGFloat, count: Int) -> Int? {
        guard count > 0, hypot(x, y) >= innerRadius else { return nil }
        let step = 2 * Double.pi / Double(count)
        // Start at twelve o'clock and advance clockwise.
        let angle = atan2(x, y)
        return (Int((angle / step).rounded()) + count) % count
    }

    static func angle(for index: Int, count: Int) -> Double {
        Double(index) * 2 * .pi / Double(count) - .pi / 2
    }
}

@MainActor
private final class WheelSelection: ObservableObject {
    let activities: [TimerAppController.WheelActivity]
    @Published var selected: Int?

    init(activities: [TimerAppController.WheelActivity]) { self.activities = activities }
}

private struct WheelView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var selection: WheelSelection
    let colors: [String: Color]

    var body: some View {
        GeometryReader { proxy in
            let center = proxy.size.width / 2
            let count = selection.activities.count
            let selected = selection.selected
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .overlay { Circle().strokeBorder(.primary.opacity(0.17), lineWidth: 1) }
                    .frame(width: 2 * WheelGeometry.radius, height: 2 * WheelGeometry.radius)

                if count > 1 {
                    Canvas { context, _ in
                        for index in 0..<count {
                            let boundary = WheelGeometry.angle(for: index, count: count) - .pi / Double(count)
                            var line = Path()
                            line.move(to: point(at: boundary, radius: WheelGeometry.innerRadius, center: center))
                            line.addLine(to: point(at: boundary, radius: WheelGeometry.radius, center: center))
                            context.stroke(line, with: .color(.primary.opacity(0.14)), lineWidth: 1)
                        }
                    }
                }

                ForEach(selection.activities.indices, id: \.self) { index in
                    let highlighted = selected == index
                    let tint = color(for: selection.activities[index])
                    let growth = highlighted && !reduceMotion ? WheelGeometry.hoverGrowth : 0
                    let slice = WheelSlice(index: index, count: count, outer: WheelGeometry.radius + growth)
                    slice
                        .fill(.regularMaterial, style: FillStyle(eoFill: true))
                        .overlay { slice.fill(tint.opacity(0.26), style: FillStyle(eoFill: true)) }
                        .overlay { slice.stroke(tint.opacity(0.58), lineWidth: 1) }
                        .opacity(highlighted ? 1 : 0)
                        .animation(hoverTransition, value: highlighted)
                }

                Circle()
                    .fill(.primary.opacity(0.06))
                    .overlay { Circle().strokeBorder(.primary.opacity(0.14), lineWidth: 1) }
                    .overlay {
                        Text("⌥T")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 2 * WheelGeometry.innerRadius, height: 2 * WheelGeometry.innerRadius)

                ForEach(selection.activities.indices, id: \.self) { index in
                    let activity = selection.activities[index]
                    let angle = WheelGeometry.angle(for: index, count: count)
                    let tint = color(for: activity)
                    let highlighted = selected == index
                    let lift: CGFloat = highlighted && !reduceMotion ? 3 : 0
                    VStack(spacing: 2) {
                        if activity.runningID != nil {
                            Text("Stop")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.primary.opacity(0.12), in: Capsule())
                        } else {
                            Circle().fill(tint).frame(width: 6, height: 6)
                        }
                        Text(activity.name)
                            .font(.system(size: 10, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(width: abs(cos(angle)) > 0.8 ? 50 : 64)
                    .accessibilityLabel(activity.runningID == nil ? "Start \(activity.name)" : "Stop \(activity.name)")
                    .position(point(at: angle, radius: 45, center: center))
                    .offset(x: lift * cos(angle), y: lift * sin(angle))
                    .animation(hoverTransition, value: highlighted)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var hoverTransition: Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: reduceMotion ? 0.10 : 0.16)
    }

    private func color(for activity: TimerAppController.WheelActivity) -> Color {
        ActivityColorPalette.color(forActivityNamed: activity.name, customColors: colors)
    }

    private func point(at angle: Double, radius: CGFloat, center: CGFloat) -> CGPoint {
        CGPoint(x: center + radius * cos(angle), y: center + radius * sin(angle))
    }
}

private struct WheelSlice: Shape {
    let index: Int
    let count: Int
    var outer: CGFloat

    var animatableData: CGFloat {
        get { outer }
        set { outer = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let inner = WheelGeometry.innerRadius
        var path = Path()
        if count == 1 {
            path.addEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: 2 * outer, height: 2 * outer))
            path.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner, width: 2 * inner, height: 2 * inner))
        } else {
            let angle = WheelGeometry.angle(for: index, count: count)
            let half = Double.pi / Double(count)
            let start = Angle.radians(angle - half)
            let end = Angle.radians(angle + half)
            path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
            path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
            path.closeSubpath()
        }
        return path
    }
}
