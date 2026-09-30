import SwiftUI
import LearningCore
#if os(iOS)
import UIKit
#else
import AppKit
import ScreenCaptureKit
#endif

/// Captures only the window hosting Engram. No screen-recording or Photos permission.
/// The weak probe is owned by SwiftUI; it never retains a window after the tour ends.
@MainActor final class NativeScreenCapture {
    #if os(iOS)
    weak var probe: UIView?
    private var window: UIWindow? { probe?.window }
    #else
    weak var probe: NSView?
    private var window: NSWindow? {
        guard var window = probe?.window else { return nil }
        while let sheet = window.attachedSheet { window = sheet }
        return window
    }
    #endif

    func png() async throws -> Data {
        #if os(iOS)
        guard let window, window.bounds.width > 0, window.bounds.height > 0 else { throw unavailable }
        window.endEditing(true)
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(window.screen.scale, 2)
        format.opaque = true
        var complete = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            complete = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard complete, let data = image.pngData() else { throw unavailable }
        return data
        #else
        guard #available(macOS 14.4, *) else {
            throw EngramError.unsupported("Screenshot export requires macOS 14.4 or later. The rest of Engram still works on macOS 14.")
        }
        guard let window = probe?.window else { throw unavailable }
        // currentProcess exposes only content this process can capture without
        // TCC consent. Never enumerate or capture another app or a whole display.
        let content = try await SCShareableContent.currentProcess
        guard let target = content.windows.first(where: {
            $0.windowID == CGWindowID(window.windowNumber) &&
            $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
        }) else { throw unavailable }
        let filter = SCContentFilter(desktopIndependentWindow: target)
        let config = SCStreamConfiguration()
        let scale = min(window.backingScaleFactor, 2)
        config.width = max(1, Int(filter.contentRect.width * scale))
        config.height = max(1, Int(filter.contentRect.height * scale))
        config.showsCursor = false
        config.includeChildWindows = true
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw unavailable }
        return data
        #endif
    }

    /// Main content only, not a sidebar or an individual text editor.
    /// Re-resolves after each layout because SwiftUI may replace native scroll views.
    func scrollToTop() { scroll(toTop: true) }
    @discardableResult func scrollForward() -> Bool { scroll(toTop: false) }

    @discardableResult private func scroll(toTop: Bool) -> Bool {
        #if os(iOS)
        guard let window else { return false }
        var controller = window.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        guard let root = controller?.view else { return false }
        let candidates = descendants(root).compactMap { $0 as? UIScrollView }.filter {
            !$0.isHidden && $0.alpha > 0 && !($0 is UITextView) &&
            $0.bounds.height > 150 && $0.bounds.width > root.bounds.width * 0.4 &&
            $0.convert($0.bounds, to: root).intersects(root.bounds) &&
            $0.contentSize.height + $0.adjustedContentInset.top + $0.adjustedContentInset.bottom > $0.bounds.height + 2
        }
        guard let view = candidates.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else { return false }
        let top = -view.adjustedContentInset.top
        let bottom = max(top, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
        let stride = max(100, (view.bounds.height - view.adjustedContentInset.top - view.adjustedContentInset.bottom) * 0.75)
        let y = toTop ? top : min(bottom, view.contentOffset.y + stride)
        guard abs(y - view.contentOffset.y) > 1 else { return false }
        view.setContentOffset(CGPoint(x: view.contentOffset.x, y: y), animated: false)
        return true
        #else
        guard let root = window?.contentView else { return false }
        let candidates = descendants(root).compactMap { $0 as? NSScrollView }.filter {
            !$0.isHiddenOrHasHiddenAncestor && !($0.documentView is NSTextView) &&
            $0.bounds.height > 150 && $0.bounds.width > root.bounds.width * 0.4 &&
            $0.convert($0.bounds, to: root).intersects(root.bounds) &&
            ($0.documentView?.bounds.height ?? 0) > $0.contentView.bounds.height + 2
        }
        guard let view = candidates.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }),
              let document = view.documentView else { return false }
        let clip = view.contentView
        let top = -view.contentInsets.top
        let bottom = max(top, document.bounds.height - clip.bounds.height + view.contentInsets.bottom)
        let stride = max(100, clip.bounds.height * 0.75)
        let y: CGFloat
        if document.isFlipped { y = toTop ? top : min(bottom, clip.bounds.minY + stride) }
        else { y = toTop ? bottom : max(top, clip.bounds.minY - stride) }
        guard abs(y - clip.bounds.minY) > 1 else { return false }
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        view.reflectScrolledClipView(clip)
        return true
        #endif
    }

    private var unavailable: EngramError { .invalid("The app window could not be captured. Keep Engram open and try again.") }

    #if os(iOS)
    private func descendants(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap { descendants($0) } }
    #else
    private func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap { descendants($0) } }
    #endif
}

#if os(iOS)
struct ScreenshotWindowProbe: UIViewRepresentable {
    let capture: NativeScreenCapture
    func makeUIView(context: Context) -> UIView {
        let view = UIView(); view.isUserInteractionEnabled = false; capture.probe = view; return view
    }
    func updateUIView(_ view: UIView, context: Context) { capture.probe = view }
}
#else
struct ScreenshotWindowProbe: NSViewRepresentable {
    let capture: NativeScreenCapture
    func makeNSView(context: Context) -> NSView { let view = NSView(); capture.probe = view; return view }
    func updateNSView(_ view: NSView, context: Context) { capture.probe = view }
}
#endif
