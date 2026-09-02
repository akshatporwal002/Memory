import Foundation

public enum EngramSpacing {
    public static let micro: CGFloat = 4
    public static let small: CGFloat = 8
    public static let compact: CGFloat = 12
    public static let regular: CGFloat = 16
    public static let page: CGFloat = 20
    public static let section: CGFloat = 24
    public static let generous: CGFloat = 32
    public static let large: CGFloat = 48
    public static let extraLarge: CGFloat = 64
}
public enum EngramShape {
    public static let control: CGFloat = 14
    public static let panel: CGFloat = 22
    public static let study: CGFloat = 28
    public static let touchTarget: CGFloat = 44
    public static let readingWidth: CGFloat = 680
}

#if canImport(SwiftUI)
import SwiftUI
public enum EngramMotion {
    public static func feedback(reduceMotion: Bool) -> Animation { .easeOut(duration: 0.12) }
    public static func reveal(reduceMotion: Bool) -> Animation { .easeOut(duration: reduceMotion ? 0.12 : 0.20) }
    public static func navigation(reduceMotion: Bool) -> Animation { .easeOut(duration: reduceMotion ? 0.12 : 0.28) }
    public static func completion(reduceMotion: Bool) -> Animation { .easeOut(duration: reduceMotion ? 0.12 : 0.36) }
    public static func contentTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12))
    }
}

/// Native tab/toolbar rendering remains the platform shell's responsibility.
/// Never layer this material behind review text. Accessibility wins over decoration.
public enum EngramNavigationPolicy {
    public static let fallbackMaterial: Material = .regularMaterial
    public static func needsOpaqueChrome(reduceTransparency: Bool, increasedContrast: Bool) -> Bool {
        reduceTransparency || increasedContrast
    }
}
#endif
