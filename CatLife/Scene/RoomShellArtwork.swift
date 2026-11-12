import SpriteKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import CatGameCore

/// A complete cutaway shell around the existing walkable floor, in projected world coordinates.
@MainActor
final class RoomShellArtwork: SKNode {
    private(set) var contentBounds = CGRect.zero
    private(set) var renderedFloor: HomeFloor = .ground
    private(set) var windowGroundAnchor: CGPoint?
    private var shellBounds = CGRect.null
    private let frontArtwork = RoomFrontArtwork()
    #if os(macOS)
    let desktopArtwork = MacRoomShellArtwork()
    var desktopDaylight = true
    var desktopLevel = 1
    #endif
    private lazy var woodTexture = UIImage(named: "room-floor-wood").map { SKTexture(image: $0) }
    private lazy var plasterTexture = UIImage(named: "room-wall-plaster").map { SKTexture(image: $0) }
    private lazy var windowTexture = UIImage(named: "room-window-arched").map { SKTexture(image: $0) }

    private let cream = UIColor(red: 0.98, green: 0.89, blue: 0.71, alpha: 1)
    private let wood = UIColor(red: 0.87, green: 0.62, blue: 0.32, alpha: 1)
    private let sage = UIColor(red: 0.62, green: 0.69, blue: 0.47, alpha: 1)

    override init() {
        super.init()
        name = "room-shell"
    }

    required init?(coder aDecoder: NSCoder) { fatalError("RoomShellArtwork is created in code") }

    func configure(projection: RoomViewProjection, floorPolygon: [CGPoint], worldSize: CGSize,
                   floor homeFloor: HomeFloor = .ground) {
        removeAllChildren()
        shellBounds = .null
        contentBounds = .zero
        renderedFloor = homeFloor
        windowGroundAnchor = nil
        guard floorPolygon.count >= 3, worldSize.width.isFinite, worldSize.height.isFinite,
              worldSize.width > 0, worldSize.height > 0,
              floorPolygon.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return }
        #if os(macOS)
        if let model = projection.macRoom {
            desktopArtwork.configure(model, floor: homeFloor, level: desktopLevel, isDaylight: desktopDaylight)
            addChild(desktopArtwork)
            contentBounds = desktopArtwork.contentBounds
            windowGroundAnchor = model.logicalPoint(cell: CGPoint(x: 2.2, y: 7))
            return
        }
        #endif
        if projection.frontFloor != nil {
            frontArtwork.configure(projection: projection, floor: homeFloor)
            addChild(frontArtwork)
            contentBounds = frontArtwork.contentBounds
            windowGroundAnchor = frontArtwork.windowGroundAnchor
            return
        }
        let outline = floorPolygon.map(projection.project)
        let winding = signedArea(outline)
        guard abs(winding) > 0.001 else { return }
        let unit = min(worldSize.width, worldSize.height)
        let wallHeight = projection.wallHeight
        let rimHeight = max(7, unit * 0.025)
        let floorPath = path(outline)
        let footprint = floorPath.boundingBoxOfPath
        let shadow = SKShapeNode(ellipseOf: CGSize(width: footprint.width * 0.94, height: max(12, footprint.height * 0.36)))
        shadow.name = "room-shell-ground-shadow"
        shadow.position = CGPoint(x: footprint.midX, y: footprint.minY + footprint.height * 0.26 - rimHeight)
        shadow.fillColor = UIColor(red: 0.34, green: 0.23, blue: 0.12, alpha: 0.13)
        shadow.strokeColor = .clear
        shadow.glowWidth = max(3, unit * 0.02)
        shadow.zPosition = -60
        addChild(shadow)

        for index in outline.indices {
            let a = outline[index], b = outline[(index + 1) % outline.count]
            let dx = b.x - a.x
            let isFar = (winding > 0 ? -dx : dx) > 0.001
            if isFar {
                let topA = lifted(a, by: wallHeight), topB = lifted(b, by: wallHeight)
                let wall = shape([a, b, topB, topA], fill: cream, stroke: cream.withAlphaComponent(0.9), z: -40)
                wall.name = "room-shell-far-wall"
                wall.fillTexture = plasterTexture
                if homeFloor == .upper {
                    wall.fillColor = UIColor(red: 0.87, green: 0.79, blue: 0.93, alpha: 1)
                    addUpperWallStripes(from: a, to: b, height: wallHeight, unit: unit)
                } else if b.x < a.x {
                    wall.fillColor = UIColor(red: 0.96, green: 0.86, blue: 0.67, alpha: 1)
                }
                shape([topA, topB, lifted(topB, by: rimHeight * 0.55), lifted(topA, by: rimHeight * 0.55)],
                      fill: sage, stroke: sage, z: -38)
                shape([a, b, lifted(b, by: rimHeight * 0.65), lifted(a, by: rimHeight * 0.65)],
                      fill: sage.withAlphaComponent(0.8), stroke: .clear, z: -37)
                line([topA, topB], color: UIColor.white.withAlphaComponent(0.45), width: max(1, unit * 0.004), z: -36)
                line([a, topA], color: UIColor(red: 0.75, green: 0.62, blue: 0.43, alpha: 0.23), width: 1.5, z: -36)
                let shadow = line([a, b], color: UIColor.brown.withAlphaComponent(0.13),
                                  width: max(2, unit * 0.014), z: -11)
                shadow.glowWidth = max(2, unit * 0.010)
            }
            let rim = shape([a, b, lifted(b, by: -rimHeight), lifted(a, by: -rimHeight)],
                            fill: UIColor(red: 0.69, green: 0.45, blue: 0.25, alpha: 1), stroke: .clear, z: -20)
            rim.name = "room-shell-wood-edge"
        }

        let floor = SKShapeNode(path: floorPath)
        floor.name = "room-shell-floor"
        floor.fillColor = homeFloor == .upper ? UIColor(red: 0.76, green: 0.54, blue: 0.31, alpha: 1) : wood
        floor.strokeColor = UIColor(red: 0.75, green: 0.50, blue: 0.27, alpha: 1)
        floor.lineWidth = 1
        floor.zPosition = -15
        addChild(floor)
        include(floorPath.boundingBoxOfPath)
        if let woodTexture {
            let rootThree = sqrt(CGFloat(3))
            let ground = floorPolygon.map { CGPoint(x: $0.x / rootThree + $0.y, y: -$0.x / rootThree + $0.y) }
            let minU = ground.map(\.x).min()!, maxU = ground.map(\.x).max()!
            let minV = ground.map(\.y).min()!, maxV = ground.map(\.y).max()!
            func corner(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
                projection.project(CGPoint(x: (u - v) * rootThree / 2, y: (u + v) / 2))
            }
            let grain = SKCropNode()
            let mask = SKShapeNode(path: floorPath)
            mask.fillColor = .white; mask.strokeColor = .clear
            grain.maskNode = mask; grain.zPosition = -14
            let texture = texturedPlane(woodTexture, corners: [corner(minU, maxV), corner(minU, minV),
                                                               corner(maxU, maxV), corner(maxU, minV)])
            texture.name = "room-shell-floor-texture"
            texture.color = .black
            texture.colorBlendFactor = homeFloor == .upper ? 0.12 : 0
            grain.addChild(texture)
            addChild(grain)
        }
        addFloorboards(floorPolygon, projection: projection, unit: unit)

        for index in outline.indices {
            let a = outline[index], b = outline[(index + 1) % outline.count]
            line([a, b], color: UIColor(red: 0.98, green: 0.81, blue: 0.55, alpha: 1),
                 width: max(2, unit * 0.006), z: -8)
            let previous = outline[(index + outline.count - 1) % outline.count]
            if cross(subtract(a, previous), subtract(b, a)) * winding < 0 {
                let height = rimHeight * 1.5
                let ledge = shape([previous, a, lifted(a, by: height), lifted(previous, by: height)],
                                  fill: cream, stroke: .clear, z: -9)
                ledge.name = "room-shell-window-bay"
                line([lifted(previous, by: height), lifted(a, by: height)], color: sage,
                     width: max(2, unit * 0.008), z: -8)
            }
        }
        let wallEdges = floorPolygon.indices.compactMap { index -> (CGPoint, CGPoint)? in
            let a = floorPolygon[index], b = floorPolygon[(index + 1) % floorPolygon.count]
            return b.x > a.x ? (a, b) : nil
        }
        func length(_ edge: (CGPoint, CGPoint)) -> CGFloat {
            hypot(edge.1.x - edge.0.x, edge.1.y - edge.0.y)
        }
        let leftEdges = wallEdges.filter { ($0.0.x + $0.1.x) / 2 < worldSize.width * 0.48 }
        let windowEdges = homeFloor == .ground ? leftEdges : wallEdges.filter { edge in
            [edge.0, edge.1].allSatisfy { abs($0.y - projection.wallGround(at: $0.x).y) < 0.001 }
        }
        if var windowEdge = windowEdges.max(by: { length($0) < length($1) }) {
            if homeFloor == .upper, let sourceWidth = leftEdges.map(length).max() {
                // Keep the original window width when moving it to the longer opposite wall.
                let fraction = min(1, sourceWidth / length(windowEdge))
                let start = (1 - fraction) / 2
                let a = windowEdge.0, delta = subtract(windowEdge.1, a)
                windowEdge = (CGPoint(x: a.x + delta.x * start, y: a.y + delta.y * start),
                              CGPoint(x: a.x + delta.x * (start + fraction), y: a.y + delta.y * (start + fraction)))
            }
            // Reuse the opposite existing wall edge, without reflecting any physical room coordinates.
            windowGroundAnchor = CGPoint(x: windowEdge.0.x + (windowEdge.1.x - windowEdge.0.x) * 0.49,
                                         y: windowEdge.0.y + (windowEdge.1.y - windowEdge.0.y) * 0.49)
            addWindow(from: projection.project(windowEdge.0), to: projection.project(windowEdge.1),
                      height: wallHeight, floorPath: floorPath, unit: unit)
        }
        if !shellBounds.isNull { contentBounds = shellBounds.insetBy(dx: -max(2, unit * 0.008), dy: -max(2, unit * 0.008)) }
    }

    private func addUpperWallStripes(from a: CGPoint, to b: CGPoint, height: CGFloat, unit: CGFloat) {
        let wash = shape([a, b, lifted(b, by: height), lifted(a, by: height)],
                         fill: UIColor(red: 0.84, green: 0.79, blue: 0.93, alpha: 0.55), stroke: .clear, z: -39.5)
        wash.name = "room-shell-upper-wallpaper"
        let length = hypot(b.x - a.x, b.y - a.y)
        let count = max(1, Int(ceil(length / max(8, unit * 0.035))))
        func along(_ fraction: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
        }
        for index in 0..<count {
            let start = along(CGFloat(index) / CGFloat(count))
            let end = along((CGFloat(index) + 0.45) / CGFloat(count))
            let stripe = shape([start, end, lifted(end, by: height), lifted(start, by: height)],
                               fill: UIColor.white.withAlphaComponent(0.16), stroke: .clear, z: -39)
            stripe.name = "room-shell-upper-wall-stripe"
        }
    }

    private func addFloorboards(_ polygon: [CGPoint], projection: RoomViewProjection, unit: CGFloat) {
        let rootThree = sqrt(CGFloat(3))
        let ground = polygon.map { CGPoint(x: $0.x / rootThree + $0.y, y: -$0.x / rootThree + $0.y) }
        guard let minU = ground.map(\.x).min(), let maxU = ground.map(\.x).max(),
              let minV = ground.map(\.y).min(), let maxV = ground.map(\.y).max() else { return }
        let step = max(12, unit * 0.043)
        let seams = CGMutablePath()
        func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: (u - v) * rootThree / 2, y: (u + v) / 2)
        }
        func add(_ a: CGPoint, _ b: CGPoint) {
            for segment in clippedSegments(from: a, to: b, polygon: polygon) {
                seams.move(to: projection.project(segment.0))
                seams.addLine(to: projection.project(segment.1))
            }
        }
        var row = 0
        for v in stride(from: floor(minV / step) * step, through: maxV, by: step) {
            add(point(minU - step, v), point(maxU + step, v))
            let spacing = step * 4
            let offset = CGFloat(row % 3) * spacing / 3
            for u in stride(from: floor((minU - offset) / spacing) * spacing + offset, through: maxU, by: spacing) {
                add(point(u, v), point(u, v + step))
            }
            row += 1
        }
        let lines = SKShapeNode(path: seams)
        lines.strokeColor = UIColor(red: 0.60, green: 0.36, blue: 0.17, alpha: 0.24)
        lines.lineWidth = max(0.6, unit * 0.0018)
        lines.zPosition = -12
        addChild(lines)
    }

    private func addWindow(from a: CGPoint, to b: CGPoint, height: CGFloat, floorPath: CGPath, unit: CGFloat) {
        func wall(_ t: CGFloat, _ z: CGFloat) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t + height * z)
        }
        if let windowTexture {
            let window = texturedPlane(windowTexture, corners: [wall(0.14, 0.12), wall(0.84, 0.12),
                                                                wall(0.14, 0.96), wall(0.84, 0.96)])
            window.name = "room-shell-window"
            window.zPosition = -28
            addChild(window)
        } else {
        let glassPath = CGMutablePath()
        glassPath.move(to: wall(0.20, 0.23))
        glassPath.addLine(to: wall(0.76, 0.23))
        glassPath.addLine(to: wall(0.76, 0.62))
        glassPath.addCurve(to: wall(0.48, 0.89), control1: wall(0.76, 0.79), control2: wall(0.63, 0.89))
        glassPath.addCurve(to: wall(0.20, 0.62), control1: wall(0.33, 0.89), control2: wall(0.20, 0.79))
        glassPath.closeSubpath()
        let glass = SKShapeNode(path: glassPath)
        glass.name = "room-shell-window"
        glass.fillColor = UIColor(red: 0.68, green: 0.84, blue: 0.89, alpha: 1)
        glass.strokeColor = UIColor(red: 0.71, green: 0.44, blue: 0.22, alpha: 1)
        glass.lineWidth = max(4, unit * 0.012)
        glass.zPosition = -33
        addChild(glass)

        let sky = SKCropNode()
        let mask = SKShapeNode(path: glassPath)
        mask.fillColor = .white
        mask.strokeColor = .clear
        sky.maskNode = mask
        sky.zPosition = -32
        for (t, z, size) in [(CGFloat(0.35), CGFloat(0.70), CGFloat(0.12)), (0.57, 0.78, 0.09)] {
            let cloud = SKShapeNode(ellipseOf: CGSize(width: unit * size, height: height * 0.05))
            cloud.position = wall(t, z)
            cloud.fillColor = .white.withAlphaComponent(0.78)
            cloud.strokeColor = .clear
            sky.addChild(cloud)
        }
        for (t, z, size) in [(CGFloat(0.24), CGFloat(0.27), CGFloat(0.15)), (0.50, 0.24, 0.18), (0.77, 0.30, 0.15)] {
            let foliage = SKShapeNode(ellipseOf: CGSize(width: unit * size, height: height * 0.30))
            foliage.position = wall(t, z)
            foliage.fillColor = UIColor(red: 0.58, green: 0.70, blue: 0.42, alpha: 0.75)
            foliage.strokeColor = .clear
            sky.addChild(foliage)
        }
        addChild(sky)
        line([wall(0.48, 0.23), wall(0.48, 0.88)], color: wood, width: max(3, unit * 0.009), z: -30)
        line([wall(0.20, 0.54), wall(0.76, 0.54)], color: wood, width: max(3, unit * 0.009), z: -30)
        shape([wall(0.16, 0.23), wall(0.80, 0.23), wall(0.80, 0.17), wall(0.16, 0.17)],
              fill: UIColor(red: 0.98, green: 0.84, blue: 0.59, alpha: 1), stroke: .clear, z: -29)
        }

        let sunlight = SKCropNode()
        let floorMask = SKShapeNode(path: floorPath)
        floorMask.fillColor = .white
        floorMask.strokeColor = .clear
        sunlight.maskNode = floorMask
        sunlight.zPosition = -10
        let drop = CGPoint(x: unit * 0.20, y: -unit * 0.44)
        let nearA = wall(0.24, 0), nearB = wall(0.71, 0)
        let patch = SKShapeNode(path: path([nearA, nearB,
            CGPoint(x: nearB.x + drop.x, y: nearB.y + drop.y),
            CGPoint(x: nearA.x + drop.x, y: nearA.y + drop.y)]))
        patch.fillColor = UIColor(red: 1, green: 0.96, blue: 0.72, alpha: 0.24)
        patch.strokeColor = .clear
        sunlight.addChild(patch)
        addChild(sunlight)
    }

    @discardableResult
    private func shape(_ points: [CGPoint], fill: UIColor, stroke: UIColor, z: CGFloat) -> SKShapeNode {
        let node = SKShapeNode(path: path(points))
        node.fillColor = fill
        node.strokeColor = stroke
        node.lineWidth = 1
        node.zPosition = z
        addChild(node)
        include(node.path!.boundingBoxOfPath)
        return node
    }

    @discardableResult
    private func line(_ points: [CGPoint], color: UIColor, width: CGFloat, z: CGFloat) -> SKShapeNode {
        let node = SKShapeNode(path: path(points, closed: false))
        node.strokeColor = color
        node.lineWidth = width
        node.lineCap = .round
        node.zPosition = z
        addChild(node)
        include(node.path!.boundingBoxOfPath.insetBy(dx: -width / 2, dy: -width / 2))
        return node
    }

    private func texturedPlane(_ texture: SKTexture, corners: [CGPoint]) -> SKSpriteNode {
        let minX = corners.map(\.x).min()!, maxX = corners.map(\.x).max()!
        let minY = corners.map(\.y).min()!, maxY = corners.map(\.y).max()!
        let box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let node = SKSpriteNode(texture: texture)
        node.size = box.size
        node.position = CGPoint(x: box.midX, y: box.midY)
        let unit: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)]
        let destination = corners.map { SIMD2(Float(($0.x - box.minX) / max(1, box.width)),
                                               Float(($0.y - box.minY) / max(1, box.height))) }
        node.warpGeometry = SKWarpGeometryGrid(columns: 1, rows: 1, sourcePositions: unit, destinationPositions: destination)
        return node
    }

    private func include(_ rect: CGRect) { shellBounds = shellBounds.union(rect) }

    private func path(_ points: [CGPoint], closed: Bool = true) -> CGPath {
        let result = CGMutablePath()
        guard let first = points.first else { return result }
        result.move(to: first)
        for point in points.dropFirst() { result.addLine(to: point) }
        if closed { result.closeSubpath() }
        return result
    }

    private func signedArea(_ polygon: [CGPoint]) -> CGFloat {
        polygon.indices.reduce(0) { $0 + cross(polygon[$1], polygon[($1 + 1) % polygon.count]) } / 2
    }

    private func subtract(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    private func cross(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x * b.y - a.y * b.x }
    private func lifted(_ point: CGPoint, by height: CGFloat) -> CGPoint { CGPoint(x: point.x, y: point.y + height) }

    private func clippedSegments(from a: CGPoint, to b: CGPoint, polygon: [CGPoint]) -> [(CGPoint, CGPoint)] {
        let direction = subtract(b, a)
        var cuts: [CGFloat] = [0, 1]
        for index in polygon.indices {
            let start = polygon[index], edge = subtract(polygon[(index + 1) % polygon.count], start)
            let denominator = cross(direction, edge)
            guard abs(denominator) > 0.00001 else { continue }
            let delta = subtract(start, a)
            let t = cross(delta, edge) / denominator, u = cross(delta, direction) / denominator
            if t > 0, t < 1, u >= 0, u <= 1 { cuts.append(t) }
        }
        cuts.sort()
        let floor = path(polygon)
        func at(_ t: CGFloat) -> CGPoint { CGPoint(x: a.x + direction.x * t, y: a.y + direction.y * t) }
        return zip(cuts, cuts.dropFirst()).compactMap { start, end in
            guard end - start > 0.00001, floor.contains(at((start + end) / 2)) else { return nil }
            return (at(start), at(end))
        }
    }
}
