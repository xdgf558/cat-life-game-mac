#if os(macOS)
import AppKit
import CoreGraphics

// Shared SpriteKit artwork uses native AppKit images and colors on macOS.
typealias UIImage = NSImage
typealias UIColor = NSColor

extension NSImage {
    @MainActor
    var cgImage: CGImage? {
        guard let source = cgImage(forProposedRect: nil, context: nil, hints: nil),
              let bitmap = CGContext(data: nil, width: source.width, height: source.height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        // Asset-catalog providers may decode lazily through AppKit; detach only an independent bitmap.
        bitmap.setBlendMode(.copy)
        bitmap.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        return bitmap.makeImage()
    }
}

@MainActor
final class UIGraphicsImageRenderer {
    struct Context { let cgContext: CGContext }
    private let size: CGSize
    init(size: CGSize) { self.size = size }
    func image(actions: (Context) -> Void) -> NSImage {
        let width = max(1, Int(ceil(size.width))), height = max(1, Int(ceil(size.height)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return NSImage(size: size)
        }
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        actions(Context(cgContext: context))
        guard let image = context.makeImage() else { return NSImage(size: size) }
        return NSImage(cgImage: image, size: size)
    }
}
#endif
