import SwiftUI

private struct ScreenshotCaptureKey: EnvironmentKey { static let defaultValue = false }
private struct ScreenshotEditorPreviewKey: EnvironmentKey { static let defaultValue = false }
private struct ScreenshotProgressKey: EnvironmentKey { static let defaultValue = "" }
private struct ScreenshotHiddenKey: EnvironmentKey { static let defaultValue = false }
private struct ScreenshotCancelKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
private struct ScreenshotAcknowledgementsKey: EnvironmentKey { static let defaultValue = false }

public extension EnvironmentValues {
    /// Suppresses automatic keyboard focus during a read-only screenshot tour.
    var engramScreenshotCapture: Bool {
        get { self[ScreenshotCaptureKey.self] }
        set { self[ScreenshotCaptureKey.self] = newValue }
    }
    var engramScreenshotEditorPreview: Bool {
        get { self[ScreenshotEditorPreviewKey.self] }
        set { self[ScreenshotEditorPreviewKey.self] = newValue }
    }
    var engramScreenshotProgress: String {
        get { self[ScreenshotProgressKey.self] }
        set { self[ScreenshotProgressKey.self] = newValue }
    }
    var engramScreenshotHideControls: Bool {
        get { self[ScreenshotHiddenKey.self] }
        set { self[ScreenshotHiddenKey.self] = newValue }
    }
    var engramScreenshotCancel: (() -> Void)? {
        get { self[ScreenshotCancelKey.self] }
        set { self[ScreenshotCancelKey.self] = newValue }
    }
    var engramScreenshotAcknowledgements: Bool {
        get { self[ScreenshotAcknowledgementsKey.self] }
        set { self[ScreenshotAcknowledgementsKey.self] = newValue }
    }
}

public extension View {
    func engramCaptureSurface() -> some View { modifier(CaptureSurfaceModifier()) }
}

private struct CaptureSurfaceModifier: ViewModifier {
    @Environment(\.engramScreenshotCapture) private var capturing
    @Environment(\.engramScreenshotProgress) private var progress
    @Environment(\.engramScreenshotHideControls) private var hidden
    @Environment(\.engramScreenshotCancel) private var cancel
    func body(content: Content) -> some View {
        if capturing {
            content
            .allowsHitTesting(false)
            .interactiveDismissDisabled(true)
            .overlay(alignment: .top) {
                if !hidden {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(progress).font(.callout)
                        Button("Cancel capture") { cancel?() }
                    }
                    .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(8)
                }
            }
        } else { content }
    }
}
