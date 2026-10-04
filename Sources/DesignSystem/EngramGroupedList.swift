import SwiftUI

/// Native grouped sections share Engram's reading surfaces and semantic contrast tokens.
public struct EngramListSection<Content: View, Header: View, Footer: View>: View {
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private let content: Content
    private let header: Header
    private let footer: Footer
    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer) {
        self.content = content(); self.header = header(); self.footer = footer()
    }
    public init(@ViewBuilder content: () -> Content) where Header == EmptyView, Footer == EmptyView {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
    public init(_ title: String, @ViewBuilder content: () -> Content) where Header == Text, Footer == EmptyView {
        self.init(content: content, header: { Text(title) }, footer: { EmptyView() })
    }
    public init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) where Header == EmptyView {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) where Footer == EmptyView {
        self.init(content: content, header: header, footer: { EmptyView() })
    }
    public var body: some View {
        let palette = theme.palette(for: scheme)
        Section {
            content
        } header: {
            header.font(theme.font(.metadata)).foregroundStyle(palette.secondaryText)
        } footer: {
            footer.foregroundStyle(palette.secondaryText)
        }
        .listRowBackground(palette.canvas)
        .listRowSeparatorTint(palette.hairline)
    }
}

private struct EngramSecondaryText: ViewModifier {
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.foregroundStyle(theme.palette(for: scheme).secondaryText) }
}
private struct EngramErrorText: ViewModifier {
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.foregroundStyle(theme.palette(for: scheme).againInk) }
}
public extension View {
    func engramSecondaryText() -> some View { modifier(EngramSecondaryText()) }
    func engramErrorText() -> some View { modifier(EngramErrorText()) }
}
