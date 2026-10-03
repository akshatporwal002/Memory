import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Built-in definitions are versioned independently of library and scheduler schemas.
public enum EngramTheme: String, CaseIterable, Codable, Sendable, Identifiable {
    case warm, neutral, monochrome
    public var id: String { rawValue }
    public var title: String {
        switch self { case .warm: return "Engram Warm"; case .neutral: return "Engram Neutral"; case .monochrome: return "Engram Mono" }
    }
    public static let definitionVersion = 3

    /// Raw sRGB values are shared by native rendering and reproducible contrast checks.
    public func colors(dark: Bool) -> EngramColorTokens {
        switch (self, dark) {
        case (.warm, false):
            return EngramColorTokens(canvas: 0xF7F3E8, surface: 0xFFFCF5, elevated: 0xFFFFFF,
                primaryText: 0x25281F, secondaryText: 0x666650, anchor: 0x434833, onAnchor: 0xFFFCF5,
                accent: 0xD79B42, accentInk: 0x80500D, hairline: 0xDEDACD, controlBorder: 0x777863,
                selection: 0xE0E6D2, answerSelectionInk: 0x80500D, successInk: 0x176B36, curveInk: 0x35452E, missingInk: 0x795000,
                againFill: 0xF3DDDA, againInk: 0x7D302D,
                hardFill: 0xEEE3CE, hardInk: 0x725015, goodFill: 0x434833, goodInk: 0xFFFCF5,
                easyFill: 0xE0E6D2, easyInk: 0x35452E)
        case (.warm, true):
            return EngramColorTokens(canvas: 0x20231C, surface: 0x2C3026, elevated: 0x373C2F,
                primaryText: 0xF7F3E8, secondaryText: 0xC5C3B5, anchor: 0x434833, onAnchor: 0xFFFCF5,
                accent: 0xE8B765, accentInk: 0xE8B765, hairline: 0x4A503F, controlBorder: 0xA4AB95,
                selection: 0x364332, answerSelectionInk: 0xFFB65C, successInk: 0x64E58E, curveInk: 0x64E58E, missingInk: 0xFFD479,
                againFill: 0x4B302E, againInk: 0xFFC1B8,
                hardFill: 0x493C25, hardInk: 0xF5D294, goodFill: 0xD8E2C3, goodInk: 0x293322,
                easyFill: 0x364332, easyInk: 0xDCEBCF)
        case (.neutral, false):
            return EngramColorTokens(canvas: 0xF3F5F6, surface: 0xFFFFFF, elevated: 0xFFFFFF,
                primaryText: 0x202B32, secondaryText: 0x53636D, anchor: 0x304E60, onAnchor: 0xFFFFFF,
                accent: 0xA3C3D2, accentInk: 0x30556A, hairline: 0xD8E0E4, controlBorder: 0x71828C,
                selection: 0xDFEAF0, answerSelectionInk: 0x9A4E00, successInk: 0x176B36, curveInk: 0x30556A, missingInk: 0x795000,
                againFill: 0xF5E1E0, againInk: 0x7D302D,
                hardFill: 0xE8E7E2, hardInk: 0x595347, goodFill: 0x304E60, goodInk: 0xFFFFFF,
                easyFill: 0xDFEAF0, easyInk: 0x30556A)
        case (.neutral, true):
            return EngramColorTokens(canvas: 0x182127, surface: 0x222E36, elevated: 0x2D3B44,
                primaryText: 0xF1F5F7, secondaryText: 0xB7C6D0, anchor: 0x304E60, onAnchor: 0xFFFFFF,
                accent: 0xA3C3D2, accentInk: 0xACD1E4, hairline: 0x455660, controlBorder: 0x9AADBA,
                selection: 0x304955, answerSelectionInk: 0xFFB65C, successInk: 0x64E58E, curveInk: 0xACD1E4, missingInk: 0xFFD479,
                againFill: 0x4B3032, againInk: 0xFFC1BF,
                hardFill: 0x403E34, hardInk: 0xE5D7B3, goodFill: 0xBCD4E0, goodInk: 0x203B49,
                easyFill: 0x304955, easyInk: 0xD1E7F2)
        case (.monochrome, false):
            return EngramColorTokens(canvas: 0xFFFFFF, surface: 0xF5F5F5, elevated: 0xFFFFFF,
                primaryText: 0x171717, secondaryText: 0x555555, anchor: 0x1B1B1B, onAnchor: 0xFFFFFF,
                accent: 0x000000, accentInk: 0x000000, hairline: 0xD0D0D0, controlBorder: 0x666666,
                selection: 0xE8E8E8, answerSelectionInk: 0x9A4E00, successInk: 0x176B36, curveInk: 0x176B36, missingInk: 0x795000,
                againFill: 0xF3DDDA, againInk: 0x7D302D,
                hardFill: 0xEEE3CE, hardInk: 0x725015, goodFill: 0x1B1B1B, goodInk: 0xFFFFFF,
                easyFill: 0xE0E6D2, easyInk: 0x35452E)
        case (.monochrome, true):
            return EngramColorTokens(canvas: 0x000000, surface: 0x101010, elevated: 0x202020,
                primaryText: 0xF5F5F5, secondaryText: 0xB8B8B8, anchor: 0xE5E5E5, onAnchor: 0x111111,
                accent: 0xFFFFFF, accentInk: 0xFFFFFF, hairline: 0x555555, controlBorder: 0xA0A0A0,
                selection: 0x252525, answerSelectionInk: 0xFFB65C, successInk: 0x64E58E, curveInk: 0x64E58E, missingInk: 0xFFD479,
                againFill: 0x4B302E, againInk: 0xFFC1B8,
                hardFill: 0x493C25, hardInk: 0xF5D294, goodFill: 0xE5E5E5, goodInk: 0x111111,
                easyFill: 0x30372A, easyInk: 0xDCEBCF)
        }
    }
}

public struct EngramColorTokens: Sendable {
    public let canvas, surface, elevated, primaryText, secondaryText: UInt32
    public let anchor, onAnchor, accent, accentInk, hairline, controlBorder, selection: UInt32
    public let answerSelectionInk, successInk, curveInk, missingInk: UInt32
    public let againFill, againInk, hardFill, hardInk, goodFill, goodInk, easyFill, easyInk: UInt32
}

public enum EngramAppearance: String, CaseIterable, Codable, Sendable, Identifiable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

#if canImport(SwiftUI)
public struct EngramPalette {
    public let canvas, surface, elevated, primaryText, secondaryText: Color
    public let anchor, onAnchor, accent, accentInk, hairline, controlBorder, selection: Color
    public let answerSelectionInk, successInk, curveInk, missingInk: Color
    public let againFill, againInk, hardFill, hardInk, goodFill, goodInk, easyFill, easyInk: Color

    public init(_ tokens: EngramColorTokens) {
        func color(_ value: UInt32) -> Color {
            Color(.sRGB, red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
        }
        canvas = color(tokens.canvas); surface = color(tokens.surface); elevated = color(tokens.elevated)
        primaryText = color(tokens.primaryText); secondaryText = color(tokens.secondaryText)
        anchor = color(tokens.anchor); onAnchor = color(tokens.onAnchor); accent = color(tokens.accent)
        accentInk = color(tokens.accentInk); hairline = color(tokens.hairline)
        controlBorder = color(tokens.controlBorder); selection = color(tokens.selection)
        answerSelectionInk = color(tokens.answerSelectionInk); successInk = color(tokens.successInk)
        curveInk = color(tokens.curveInk); missingInk = color(tokens.missingInk)
        againFill = color(tokens.againFill); againInk = color(tokens.againInk)
        hardFill = color(tokens.hardFill); hardInk = color(tokens.hardInk)
        goodFill = color(tokens.goodFill); goodInk = color(tokens.goodInk)
        easyFill = color(tokens.easyFill); easyInk = color(tokens.easyInk)
    }
}

public extension EngramTheme {
    func palette(for scheme: ColorScheme) -> EngramPalette { EngramPalette(colors(dark: scheme == .dark)) }
    func font(_ role: EngramTypography) -> Font {
        let editorial: Font.Design = self == .warm || self == .monochrome ? .serif : .default
        switch role {
        case .hero: return .system(.largeTitle, design: editorial, weight: .regular)
        case .title: return .system(.title, design: editorial, weight: .regular)
        case .section: return .system(.title2, design: editorial, weight: .regular)
        case .prompt: return .system(.title2, design: editorial, weight: .regular)
        case .body: return .system(.body, design: .default)
        case .control: return .system(.body, design: .default, weight: .medium)
        case .metadata: return .system(.subheadline, design: .default)
        }
    }
}

public enum EngramTypography { case hero, title, section, prompt, body, control, metadata }
private struct EngramThemeKey: EnvironmentKey { static let defaultValue: EngramTheme = .warm }
public extension EnvironmentValues {
    var engramTheme: EngramTheme {
        get { self[EngramThemeKey.self] }
        set { self[EngramThemeKey.self] = newValue }
    }
}
public extension EngramAppearance {
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}
#endif

#if canImport(SwiftUI)
private struct EngramWorkspaceLayoutKey: EnvironmentKey { static let defaultValue = false }
public extension EnvironmentValues {
    /// Opt-in at the app shell. Never enabled for iPhone, including landscape.
    var engramWorkspaceLayout: Bool {
        get { self[EngramWorkspaceLayoutKey.self] }
        set { self[EngramWorkspaceLayoutKey.self] = newValue }
    }
}
#endif
