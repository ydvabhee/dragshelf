import AppKit
import QuickLookThumbnailing
import SwiftUI

/// QuickLook thumbnail for a file; shows the system icon until (or if never) one is available.
struct FileThumbnail: View {
    let url: URL
    @State private var thumbnail: NSImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .scaledToFit()
            .task(id: url) {
                let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 64, height: 64),
                                                            scale: scale, representationTypes: .thumbnail)
                guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return }
                thumbnail = rep.nsImage
            }
    }
}
