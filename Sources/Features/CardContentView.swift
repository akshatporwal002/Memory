import SwiftUI
import LearningCore
import DesignSystem
import ImageIO
import AVFAudio
import Combine

/// Native, non-executing rendering of the SafeCardMarkup subset. All media comes from
/// supplied library bytes: there is no URL loader, HTML web view, or filesystem fallback.
public struct CardContentView: View {
    public let text: String
    public let media: [MediaFile]
    public let ink: Color?
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    public init(text: String, media: [MediaFile] = [], ink: Color? = nil) { self.text = text; self.media = media; self.ink = ink }
    public var body: some View {
        let document = SafeCardMarkup.inspect(text)
        VStack(alignment: .leading, spacing: EngramSpacing.regular) {
            if document.isSupported {
                ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let runs):
                        formattedText(runs)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(5)
                    case .image(let name, let alternative):
                        LocalCardImage(name: name, alternative: alternative, data: media.first { $0.name == name }?.data)
                    case .audio(let name):
                        LocalCardAudio(name: name, data: media.first { $0.name == name }?.data)
                    }
                }
            } else {
                Label("This card needs supported formatting", systemImage: "exclamationmark.triangle")
                    .font(theme.font(.metadata))
                Text(document.findings.joined(separator: "\n"))
                    .font(theme.font(.metadata))
                    .foregroundStyle(theme.palette(for: colorScheme).secondaryText)
                // Preserve visible evidence for authored drafts; unsupported imports are blocked
                // at inspection. A verbatim Text never interprets HTML or Markdown links.
                Text(verbatim: text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(ink ?? theme.palette(for: colorScheme).primaryText)
        .id(text)
    }
    private func formattedText(_ runs: [SafeCardRun]) -> Text {
        runs.reduce(Text(verbatim: "")) { accumulated, run in
            var segment = Text(verbatim: run.text)
            if run.style.contains(.bold) { segment = segment.bold() }
            if run.style.contains(.italic) { segment = segment.italic() }
            if run.style.contains(.underline) { segment = segment.underline() }
            if run.style.contains(.strike) { segment = segment.strikethrough() }
            if run.style.contains(.monospace) { segment = segment.monospaced() }
            return accumulated + segment
        }
    }
}

private struct LocalCardImage: View {
    let name: String
    let alternative: String
    let data: Data?
    @State private var decoded: CGImage?
    @State private var problem: String?
    @Environment(\.engramTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: EngramSpacing.compact) {
            if let decoded {
                Image(decoded, scale: 1, label: Text(alternative.isEmpty ? name : alternative))
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: min(CGFloat(decoded.width), 640))
                    .accessibilityLabel(alternative.isEmpty ? "Image: \(name)" : alternative)
            } else if let problem {
                Label(problem, systemImage: "photo.badge.exclamationmark")
                    .font(theme.font(.metadata))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView("Loading image")
            }
        }
        .onAppear(perform: load)
        .onChange(of: data) { _, _ in load() }
    }
    private func load() {
        decoded = nil; problem = nil
        guard let data else { problem = "Missing image: \(name)"; return }
        guard data.count <= 50 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              ["public.png", "public.jpeg", "com.microsoft.bmp", "public.tiff", "public.heic", "public.heif"].contains(type),
              CGImageSourceGetCount(source) == 1 else {
            problem = "This image is unreadable, animated, or uses an unsupported format: \(name)"; return
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        let width = (properties?[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue ?? 0
        guard width > 0, height > 0, width <= 20_000, height <= 20_000, width * height <= 40_000_000 else {
            problem = "This image exceeds the supported 40-megapixel limit: \(name)"; return
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2_048]
        decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        if decoded == nil { problem = "Could not decode image: \(name)" }
    }
}

private struct LocalCardAudio: View {
    let name: String
    let data: Data?
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var problem: String?
    @Environment(\.engramTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: EngramSpacing.compact) {
            Button(action: togglePlayback) {
                Label(isPlaying ? "Pause audio" : "Play audio", systemImage: isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(EngramButtonStyle(.secondary))
            .disabled(data == nil)
            .accessibilityLabel("\(isPlaying ? "Pause" : "Play") audio: \(name)")
            .accessibilityHint("Plays the audio stored with this card.")
            Text(name).font(theme.font(.metadata)).fixedSize(horizontal: false, vertical: true)
            if data == nil { Text("Missing audio file").font(theme.font(.metadata)) }
            if let problem { Text(problem).font(theme.font(.metadata)).fixedSize(horizontal: false, vertical: true) }
        }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            isPlaying = player?.isPlaying ?? false
        }
        .onDisappear(perform: stopPlayback)
        .onChange(of: data) { _, _ in stopPlayback() }
    }
    private func togglePlayback() {
        guard let data else { return }
        if let player, player.isPlaying { player.pause(); isPlaying = false; return }
        do {
            if player == nil { player = try AVAudioPlayer(data: data) }
            guard let player else { return }
            if player.currentTime >= player.duration { player.currentTime = 0 }
            guard player.prepareToPlay(), player.play() else {
                problem = "This device could not play the audio file."; return
            }
            isPlaying = true; problem = nil
        } catch { problem = "This audio file is damaged or unsupported on this device."; isPlaying = false }
    }
    private func stopPlayback() { player?.stop(); player = nil; isPlaying = false; problem = nil }
}
