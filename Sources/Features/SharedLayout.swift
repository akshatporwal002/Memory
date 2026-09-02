import SwiftUI
import DesignSystem

extension View {
    /// Desktop sheets need a useful initial size. Mobile sheets follow actual safe-area geometry.
    @ViewBuilder func engramSheetSizing(idealWidth: CGFloat, minimumHeight: CGFloat) -> some View {
        #if os(macOS)
        frame(minWidth: 300, idealWidth: idealWidth, minHeight: minimumHeight)
        #else
        self
        #endif
    }
}

private struct EngramNumericModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Int
    func body(content: Content) -> some View {
        content.contentTransition(reduceMotion ? .opacity : .numericText(value: Double(value)))
            .animation(EngramMotion.feedback(reduceMotion: reduceMotion), value: value)
    }
}
extension View {
    func engramNumericTransition(value: Int) -> some View { modifier(EngramNumericModifier(value: value)) }
}
