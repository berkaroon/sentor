import SwiftUI
import AppKit

enum AppThemeMode: String, CaseIterable, Identifiable, Codable {
    case creamLight
    case oledDark

    var id: String { rawValue }
}

/// Adobe Color Warm Cream & OLED Dark Pastel Harmony design tokens for Sentor.
enum SentorTheme {
    private static let themeDefaultsKey = "sentor.themeMode"

    static var current: AppThemeMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: themeDefaultsKey),
               let mode = AppThemeMode(rawValue: raw) {
                return mode
            }
            return .creamLight
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: themeDefaultsKey)
        }
    }

    static func setTheme(_ mode: AppThemeMode) {
        current = mode
    }

    static var isDarkMode: Bool { current == .oledDark }
    private static var isDark: Bool { isDarkMode }

    // MARK: - Swiss Sage Neutral Surfaces
    static var canvasCream: Color { isDark ? Color(hex: 0x000000) : Color(hex: 0xF5F7F3) }
    static var cardIvory: Color { isDark ? Color(hex: 0x080B08) : Color(hex: 0xFCFDFB) }
    static var surfaceLinen: Color { isDark ? Color(hex: 0x101711) : Color(hex: 0xE4ECE0) }
    static var surfaceHover: Color { isDark ? Color(hex: 0x182219) : Color(hex: 0xD6E2D1) }
    static var borderWarm: Color { isDark ? Color(hex: 0x243025) : Color(hex: 0xC4D1BE) }
    static var gridStrong: Color { isDark ? Color(hex: 0x425A45) : Color(hex: 0x1C3018) }

    // MARK: - Pine & Sage Ink Hierarchy
    static var textCharcoal: Color { isDark ? Color(hex: 0xF2F6F0) : Color(hex: 0x1C3018) }
    static var textMuted: Color { isDark ? Color(hex: 0x8C9E8A) : Color(hex: 0x52644E) }
    static var textSubtle: Color { isDark ? Color(hex: 0x5E6E5C) : Color(hex: 0x7A8C75) }

    // MARK: - Swiss Sage Accents & Stats Bar
    static var sageAccent: Color { isDark ? Color(hex: 0x3D6E49) : Color(hex: 0x3A6845) }
    static var sageAccentFg: Color { isDark ? Color(hex: 0xFCF8F4) : Color(hex: 0xFCF8F4) }
    static var sageBarBg: Color { isDark ? Color(hex: 0x0B120C) : Color(hex: 0x1C3018) }
    static var sageBarFg: Color { isDark ? Color(hex: 0xF5F8F3) : Color(hex: 0xF5F8F3) }
    static var sageBarSubtle: Color { isDark ? Color(hex: 0x8AA387) : Color(hex: 0xA8BEA3) }

    // MARK: - Harmonized Pastel Mode & Status Accents
    static var copySageBg: Color { isDark ? Color(hex: 0x182417) : Color(hex: 0xE4ECE0) }
    static var copySageFg: Color { isDark ? Color(hex: 0xA8C9A3) : Color(hex: 0x2E5638) }

    static var movePeachBg: Color { isDark ? Color(hex: 0x2A1A12) : Color(hex: 0xF6DFD0) }
    static var movePeachFg: Color { isDark ? Color(hex: 0xEAB093) : Color(hex: 0x8B4A2B) }

    static var syncLavenderBg: Color { isDark ? Color(hex: 0x211B29) : Color(hex: 0xEAE3F0) }
    static var syncLavenderFg: Color { isDark ? Color(hex: 0xC9B8DC) : Color(hex: 0x5A4670) }

    static var diffAmberBg: Color { isDark ? Color(hex: 0x282010) : Color(hex: 0xF5E9CE) }
    static var diffAmberFg: Color { isDark ? Color(hex: 0xE5C888) : Color(hex: 0x7A581B) }

    static var deleteRoseBg: Color { isDark ? Color(hex: 0x2A161A) : Color(hex: 0xF4DCE0) }
    static var deleteRoseFg: Color { isDark ? Color(hex: 0xE4A3AE) : Color(hex: 0x863B48) }

    static var accentWarm: Color { isDark ? Color(hex: 0x4A7E56) : Color(hex: 0x3A6845) }

    // MARK: - Typography (Helvetica with SF Pro fallback)
    static let isHelveticaAvailable: Bool = {
        NSFont(name: "Helvetica", size: 13) != nil
    }()

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if isHelveticaAvailable {
            switch weight {
            case .bold, .heavy, .black, .semibold:
                return .custom("Helvetica-Bold", size: size)
            default:
                return .custom("Helvetica", size: size)
            }
        }
        return .system(size: size, weight: weight, design: .default)
    }

    static func mono(size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
