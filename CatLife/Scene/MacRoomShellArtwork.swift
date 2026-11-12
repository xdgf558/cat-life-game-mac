#if os(macOS)
import SpriteKit
import AppKit
import CatGameCore

/// Existing material/window assets are warped over one cutaway room, never a screenshot of the prototype.
@MainActor
final class MacRoomShellArtwork: SKNode {
    private let wood = SKTexture(imageNamed: "room-floor-wood")
    private let plaster = SKTexture(imageNamed: "room-wall-plaster")
    private let windowArt = SKTexture(imageNamed: "room-window-arched")
    private(set) var fixedFrames: [MacRoomStructure: CGRect] = [:]
    private(set) var fixedPolygons: [MacRoomStructure: [CGPoint]] = [:]
    private(set) var contentBounds = CGRect.zero

    override init() { super.init(); name = "mac-dollhouse-shell" }
    required init?(coder: NSCoder) { fatalError("Created in code") }

    func configure(_ model: MacRoomProjection, floor: HomeFloor, level: Int, isDaylight: Bool) {
        removeAllChildren(); fixedFrames.removeAll(); fixedPolygons.removeAll()
        contentBounds = model.contentBounds
        let upper = floor == .upper
        let wallpaper = upper ? NSColor(red: 0.93, green: 0.86, blue: 0.96, alpha: 1)
            : NSColor(red: 0.99, green: 0.92, blue: 0.80, alpha: 1)
        let skirt = upper ? NSColor(red: 0.75, green: 0.62, blue: 0.81, alpha: 1)
            : NSColor(red: 0.62, green: 0.76, blue: 0.59, alpha: 1)
        func p(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint { model.projectCell(x: x, height: y, z: z) }
        for layer in 0..<6 {
            let spread = CGFloat(layer) * 0.12
            let points = (0..<48).map { index in
                let a = CGFloat(index) * .pi * 2 / 48
                return p(6 + cos(a) * (6.3 + spread), -0.5, 3.5 + sin(a) * (3.7 + spread))
            }
            polygon(points, color: NSColor.brown.withAlphaComponent(0.022), z: -90 - CGFloat(layer))
        }
        func wall(_ a: CGPoint, _ b: CGPoint, outside: CGPoint) {
            func surface(_ startHeight: CGFloat, _ endHeight: CGFloat, texture: SKTexture, tint: NSColor, z: CGFloat) {
                textured(texture, tint: tint, blend: 0.55, z: z) { u, v in
                    p(a.x + (b.x - a.x) * u, startHeight + (endHeight - startHeight) * v, a.y + (b.y - a.y) * u)
                }
            }
            let length = hypot(b.x - a.x, b.y - a.y), tiles = max(1, Int((length / 4).rounded()))
            for tile in 0..<tiles {
                let t0 = CGFloat(tile) / CGFloat(tiles), t1 = CGFloat(tile + 1) / CGFloat(tiles)
                textured(plaster, tint: wallpaper, blend: 0.55, z: -40) { u, v in
                    let t = t0 + (t1 - t0) * u
                    return p(a.x + (b.x - a.x) * t, 4.6 * v, a.y + (b.y - a.y) * t)
                }
            }
            surface(0, 0.34, texture: wood, tint: skirt, z: -36)
            textured(wood, tint: .white, blend: 0.08, z: -34) { u, v in
                p(a.x + (b.x - a.x) * u + outside.x * v, 4.6, a.y + (b.y - a.y) * u + outside.y * v)
            }
        }
        wall(CGPoint(x: 0, y: 7), CGPoint(x: 12, y: 7), outside: CGPoint(x: 0, y: 0.3))
        if model.angle != .left {
            wall(CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 7), outside: CGPoint(x: -0.3, y: 0))
            textured(wood, tint: wallpaper, blend: 0.2, z: -10) { u, v in p(-0.3 * u, -0.4 + 5 * v, 0) }
        }
        if model.angle != .right {
            wall(CGPoint(x: 12, y: 7), CGPoint(x: 12, y: 0), outside: CGPoint(x: 0.3, y: 0))
            textured(wood, tint: wallpaper, blend: 0.2, z: -10) { u, v in p(12 + 0.3 * u, -0.4 + 5 * v, 0) }
        }
        textured(wood, tint: .black, blend: 0.18, z: -18) { u, v in p(12 * u, -0.4 * v, 0) }
        textured(wood, tint: .black, blend: 0.24, z: -19) { u, v in p(0, -0.4 * v, 7 * u) }
        textured(wood, tint: .black, blend: 0.24, z: -19) { u, v in p(12, -0.4 * v, 7 * u) }
        // One 1024px tile holds 12 planks; tiling it 2×2 keeps each plank about half a cell wide.
        for column in 0..<2 { for row in 0..<2 {
            let x0 = CGFloat(column) * 6, z0 = CGFloat(row) * 3.5
            textured(wood, tint: upper ? NSColor(red: 0.82, green: 0.69, blue: 0.56, alpha: 1) : .white,
                     blend: upper ? 0.18 : 0, z: -15) { u, v in p(x0 + 6 * u, 0, z0 + 3.5 * v) }
        } }
        for x: CGFloat in [2.2, 6.6] {
            textured(windowArt, tint: .white, blend: 0, z: -30) { u, v in p(x - 0.9 + 1.8 * u, 1.5 + 2.4 * v, 6.99) }
            children.last?.name = "mac-room-window"
        }
        if isDaylight {
            polygon([p(1.2, 0.012, 6.8), p(3.2, 0.012, 6.8), p(4.4, 0.012, 3.6), p(1.8, 0.012, 3.6)],
                    color: NSColor(red: 1, green: 0.95, blue: 0.75, alpha: 0.33), z: -13)
        }
        if model.angle != .left { installDoor(model) }
        installStairs(model, upper: upper, unlocked: level >= 6)
        if !isDaylight {
            polygon([p(1.2, 0.014, 6.8), p(3.2, 0.014, 6.8), p(4.4, 0.014, 3.6), p(1.8, 0.014, 3.6)],
                    color: NSColor(red: 1, green: 0.72, blue: 0.36, alpha: 0.12), z: -13)
            for case let sprite as SKSpriteNode in children {
                if sprite.name == "mac-room-window" {
                    sprite.color = NSColor(red: 1, green: 0.74, blue: 0.43, alpha: 1)
                    sprite.colorBlendFactor = 0.3
                    continue
                }
                sprite.color = sprite.color.blended(withFraction: 0.18, of: NSColor(red: 0.23, green: 0.25, blue: 0.39, alpha: 1)) ?? sprite.color
                sprite.colorBlendFactor = max(0.28, sprite.colorBlendFactor)
            }
        }
    }

    private func installDoor(_ model: MacRoomProjection) {
        func p(_ z: CGFloat, _ height: CGFloat, _ offset: CGFloat = 0.025) -> CGPoint {
            model.projectCell(x: offset, height: height, z: z)
        }
        textured(wood, tint: .white, blend: 0.03, z: -29) { u, v in p(1.35 + 1.7 * u, 3.3 * v) }
        let mint = NSColor(red: 0.55, green: 0.77, blue: 0.68, alpha: 1)
        textured(wood, tint: mint, blend: 0.8, z: -28) { u, v in p(1.48 + 1.44 * u, 0.04 + 3.10 * v, 0.035) }
        textured(plaster, tint: NSColor.white.withAlphaComponent(0.8), blend: 0.6, z: -27) { u, v in
            p(1.67 + 1.05 * u, 1.7 + 1.05 * v, 0.04)
        }
        let knob = (0..<20).map { index in
            let a = CGFloat(index) * .pi * 2 / 20
            return p(1.68 + cos(a) * 0.08, 1.45 + sin(a) * 0.08, 0.065)
        }
        polygon(knob, color: NSColor(red: 0.87, green: 0.65, blue: 0.26, alpha: 1), z: -26)
        let hit = [p(1.35, 0), p(3.05, 0), p(3.05, 3.3), p(1.35, 3.3)]
        fixedPolygons[.door] = hit; fixedFrames[.door] = MacRoomProjection.bounds(hit)
    }

    private func installStairs(_ model: MacRoomProjection, upper: Bool, unlocked: Bool) {
        func p(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint { model.projectCell(x: x, height: y, z: z) }
        let depth = 10_000 - p(11, 0, 5.5).y
        if upper {
            polygon([p(10, 0.015, 4), p(12, 0.015, 4), p(12, 0.015, 7), p(10, 0.015, 7)],
                    color: NSColor(red: 0.32, green: 0.23, blue: 0.16, alpha: 1), z: depth)
            for index in 0..<6 {
                let z = 4 + CGFloat(index) * 0.5
                textured(wood, tint: .black, blend: 0.12 + CGFloat(index) * 0.04, z: depth + 0.1) { u, v in
                    p(10.12 + 1.76 * u, -0.12 - CGFloat(index) * 0.08, z + 0.45 * v)
                }
            }
        } else {
            for index in 0..<6 {
                let z = 4 + CGFloat(index) * 0.5, height = CGFloat(index + 1) * 0.42
                let layer = 10_000 - p(11, 0, z + 0.25).y
                textured(wood, tint: .black, blend: 0.18, z: layer) { u, v in p(10.1 + 1.8 * u, height * v, z) }
                textured(wood, tint: .white, blend: 0.08, z: layer + 0.1) { u, v in p(10.1 + 1.8 * u, height, z + 0.5 * v) }
                let side: CGFloat = model.angle == .left ? 11.9 : 10.1
                textured(wood, tint: .black, blend: 0.28, z: layer + 0.05) { u, v in p(side, height * v, z + 0.5 * u) }
            }
            if !unlocked {
                textured(wood, tint: NSColor(red: 0.68, green: 0.53, blue: 0.36, alpha: 1), blend: 0.35, z: depth + 5) { u, v in
                    p(10 + 2 * u, 0.75 + 0.23 * v, 3.98)
                }
            }
        }
        let hit = [p(10, 0, 4), p(12, 0, 4), p(12, upper ? 0 : 2.6, 7), p(10, upper ? 0 : 2.6, 7)]
        fixedFrames[.stairs] = MacRoomProjection.bounds(hit)
        fixedPolygons[.stairs] = hit
    }

    private func polygon(_ points: [CGPoint], color: NSColor, z: CGFloat) {
        let path = CGMutablePath(); path.addLines(between: points); path.closeSubpath()
        let node = SKShapeNode(path: path); node.fillColor = color; node.strokeColor = .clear; node.zPosition = z
        addChild(node)
    }
    private func textured(_ texture: SKTexture, tint: NSColor, blend: CGFloat, z: CGFloat,
                          project: (CGFloat, CGFloat) -> CGPoint) {
        let corners = [project(0, 0), project(1, 0), project(0, 1), project(1, 1)]
        let bounds = MacRoomProjection.bounds(corners)
        guard bounds.width > 0.0001, bounds.height > 0.0001 else { return }
        let node = SKSpriteNode(texture: texture)
        node.position = CGPoint(x: bounds.midX, y: bounds.midY); node.size = bounds.size; node.zPosition = z
        node.color = tint; node.colorBlendFactor = blend
        let count = 4
        var source: [SIMD2<Float>] = [], destination: [SIMD2<Float>] = []
        for row in 0...count { for column in 0...count {
            let u = CGFloat(column) / CGFloat(count), v = CGFloat(row) / CGFloat(count), p = project(u, v)
            source.append(SIMD2(Float(u), Float(v)))
            destination.append(SIMD2(Float((p.x - bounds.minX) / bounds.width), Float((p.y - bounds.minY) / bounds.height)))
        } }
        node.warpGeometry = SKWarpGeometryGrid(columns: count, rows: count, sourcePositions: source, destinationPositions: destination)
        addChild(node)
    }
}
#endif
