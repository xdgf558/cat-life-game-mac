#if os(macOS)
import CoreGraphics
import Foundation

/// A reversible display model; legacy physics and normalized save coordinates never change.
struct MacRoomProjection: Sendable {
    static let columns: CGFloat = 12
    static let rows: CGFloat = 7
    static let wallCells: CGFloat = 4.6
    static let stairCells = CGRect(x: 10, y: 4, width: 2, height: 3)
    static let doorClearanceCells = CGRect(x: 0, y: 1, width: 2, height: 2)
    /// Phone-world sprites are drawn for a tall diamond floor; the wide 12×7 room needs them
    /// smaller so a cat is about one cell and tall furniture stays under the 4.6-cell walls.
    static let spriteScale: CGFloat = 0.6
    let floorMapping: RoomFrontFloorProjection
    let angle: RoomViewAngle
    let unit: CGFloat
    let logicalBounds: CGRect
    var radians: CGFloat { -CGFloat(angle.rawValue) * .pi * 24 / 180 }
    var distance: CGFloat { angle == .front ? 22 : 40 }
    private let pitch: CGFloat = 0.5
    private let vertical: CGFloat = 0.88
    private let eyeHeight: CGFloat = 3.4

    init?(legacyFloor: [CGPoint], worldSize: CGSize, angle: RoomViewAngle) {
        guard worldSize.width.isFinite, worldSize.width > 0,
              let mapping = RoomFrontFloorProjection(polygon: legacyFloor,
                  destination: CGRect(x: 0, y: 0, width: Self.columns, height: Self.rows)) else { return nil }
        floorMapping = mapping
        self.angle = angle
        unit = worldSize.width / Self.columns
        logicalBounds = Self.bounds(legacyFloor)
    }
    func cellPoint(logical point: CGPoint) -> CGPoint { floorMapping.project(point) }
    func logicalPoint(cell point: CGPoint) -> CGPoint { floorMapping.unproject(point) }
    func project(_ point: CGPoint) -> CGPoint {
        let cell = cellPoint(logical: point)
        return projectCell(x: cell.x, height: 0, z: cell.y)
    }
    func projectCell(x: CGFloat, height: CGFloat, z: CGFloat) -> CGPoint {
        let centerX = x - Self.columns / 2, centerZ = z - Self.rows / 2
        let xr = centerX * cos(radians) - centerZ * sin(radians)
        let zr = centerX * sin(radians) + centerZ * cos(radians)
        let factor = distance / max(0.001, distance + zr)
        return CGPoint(x: unit * xr * factor,
            y: unit * ((pitch * zr + vertical * height) * factor + vertical * eyeHeight * (1 - factor)))
    }
    func unproject(_ point: CGPoint) -> CGPoint {
        let p = point.x / unit, q = point.y / unit
        let zr = q * distance / max(0.001, pitch * distance + vertical * eyeHeight - q)
        let xr = p * (distance + zr) / distance
        return logicalPoint(cell: CGPoint(x: xr * cos(radians) + zr * sin(radians) + Self.columns / 2,
                                           y: -xr * sin(radians) + zr * cos(radians) + Self.rows / 2))
    }
    func perspectiveScale(at logical: CGPoint) -> CGFloat { scale(atCell: cellPoint(logical: logical)) }
    func scale(atCell cell: CGPoint) -> CGFloat {
        let zr = (cell.x - Self.columns / 2) * sin(radians) + (cell.y - Self.rows / 2) * cos(radians)
        return Self.spriteScale * distance / max(0.001, distance + zr)
    }
    func wallPoint(x: CGFloat, height: CGFloat) -> CGPoint {
        projectCell(x: x, height: height, z: Self.rows)
    }
    func wallCoordinates(projected point: CGPoint) -> CGPoint {
        let p = point.x / unit, q = point.y / unit, z = Self.rows / 2
        let denominator = distance * cos(radians) - p * sin(radians)
        let x = (p * (distance + z * cos(radians)) + distance * z * sin(radians)) / max(0.001, denominator)
        let zr = x * sin(radians) + z * cos(radians)
        let factor = distance / max(0.001, distance + zr)
        let height = ((q - vertical * eyeHeight * (1 - factor)) / factor - pitch * zr) / vertical
        return CGPoint(x: x + Self.columns / 2, y: height)
    }
    var contentBounds: CGRect {
        Self.bounds([-0.3, Self.columns + 0.3].flatMap { x in
            [CGFloat.zero, Self.rows + 0.3].flatMap { z in
                [CGFloat(-0.4), Self.wallCells].map { projectCell(x: x, height: $0, z: z) }
            }
        })
    }
    func logicalBoundary(of cells: CGRect, samples: Int = 12) -> [CGPoint] {
        let corners = [CGPoint(x: cells.minX, y: cells.minY), CGPoint(x: cells.maxX, y: cells.minY),
                       CGPoint(x: cells.maxX, y: cells.maxY), CGPoint(x: cells.minX, y: cells.maxY)]
        return corners.indices.flatMap { index in
            let a = corners[index], b = corners[(index + 1) % corners.count]
            return (0..<samples).map { step in
                let t = CGFloat(step) / CGFloat(samples)
                return logicalPoint(cell: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
    }
    static func bounds(_ points: [CGPoint]) -> CGRect {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

enum MacRoomStructure: String, CaseIterable, Sendable { case door, stairs }
#endif
