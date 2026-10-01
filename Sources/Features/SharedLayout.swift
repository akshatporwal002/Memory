import SwiftUI
import DesignSystem

private struct AssistantBottomInsetKey: EnvironmentKey { static let defaultValue: CGFloat = 72 }
extension EnvironmentValues {
    var engramAssistantBottomInset: CGFloat {
        get { self[AssistantBottomInsetKey.self] }
        set { self[AssistantBottomInsetKey.self] = newValue }
    }
}
struct AssistantDockHeight: PreferenceKey {
    static var defaultValue: CGFloat = 72
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct AssistantClearance: ViewModifier {
    @Environment(\.engramAssistantBottomInset) private var inset
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: inset).allowsHitTesting(false)
        }
    }
}
extension View {
    func engramAssistantClearance() -> some View { modifier(AssistantClearance()) }
}

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

struct EngramTaskContainer<Content: View>: View {
    var embedded: Bool
    @ViewBuilder var content: () -> Content
    var body: some View {
        if embedded { content() } else { NavigationStack { content() } }
    }
}

extension View {
    @ViewBuilder func engramInlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    @ViewBuilder func engramHideBack(_ hidden: Bool) -> some View {
        #if os(iOS)
        navigationBarBackButtonHidden(hidden)
        #else
        self
        #endif
    }
}

struct EngramTaskSizing: ViewModifier {
    let embedded: Bool
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        if embedded { content } else { content.engramSheetSizing(idealWidth: width, minimumHeight: height) }
    }
}

extension View {
    @ViewBuilder func engramHideStudyTabs(_ hidden: Bool = true) -> some View {
        #if os(iOS)
        toolbar(hidden ? .hidden : .visible, for: .tabBar)
        #else
        self
        #endif
    }
}
