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
