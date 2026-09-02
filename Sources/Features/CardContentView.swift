import SwiftUI
import LearningCore

/// Presentation seam for supported imported HTML/media; no template code is executed here.
public struct CardContentView: View {
    public let text: String
    public let media: [MediaFile]
    public init(text: String, media: [MediaFile] = []) { self.text = text; self.media = media }
    public var body: some View { Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).lineSpacing(5) }
}
