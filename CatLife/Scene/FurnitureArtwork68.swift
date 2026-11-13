import SpriteKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import CatGameCore

/// Cropped render textures keep one physical scale across all views and facings.
@MainActor
enum FurnitureArtwork68 {
    struct PixelPoint: Decodable, Sendable {
        let x: CGFloat
        let y: CGFloat
        var point: CGPoint { CGPoint(x: x, y: y) }
    }

    struct PixelSize: Decodable, Sendable {
        let width: CGFloat
        let height: CGFloat
        var size: CGSize { CGSize(width: width, height: height) }
    }

    struct PixelBounds: Decodable, Sendable {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        var size: CGSize { CGSize(width: width, height: height) }
    }

    struct ModelDimensions: Decodable, Sendable {
        let width: CGFloat
        let height: CGFloat
        let depth: CGFloat
    }

    struct Record: Decodable, Sendable {
        let assetName: String
        let sourceAssetName: String
        let kind: String
        let state: String
        let view: String
        let facing: String
        let yawDegrees: CGFloat
        let canvasSize: PixelSize
        let alphaBounds: PixelBounds
        let anchorPixel: PixelPoint
        let anchorKind: String
        let actualModelDimensions: ModelDimensions
        let surfacePixels: [String: PixelPoint]
        let wallSurfaceYawDegrees: CGFloat?
        let modelYawDegrees: CGFloat?

        var isValid: Bool {
            let b = alphaBounds
            return !assetName.isEmpty && canvasSize.width > 0 && canvasSize.height > 0
                && b.x >= 0 && b.y >= 0 && b.width > 0 && b.height > 0
                && b.x + b.width <= canvasSize.width && b.y + b.height <= canvasSize.height
                && anchorPixel.x.isFinite && anchorPixel.y.isFinite
                && surfacePixels.values.allSatisfy { $0.x.isFinite && $0.y.isFinite }
        }
    }

    @MainActor
    struct Variant {
        let record: Record
        let referenceFrontAlphaWidth: CGFloat

        var assetName: String { record.assetName }
        var croppedSize: CGSize { record.alphaBounds.size }
        var rebasedAnchorPixel: CGPoint {
            CGPoint(x: record.anchorPixel.x - record.alphaBounds.x,
                    y: record.anchorPixel.y - record.alphaBounds.y)
        }
        var anchorPoint: CGPoint {
            CGPoint(x: rebasedAnchorPixel.x / croppedSize.width,
                    y: 1 - rebasedAnchorPixel.y / croppedSize.height)
        }
        var texture: SKTexture { FurnitureArtwork68.texture(for: self) }

        func size(referenceWidth: CGFloat) -> CGSize {
            guard referenceWidth.isFinite, referenceWidth > 0 else { return .zero }
            let scale = referenceWidth / referenceFrontAlphaWidth
            return CGSize(width: croppedSize.width * scale, height: croppedSize.height * scale)
        }

        /// Pixel contacts become SpriteKit offsets from the actual floor/mount anchor.
        func surfaceOffset(_ name: String, referenceWidth: CGFloat) -> CGPoint? {
            guard referenceWidth.isFinite, referenceWidth > 0,
                  let point = record.surfacePixels[name] else { return nil }
            let scale = referenceWidth / referenceFrontAlphaWidth
            return CGPoint(x: (point.x - record.anchorPixel.x) * scale,
                           y: (record.anchorPixel.y - point.y) * scale)
        }
    }

    private struct Manifest: Decodable {
        let formatVersion: Int
        let assetCount: Int
        let assets: [Record]
    }

    static let records: [String: Record] = {
        guard let data = NSDataAsset(name: "FurnitureArtwork68")?.data,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.formatVersion == 1, manifest.assetCount == 105,
              manifest.assets.count == manifest.assetCount,
              Set(manifest.assets.map(\.assetName)).count == manifest.assetCount,
              manifest.assets.allSatisfy(\.isValid) else { return [:] }
        return Dictionary(uniqueKeysWithValues: manifest.assets.map { ($0.assetName, $0) })
    }()

    private static let asymmetric: Set<FurnitureKind> = [.cabinet, .bookcase, .catTree, .rattanChair]
    private static let textures: NSCache<NSString, SKTexture> = {
        let cache = NSCache<NSString, SKTexture>()
        cache.totalCostLimit = 32 * 1_024 * 1_024
        cache.countLimit = 48
        return cache
    }()

    static func assetName(for item: FurnitureItem, angle: RoomViewAngle = .front,
                          placement: FurniturePlacement? = nil) -> String {
        variant(for: item, angle: angle, placement: placement)?.assetName
            ?? FurnitureCatalog.metadata(for: item.kind).assetName
    }

    static func variant(for item: FurnitureItem, angle: RoomViewAngle = .front,
                        placement: FurniturePlacement? = nil) -> Variant? {
        let base = FurnitureCatalog.metadata(for: item.kind).assetName
        let facing: String
        if !item.kind.supportsRotation {
            facing = placement.map { $0.position.x < 0.47 ? "left" : "right" } ?? "front"
        } else {
            facing = asymmetric.contains(item.kind) ? item.orientation.rawValue : "front"
        }
        return variant(base: base, view: viewName(angle), facing: facing)
    }

    static func bowlVariant(hasFood: Bool, angle: RoomViewAngle = .front) -> Variant? {
        variant(base: hasFood ? "bowl-full" : "bowl-empty", view: viewName(angle), facing: "front")
    }

    private static func viewName(_ angle: RoomViewAngle) -> String {
        switch angle {
        case .left: "left"
        case .front: "front"
        case .right: "right"
        }
    }

    private static func variant(base: String, view: String, facing: String) -> Variant? {
        guard let record = records["\(base)-\(view)-\(facing)"],
              let reference = records["\(base)-front-front"], reference.alphaBounds.width > 0 else { return nil }
        return Variant(record: record, referenceFrontAlphaWidth: reference.alphaBounds.width)
    }

    private static func texture(for variant: Variant) -> SKTexture {
        let key = variant.assetName as NSString
        if let existing = textures.object(forKey: key) { return existing }
        let texture = SKTexture(imageNamed: variant.assetName)
        texture.filteringMode = .linear
        let cost = Int(variant.croppedSize.width * variant.croppedSize.height * 4)
        textures.setObject(texture, forKey: key, cost: cost)
        return texture
    }
}
