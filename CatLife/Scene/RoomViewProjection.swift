import Foundation
import CoreGraphics

enum RoomViewAngle: Int, CaseIterable, Hashable, Sendable {
    case left = -1
    case front = 0
    case right = 1

    var previous: Self { Self(rawValue: rawValue - 1) ?? .right }
    var next: Self { Self(rawValue: rawValue + 1) ?? .left }
    var radians: CGFloat { CGFloat(rawValue) * .pi / 10 }
}

/// Changes presentation only: navigation, actors and saved positions keep their original coordinates.
struct RoomViewProjection: Sendable {
    let worldSize: CGSize
    let angle: RoomViewAngle
    let frontFloor: RoomFrontFloorProjection?
    #if os(macOS)
    var macRoom: MacRoomProjection?
    #endif

    var wallHeight: CGFloat {
        #if os(macOS)
        if let macRoom { return MacRoomProjection.wallCells * macRoom.unit * 0.88 }
        #endif
        if angle == .front, let frontFloor { return frontFloor.destination.height * 0.34 / 0.66 }
        return min(worldSize.width * 0.43, worldSize.height * 0.27)
    }

    init(worldSize: CGSize, angle: RoomViewAngle, frontFloor: RoomFrontFloorProjection? = nil) {
        self.worldSize = worldSize
        self.angle = angle
        self.frontFloor = frontFloor
    }

    func project(_ point: CGPoint) -> CGPoint {
        #if os(macOS)
        if let macRoom { return macRoom.project(point) }
        #endif
        if angle == .front { return frontFloor?.project(point) ?? point }
        let center = CGPoint(x: worldSize.width / 2, y: worldSize.height / 2)
        let offset = vector(CGPoint(x: point.x - center.x, y: point.y - center.y))
        return CGPoint(x: center.x + offset.x, y: center.y + offset.y)
    }

    func unproject(_ point: CGPoint) -> CGPoint {
        #if os(macOS)
        if let macRoom { return macRoom.unproject(point) }
        #endif
        if angle == .front { return frontFloor?.unproject(point) ?? point }
        let center = CGPoint(x: worldSize.width / 2, y: worldSize.height / 2)
        let offset = transform(CGPoint(x: point.x - center.x, y: point.y - center.y), radians: -angle.radians)
        return CGPoint(x: center.x + offset.x, y: center.y + offset.y)
    }

    /// Rectification is piecewise affine, so a local displacement must retain its origin.
    func vector(_ delta: CGPoint, at origin: CGPoint = .zero) -> CGPoint {
        #if os(macOS)
        if let macRoom {
            let a = macRoom.project(origin), b = macRoom.project(CGPoint(x: origin.x + delta.x, y: origin.y + delta.y))
            return CGPoint(x: b.x - a.x, y: b.y - a.y)
        }
        #endif
        if angle == .front, frontFloor != nil {
            let a = project(origin), b = project(CGPoint(x: origin.x + delta.x, y: origin.y + delta.y))
            return CGPoint(x: b.x - a.x, y: b.y - a.y)
        }
        return transform(delta, radians: angle.radians)
    }

    /// Ground depth excludes a sprite's height, so tall furniture still sorts by its feet.
    func projectedDepth(_ point: CGPoint) -> CGFloat { project(point).y }

    /// Wall decorations retain their original wall coordinates; only their displayed height is remapped.
    func wallPoint(_ point: CGPoint) -> CGPoint {
        #if os(macOS)
        if let macRoom {
            let x = (point.x - macRoom.logicalBounds.minX) / macRoom.logicalBounds.width * MacRoomProjection.columns
            return macRoom.wallPoint(x: x, height: (point.y - wallGround(at: point.x).y) / sourceWallHeight * MacRoomProjection.wallCells)
        }
        #endif
        guard sourceWallHeight > 0, wallHeight > 0 else { return project(point) }
        if angle == .front, let frontFloor {
            let ground = wallGround(at: point.x)
            return CGPoint(x: frontFloor.project(ground).x,
                           y: frontFloor.destination.maxY + (point.y - ground.y) * wallHeight / sourceWallHeight)
        }
        let ground = wallGround(at: point.x)
        let projected = project(ground)
        return CGPoint(x: projected.x, y: projected.y + (point.y - ground.y) * wallHeight / sourceWallHeight)
    }

    func unprojectWallPoint(_ point: CGPoint) -> CGPoint {
        #if os(macOS)
        if let macRoom {
            let cell = macRoom.wallCoordinates(projected: point)
            let x = macRoom.logicalBounds.minX + cell.x / MacRoomProjection.columns * macRoom.logicalBounds.width
            return CGPoint(x: x, y: wallGround(at: x).y + cell.y / MacRoomProjection.wallCells * sourceWallHeight)
        }
        #endif
        guard sourceWallHeight > 0, wallHeight > 0 else { return unproject(point) }
        func projectedX(_ x: CGFloat) -> CGFloat {
            let ground = wallGround(at: x)
            return angle == .front ? (frontFloor?.project(ground).x ?? project(ground).x) : project(ground).x
        }
        var lower = worldSize.width / 2 - 512 * artworkScale
        var upper = worldSize.width / 2 + 512 * artworkScale
        let left = projectedX(lower), right = projectedX(upper)
        guard right - left > 0.000_001 else { return unproject(point) }
        let x: CGFloat
        if point.x < left {
            let step = max(1, artworkScale * 8)
            x = lower + (point.x - left) * step / (projectedX(lower + step) - left)
        } else if point.x > right {
            let step = max(1, artworkScale * 8)
            x = upper + (point.x - right) * step / (right - projectedX(upper - step))
        } else {
            // Each wall has its own seam; the front floor also changes affine
            // sectors. Invert their continuous, monotone x mapping together.
            for _ in 0..<48 {
                let middle = (lower + upper) / 2
                if projectedX(middle) < point.x { lower = middle } else { upper = middle }
            }
            x = (lower + upper) / 2
        }
        let ground = wallGround(at: x)
        let baseline = angle == .front ? (frontFloor?.destination.maxY ?? project(ground).y) : project(ground).y
        return CGPoint(x: x, y: ground.y + (point.y - baseline) * sourceWallHeight / wallHeight)
    }

    // Calibration uses room-empty.png's 1024×1536 top-left pixel coordinates and RoomArtworkTransform's aspect fill.
    // The retained 384px span remaps legacy decoration heights; it is separate from the projected wallHeight.
    // When replacing/reframing that artwork, recalibrate these values with RoomFloor.sourceFloor and RoomFurnitureWorld.wallPolygon.
    private var artworkScale: CGFloat { max(worldSize.width / 1024, worldSize.height / 1536) }
    private var sourceWallHeight: CGFloat { 384 * artworkScale }

    /// Legacy right-wall baseline shared by decoration heights and the upstairs window anchor.
    func wallGround(at x: CGFloat) -> CGPoint {
        // Right-wall/floor seam: source (442,530)→(1024,825); world y points upward.
        // 70=1024/2−442, 238=1536/2−530, and 295/582=(825−530)/(1024−442).
        let back = CGPoint(x: worldSize.width / 2 - 70 * artworkScale,
                           y: worldSize.height / 2 + 238 * artworkScale)
        return CGPoint(x: x, y: x < back.x
            ? back.y + (x - back.x) * 255 / 442
            : back.y - (x - back.x) * 295 / 582)
    }

    private func transform(_ point: CGPoint, radians: CGFloat) -> CGPoint {
        guard radians != 0 else { return point }
        // Undo the original 30° isometric basis, rotate its floor plane, then restore that basis.
        let cosine = cos(radians), sine = sin(radians), ratio = sqrt(CGFloat(3))
        return CGPoint(x: cosine * point.x - ratio * sine * point.y,
                       y: sine * point.x / ratio + cosine * point.y)
    }
}
