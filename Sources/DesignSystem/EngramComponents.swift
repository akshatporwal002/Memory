#if canImport(SwiftUI)
import SwiftUI

public enum EngramButtonTone { case primary, secondary, destructive }
public enum EngramGradeTone { case again, hard, good, easy }

public struct EngramButtonStyle: ButtonStyle {
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let tone: EngramButtonTone
    public init(_ tone: EngramButtonTone = .primary) { self.tone = tone }
    public func makeBody(configuration: Configuration) -> some View {
        let palette = theme.palette(for: scheme)
        let fill = tone == .primary ? palette.anchor : tone == .destructive ? palette.againFill : palette.surface
        let ink = tone == .primary ? palette.onAnchor : tone == .destructive ? palette.againInk : palette.primaryText
        configuration.label
            .font(theme.font(.control))
            .multilineTextAlignment(.center)
            .padding(.horizontal, EngramSpacing.regular)
            .padding(.vertical, EngramSpacing.compact)
            .frame(minHeight: EngramShape.touchTarget)
            .foregroundStyle(ink)
            .background(fill, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(palette.controlBorder, lineWidth: 1)
            }
            .overlay {
                if focused {
                    Capsule()
                        .strokeBorder(palette.accentInk, lineWidth: 3).padding(-4)
                }
            }
            .opacity(enabled ? (configuration.isPressed ? 0.80 : 1) : 0.55)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(EngramMotion.feedback(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

private struct EngramSurfaceModifier: ViewModifier {
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    let padding: CGFloat
    func body(content: Content) -> some View {
        let palette = theme.palette(for: scheme)
        content.padding(padding)
            .foregroundStyle(palette.primaryText)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: EngramShape.study, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EngramShape.study, style: .continuous)
                    .strokeBorder(contrast == .increased ? palette.controlBorder : palette.hairline,
                                  lineWidth: contrast == .increased ? 2 : 1)
            }
            .shadow(color: palette.primaryText.opacity(scheme == .dark ? 0 : 0.07), radius: 20, y: 8)
    }
}
private struct EngramCanvasModifier: ViewModifier {
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let palette = theme.palette(for: scheme)
        content.foregroundStyle(palette.primaryText).tint(palette.accentInk)
            .background(palette.canvas.ignoresSafeArea())
    }
}
public extension View {
    func engramSurface(padding: CGFloat = EngramSpacing.section) -> some View {
        modifier(EngramSurfaceModifier(padding: padding))
    }
    func engramCanvas() -> some View { modifier(EngramCanvasModifier()) }
}

public struct EngramGradeButton: View {
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    let label: String
    let interval: String
    let tone: EngramGradeTone
    let action: () -> Void
    public init(label: String, interval: String, tone: EngramGradeTone, action: @escaping () -> Void) {
        self.label = label; self.interval = interval; self.tone = tone; self.action = action
    }
    public var body: some View {
        let palette = theme.palette(for: scheme)
        let colors: (Color, Color) = {
            switch tone {
            case .again: return (palette.againFill, palette.againInk)
            case .hard: return (palette.hardFill, palette.hardInk)
            case .good: return (palette.goodFill, palette.goodInk)
            case .easy: return (palette.easyFill, palette.easyInk)
            }
        }()
        Button(action: action) {
            VStack(spacing: EngramSpacing.micro) {
                Text(label).font(theme.font(.control))
                Text(interval).font(theme.font(.metadata)).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GradeStyle(fill: colors.0, ink: colors.1))
        .accessibilityLabel("\(label), \(interval)")
        .accessibilityHint("Save this rating and continue")
    }
}
private struct GradeStyle: ButtonStyle {
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let fill: Color
    let ink: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(EngramSpacing.compact)
            .frame(minHeight: EngramShape.touchTarget)
            .multilineTextAlignment(.center).foregroundStyle(ink)
            .background(fill, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(theme.palette(for: scheme).controlBorder, lineWidth: 1)
            }
            .overlay {
                if focused {
                    Capsule()
                        .strokeBorder(theme.palette(for: scheme).accentInk, lineWidth: 3).padding(-4)
                }
            }
            .opacity(enabled ? (configuration.isPressed ? 0.80 : 1) : 0.55)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(EngramMotion.feedback(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

public struct EngramTag: View {
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    let text: String
    let selected: Bool
    public init(text: String, selected: Bool = false) { self.text = text; self.selected = selected }
    public var body: some View {
        let palette = theme.palette(for: scheme)
        HStack(spacing: EngramSpacing.micro) {
            if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(theme.font(.metadata)).foregroundStyle(palette.primaryText)
        .padding(.horizontal, EngramSpacing.compact).padding(.vertical, EngramSpacing.small)
        .background(selected ? palette.selection : palette.surface, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text).accessibilityValue(selected ? "Selected" : "")
    }
}

public struct EngramInlineError: View {
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    let message: String
    public init(message: String) { self.message = message }
    public var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(theme.font(.metadata)).fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(theme.palette(for: scheme).againInk)
            .padding(.vertical, EngramSpacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

public struct EngramEmptyState: View {
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    let title: String
    let message: String
    let symbol: String
    public init(title: String, message: String, symbol: String = "rectangle.on.rectangle") {
        self.title = title; self.message = message; self.symbol = symbol
    }
    public var body: some View {
        VStack(spacing: EngramSpacing.regular) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(theme.palette(for: scheme).accentInk)
                .accessibilityHidden(true)
            Text(title).font(theme.font(.title)).accessibilityAddTraits(.isHeader)
            Text(message).font(theme.font(.body)).foregroundStyle(theme.palette(for: scheme).secondaryText)
        }
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: EngramShape.readingWidth).padding(EngramSpacing.section)
    }
}

/// The caller owns submission state and performs the durable operation before navigation.
public struct EngramActionButton: View {
    let title: String
    let busy: Bool
    let action: () -> Void
    public init(_ title: String, busy: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.busy = busy; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Text(title)
            }.frame(maxWidth: .infinity)
        }
        .buttonStyle(EngramButtonStyle()).disabled(busy)
        .accessibilityValue(busy ? "In progress" : "")
    }
}
#endif
