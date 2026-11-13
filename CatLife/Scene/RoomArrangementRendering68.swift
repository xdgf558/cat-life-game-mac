import SpriteKit
import CatGameCore

/// Scene-only grid and footprints use exactly the editor's coordinate conversion.
@MainActor
final class RoomArrangementRendering68: SKNode {
    private let gridLines = SKShapeNode()
    private let footprint = SKShapeNode()
    private let direction = SKShapeNode()
    private var gridSignature = ""
    private var selectionSignature = ""

    override init() {
        super.init()
        name = "arrangement-grid68"
        zPosition = 2
        gridLines.strokeColor = UIColor.white.withAlphaComponent(0.65)
        gridLines.lineWidth = 1
        gridLines.zPosition = 0
        footprint.name = "arrangement-footprint68"
        footprint.lineWidth = 2
        footprint.zPosition = 1
        direction.zPosition = 2
        direction.strokeColor = .white
        direction.lineWidth = 1
        addChild(gridLines); addChild(footprint); addChild(direction)
    }
    required init?(coder: NSCoder) { fatalError("Created in code") }

    func update(world: RoomFurnitureWorld?, projection: RoomViewProjection, editing: Bool,
                selectedID: String?, bowlSelected: Bool, issues: [String: ArrangementIssue68], previewCenter: CGPoint? = nil) {
        isHidden = !editing
        guard editing, let world else { return }
        let signature = "\(world.transform.sceneSize)|\(world.transform.visualScale)|\(projection.angle)|\(String(describing: projection.frontFloor?.destination))"
        if signature != gridSignature {
            gridSignature = signature
            let grid = RoomArrangementGrid68(transform: world.transform)
            let polygon = world.roomFloor.polygon
            let points = polygon.map { grid.gridPoint(world: $0) }
            if let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
               let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() {
                let path = CGMutablePath()
                func add(_ start: CGPoint, _ end: CGPoint) {
                    for segment in Self.clipped(start, end, polygon: polygon) {
                        // Rectified front projection is piecewise affine: sample each segment so grid lines follow its seams.
                        for index in 0...24 {
                            let t = CGFloat(index) / 24
                            let p = projection.project(CGPoint(x: segment.0.x + (segment.1.x - segment.0.x) * t,
                                                               y: segment.0.y + (segment.1.y - segment.0.y) * t))
                            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                        }
                    }
                }
                for x in Int(floor(minX))...Int(ceil(maxX)) {
                    add(grid.worldPoint(grid: CGPoint(x: CGFloat(x), y: minY - 1)),
                        grid.worldPoint(grid: CGPoint(x: CGFloat(x), y: maxY + 1)))
                }
                for y in Int(floor(minY))...Int(ceil(maxY)) {
                    add(grid.worldPoint(grid: CGPoint(x: minX - 1, y: CGFloat(y))),
                        grid.worldPoint(grid: CGPoint(x: maxX + 1, y: CGFloat(y))))
                }
                gridLines.path = path.copy(dashingWithPhase: 0, lengths: [4, 4])
                #if os(macOS)
                if let model = projection.macRoom {
                    let cells = CGMutablePath()
                    func line(_ a: CGPoint, _ b: CGPoint) {
                        for index in 0...24 {
                            let t = CGFloat(index) / 24
                            let point = model.projectCell(x: a.x + (b.x - a.x) * t, height: 0.015,
                                                          z: a.y + (b.y - a.y) * t)
                            if index == 0 { cells.move(to: point) } else { cells.addLine(to: point) }
                        }
                    }
                    for x in 0...12 { line(CGPoint(x: CGFloat(x), y: 0), CGPoint(x: CGFloat(x), y: 7)) }
                    for z in 0...7 { line(CGPoint(x: 0, y: CGFloat(z)), CGPoint(x: 12, y: CGFloat(z))) }
                    gridLines.path = cells.copy(dashingWithPhase: 0, lengths: [4, 4])
                }
                #endif
            }
        }
        let center = previewCenter ?? selectedID.flatMap(world.center) ?? world.bowlPosition
        let previewWorld = selectedID.map { world.replacing($0, with: center) } ?? world
        let item = selectedID.flatMap(previewWorld.item)
        let wall = item.map { FurnitureCatalog.metadata(for: $0.kind).isWall } ?? false
        let key = selectedID ?? "bowl"
        let selected = selectedID != nil || bowlSelected
        footprint.isHidden = !selected; direction.isHidden = !selected || wall
        guard selected else { return }
        let size = item.map(previewWorld.footprint) ?? world.roomFloor.bowlFootprint
        let orientation = item?.orientation ?? .front
        let invalid = issues[key] != nil
        let selectionKey = "\(signature)|\(key)|\(center)|\(size)|\(orientation)|\(invalid)"
        guard selectionKey != selectionSignature else { return }
        selectionSignature = selectionKey
        let color = invalid ? UIColor(red: 0.87, green: 0.31, blue: 0.36, alpha: 1)
                            : UIColor(red: 0.15, green: 0.66, blue: 0.48, alpha: 1)
        footprint.strokeColor = color; footprint.fillColor = color.withAlphaComponent(0.23)
        direction.fillColor = color
        func project(_ point: CGPoint) -> CGPoint { wall ? projection.wallPoint(point) : projection.project(point) }
        let corners = [CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
                       CGPoint(x: center.x + size.width / 2, y: center.y - size.height / 2),
                       CGPoint(x: center.x + size.width / 2, y: center.y + size.height / 2),
                       CGPoint(x: center.x - size.width / 2, y: center.y + size.height / 2)].map(project)
        let path = CGMutablePath(); path.addLines(between: corners); path.closeSubpath()
        footprint.path = wall ? path.copy(dashingWithPhase: 0, lengths: [5, 3]) : path
        let vector = orientation.rotatedOffset(CGPoint(x: 0, y: -1))
        let point = CGPoint(x: center.x + vector.x * size.width * 0.58,
                            y: center.y + vector.y * size.height * 0.58)
        let tip = projection.project(point), base = projection.project(center)
        let angle = atan2(tip.y - base.y, tip.x - base.x)
        let arrow = CGMutablePath()
        arrow.addLines(between: [CGPoint(x: 7, y: 0), CGPoint(x: -5, y: 5), CGPoint(x: -5, y: -5)])
        arrow.closeSubpath(); direction.path = arrow; direction.position = tip; direction.zRotation = angle
    }

    /// Split at every polygon crossing; midpoint testing also handles the concave window bay.
    static func clipped(_ a: CGPoint, _ b: CGPoint, polygon: [CGPoint]) -> [(CGPoint, CGPoint)] {
        guard polygon.count >= 3 else { return [] }
        let d = CGPoint(x: b.x - a.x, y: b.y - a.y)
        var cuts: [CGFloat] = [0, 1]
        for index in polygon.indices {
            let p = polygon[index], q = polygon[(index + 1) % polygon.count]
            let e = CGPoint(x: q.x - p.x, y: q.y - p.y)
            let denominator = d.x * e.y - d.y * e.x
            guard abs(denominator) > 0.00001 else { continue }
            let delta = CGPoint(x: p.x - a.x, y: p.y - a.y)
            let t = (delta.x * e.y - delta.y * e.x) / denominator
            let u = (delta.x * d.y - delta.y * d.x) / denominator
            if t > 0, t < 1, u >= 0, u <= 1 { cuts.append(t) }
        }
        cuts.sort()
        func point(_ t: CGFloat) -> CGPoint { CGPoint(x: a.x + d.x * t, y: a.y + d.y * t) }
        func inside(_ p: CGPoint) -> Bool {
            let path = CGMutablePath(); path.addLines(between: polygon); path.closeSubpath()
            return path.contains(p)
        }
        return zip(cuts, cuts.dropFirst()).compactMap { lo, hi in
            guard hi - lo > 0.00001, inside(point((lo + hi) / 2)) else { return nil }
            return (point(lo), point(hi))
        }
    }
}

/// Three translucent ellipses avoid per-frame blur/glow work and keep shadows separate from the art.
@MainActor
final class RoomContactShadow68: SKNode {
    private var cachedSize = CGSize.zero
    private let rings = (0..<3).map { _ in SKShapeNode() }
    override init() {
        super.init()
        name = "furniture-contact-shadow68"; zPosition = 1
        for ring in rings { ring.strokeColor = .clear; addChild(ring) }
    }
    required init?(coder: NSCoder) { fatalError("Created in code") }
    func update(center: CGPoint, size: CGSize, selected: Bool, hidden: Bool, alpha: CGFloat) {
        position = center; isHidden = hidden; self.alpha = alpha
        if size != cachedSize {
            cachedSize = size
            for (index, ring) in rings.enumerated() {
                let factor = 1 - CGFloat(index) * 0.17
                ring.path = CGPath(ellipseIn: CGRect(x: -size.width * factor / 2, y: -size.height * factor / 2,
                    width: size.width * factor, height: size.height * factor), transform: nil)
            }
        }
        for (index, ring) in rings.enumerated() {
            ring.fillColor = UIColor(red: 0.30, green: 0.21, blue: 0.14,
                                     alpha: (selected ? 0.09 : 0.045) + CGFloat(index) * 0.012)
        }
    }
}
