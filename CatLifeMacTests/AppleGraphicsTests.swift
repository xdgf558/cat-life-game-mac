#if os(macOS)
import AppKit
import XCTest
@testable import CatLifeMac

@MainActor
final class AppleGraphicsTests: XCTestCase {
    func testRasterizedAssetKeepsAlphaAndAtlasBoundsOnAWorker() async throws {
        let image = try XCTUnwrap(NSImage(named: "cat-expressions"))
        let native = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let raster = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(raster.width, native.width)
        XCTAssertEqual(raster.height, native.height)
        XCTAssertEqual(try alphaBytes(native), try alphaBytes(raster))

        let baseline = try XCTUnwrap(CatAtlasRegistration.extract(cgImage: native, appearance: .orange, clip: .expressions,
            columns: 4, rows: 2))
        let extracted = await Task.detached {
            CatAtlasRegistration.extract(cgImage: raster, appearance: .orange, clip: .expressions, columns: 4, rows: 2)
        }.value
        let independent = try XCTUnwrap(extracted)
        XCTAssertEqual(independent.map(\.bounds), baseline.map(\.bounds))
        XCTAssertEqual(independent.map(\.rect), baseline.map(\.rect))
    }

    private func alphaBytes(_ image: CGImage) throws -> [UInt8] {
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let bitmap = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
    }
}
#endif
