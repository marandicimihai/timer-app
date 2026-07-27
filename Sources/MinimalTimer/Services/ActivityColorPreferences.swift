import AppKit
import SwiftUI

@MainActor
final class ActivityColorPreferences: ObservableObject {
    @Published private(set) var customColors: [String: Color]

    private let userDefaults: UserDefaults?
    private static let customColorsKey = "activityColors.custom"

    init(userDefaults: UserDefaults? = .standard) {
        self.userDefaults = userDefaults
        customColors = Self.storedColors(in: userDefaults).reduce(into: [:]) { colors, entry in
            colors[entry.key] = Color(
                nsColor: NSColor(
                    srgbRed: entry.value.red,
                    green: entry.value.green,
                    blue: entry.value.blue,
                    alpha: entry.value.alpha
                )
            )
        }
    }

    func color(forActivityID activityID: String) -> Color {
        ActivityColorPalette.color(forActivityID: activityID, customColors: customColors)
    }

    func colorBinding(forActivityID activityID: String) -> Binding<Color> {
        Binding(
            get: { self.color(forActivityID: activityID) },
            set: { self.setColor($0, forActivityID: activityID) }
        )
    }

    func setColor(_ color: Color, forActivityID activityID: String) {
        guard activityID != "aggregate:other", let rgba = Self.rgbaComponents(for: color) else { return }
        customColors[activityID] = color
        saveCustomColors(replacing: activityID, with: rgba)
    }

    func restoreDefaults() {
        customColors = [:]
        userDefaults?.removeObject(forKey: Self.customColorsKey)
    }

    private func saveCustomColors(replacing activityID: String, with rgba: RGBA) {
        var storedColors = Self.storedColors(in: userDefaults)
        storedColors[activityID] = rgba
        guard let data = try? JSONEncoder().encode(storedColors) else { return }
        userDefaults?.set(data, forKey: Self.customColorsKey)
    }

    private static func rgbaComponents(for color: Color) -> RGBA? {
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return RGBA(
            red: nsColor.redComponent,
            green: nsColor.greenComponent,
            blue: nsColor.blueComponent,
            alpha: nsColor.alphaComponent
        )
    }

    private static func storedColors(in userDefaults: UserDefaults?) -> [String: RGBA] {
        guard
            let data = userDefaults?.data(forKey: customColorsKey),
            let colors = try? JSONDecoder().decode([String: RGBA].self, from: data)
        else { return [:] }
        return colors
    }

    private struct RGBA: Codable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }
}
