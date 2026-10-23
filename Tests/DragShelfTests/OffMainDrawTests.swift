import AppKit
import Testing
@testable import DragShelf

/// Sum of alpha over the image rendered at 1x; 0 = drew nothing.
private nonisolated func alphaSum(_ image: NSImage) -> Int {
    var rect = NSRect(origin: .zero, size: image.size)
    guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
          let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
    else { return 0 }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    guard let data = ctx.data else { return 0 }
    let bytes = data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * cg.height)
    return (0..<ctx.bytesPerRow * cg.height).reduce(0) { $0 + Int(bytes[$1]) }
}

/// AppKit may call `NSImage` drawing handlers on any thread: drawing off main must not trap.
@Test func imagesDrawOffMain() async {
    let sums = await withCheckedContinuation { (done: CheckedContinuation<[Int], Never>) in
        DispatchQueue.global().async {
            done.resume(returning: [alphaSum(MenuBarIcon.make()), alphaSum(VisualEffectBackground.mask(radius: 22))])
        }
    }
    #expect(sums.allSatisfy { $0 > 0 })
}
