import Foundation
import CoreGraphics

/// A floor-space navigator. Artwork, screen transforms and animation stay in the
/// scene; this type only knows a floor polygon, solid objects and the cat's feet.
/// Coordinates can use either orientation as long as every input uses the same one.
public struct RoomNavigation: Sendable {
    public enum FloorFootprintShape: Equatable, Sendable {
        case rectangle, clippedCorners
    }

    public let floor: [CGPoint]
    public let obstacles: [CGRect]
    public let footprint: CGSize
    public let floorFootprintShape: FloorFootprintShape
    public let cellSize: CGFloat
    public private(set) var walkablePoints: [CGPoint] = []

    private let bounds: CGRect
    private let valid: Bool
    private var columns = 0
    private var rows = 0
    private var grid: [CGPoint?] = []
    private static let epsilon: CGFloat = 0.000_001

    /// Deferred grids keep geometry checks cheap while testing candidate layouts.
    /// Leave precomputation enabled when using walkablePoints or nearestWalkable
    /// to recover an invalid position. A deferred route builds its own grid only
    /// when the exact endpoints cannot be connected by a safe straight segment.
    public init(floor: [CGPoint], obstacles: [CGRect], footprint: CGSize, cellSize: CGFloat = 8,
                precomputeGrid: Bool = true, floorFootprintShape: FloorFootprintShape = .rectangle) {
        self.floor = floor
        self.obstacles = obstacles.map(\.standardized)
        self.footprint = footprint
        self.floorFootprintShape = floorFootprintShape
        let finiteFloor = floor.count >= 3 && floor.allSatisfy(Self.finite)
        let finiteObjects = obstacles.allSatisfy {
            !$0.isNull && !$0.isInfinite && $0.origin.x.isFinite && $0.origin.y.isFinite
                && $0.width.isFinite && $0.height.isFinite
        }
        if finiteFloor {
            let xs = floor.map(\.x), ys = floor.map(\.y)
            bounds = CGRect(x: xs.min()!, y: ys.min()!,
                            width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        } else { bounds = .zero }
        valid = finiteFloor && finiteObjects && footprint.width.isFinite && footprint.height.isFinite
            && footprint.width > 0 && footprint.height > 0 && bounds.width > 0 && bounds.height > 0
        // Keep malformed/very large scene coordinates from creating unbounded grids.
        let requested = cellSize.isFinite && cellSize > 0 ? cellSize : 8
        self.cellSize = max(requested, max(bounds.width, bounds.height) / 120)
        guard valid, precomputeGrid else { return }
        columns = Int(ceil(bounds.width / self.cellSize)) + 1
        rows = Int(ceil(bounds.height / self.cellSize)) + 1
        grid = [CGPoint?](repeating: nil, count: columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let point = CGPoint(x: min(bounds.maxX, bounds.minX + CGFloat(column) * self.cellSize),
                                    y: min(bounds.maxY, bounds.minY + CGFloat(row) * self.cellSize))
                if isWalkable(point) {
                    grid[row * columns + column] = point
                    walkablePoints.append(point)
                }
            }
        }
    }

    /// Checks the whole footprint, including concave notches in the room boundary.
    public func isWalkable(_ point: CGPoint) -> Bool {
        segmentIsWalkable(from: point, to: point)
    }

    /// Tests a swept footprint, so a thin obstacle between safe endpoints cannot
    /// be skipped by a fast animation or by path simplification.
    public func segmentIsWalkable(from start: CGPoint, to end: CGPoint) -> Bool {
        guard valid, Self.finite(start), Self.finite(end) else { return false }
        let halfWidth = footprint.width / 2, halfHeight = footprint.height / 2
        for obstacle in obstacles {
            let inflated = obstacle.insetBy(dx: -halfWidth, dy: -halfHeight)
            if Self.segment(start, end, intersects: inflated) { return false }
        }
        let swept = Self.convexHull(floorVertices(at: start) + floorVertices(at: end))
        guard swept.allSatisfy(pointIsOnFloor) else { return false }
        // Safe vertices alone are insufficient: a narrow concave wall can
        // enter between them. No floor boundary may cross the swept interior.
        for index in floor.indices {
            if Self.segmentEntersInterior(floor[index], floor[(index + 1) % floor.count], of: swept) {
                return false
            }
        }
        return true
    }

    /// Includes the exact endpoints. An unreachable destination returns nil;
    /// callers must stay put or choose another destination, never draw a straight fallback.
    public func route(from start: CGPoint, to end: CGPoint) -> [CGPoint]? {
        guard isWalkable(start), isWalkable(end) else { return nil }
        if Self.distance(start, end) < Self.epsilon { return [start] }
        if segmentIsWalkable(from: start, to: end) { return [start, end] }
        if grid.isEmpty {
            let navigator = RoomNavigation(floor: floor, obstacles: obstacles,
                                           footprint: footprint, cellSize: cellSize,
                                           floorFootprintShape: floorFootprintShape)
            return navigator.route(from: start, to: end)
        }
        let starts = connectors(for: start, limit: 12), ends = connectors(for: end, limit: 12)
        if let path = gridRoute(from: start, to: end, starts: starts, ends: ends) { return path }
        // A narrow passage may admit a long safe segment while containing no
        // adjacent grid cells. The nearest connectors alone can miss that link,
        // even after a cat has walked through it. Retry once with every visible
        // connector; all links still pass the full swept-footprint check.
        let allStarts = connectors(for: start, limit: nil), allEnds = connectors(for: end, limit: nil)
        guard allStarts.count > starts.count || allEnds.count > ends.count else { return nil }
        return gridRoute(from: start, to: end, starts: allStarts, ends: allEnds)
    }

    private func gridRoute(from start: CGPoint, to end: CGPoint,
                           starts: [(index: Int, distance: CGFloat)],
                           ends: [(index: Int, distance: CGFloat)]) -> [CGPoint]? {
        guard !starts.isEmpty, !ends.isEmpty else { return nil }
        let goal = grid.count
        var distance = [CGFloat](repeating: .infinity, count: grid.count + 1)
        var previous = [Int](repeating: -1, count: grid.count + 1)
        let endCosts = Dictionary(uniqueKeysWithValues: ends.map { ($0.index, $0.distance) })
        var queue = NavigationHeap()
        for connection in starts {
            distance[connection.index] = connection.distance
            previous[connection.index] = -2
            queue.push(.init(index: connection.index, cost: connection.distance,
                             estimate: connection.distance + Self.distance(grid[connection.index]!, end)))
        }
        let directions = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
        while let current = queue.pop() {
            guard current.cost <= distance[current.index] + Self.epsilon else { continue }
            if current.index == goal {
                var indices: [Int] = []
                var index = previous[goal]
                while index >= 0 { indices.append(index); index = previous[index] }
                let points = [start] + indices.reversed().compactMap { grid[$0] } + [end]
                return simplify(points)
            }
            let point = grid[current.index]!
            if let finalDistance = endCosts[current.index] {
                let total = current.cost + finalDistance
                if total < distance[goal] {
                    distance[goal] = total
                    previous[goal] = current.index
                    queue.push(.init(index: goal, cost: total, estimate: total))
                }
            }
            let row = current.index / columns, column = current.index % columns
            for (dx, dy) in directions {
                let nextColumn = column + dx, nextRow = row + dy
                guard (0..<columns).contains(nextColumn), (0..<rows).contains(nextRow) else { continue }
                let next = nextRow * columns + nextColumn
                guard let destination = grid[next] else { continue }
                let total = current.cost + Self.distance(point, destination)
                guard total + Self.epsilon < distance[next], segmentIsWalkable(from: point, to: destination) else { continue }
                distance[next] = total
                previous[next] = current.index
                queue.push(.init(index: next, cost: total, estimate: total + Self.distance(destination, end)))
            }
        }
        return nil
    }

    /// For initial layout or resizing only, not for teleporting around a blocked path.
    public func nearestWalkable(to point: CGPoint) -> CGPoint? {
        guard Self.finite(point) else { return nil }
        if isWalkable(point) { return point }
        return walkablePoints.min { Self.distance($0, point) < Self.distance($1, point) }
    }

    private func connectors(for point: CGPoint, limit: Int?) -> [(index: Int, distance: CGFloat)] {
        let nearby = grid.indices.compactMap { index -> (index: Int, distance: CGFloat)? in
            guard let candidate = grid[index] else { return nil }
            return (index, Self.distance(point, candidate))
        }.sorted { $0.distance == $1.distance ? $0.index < $1.index : $0.distance < $1.distance }
        var result: [(index: Int, distance: CGFloat)] = []
        for candidate in nearby {
            if segmentIsWalkable(from: point, to: grid[candidate.index]!) { result.append(candidate) }
            if let limit, result.count == limit { break }
        }
        return result
    }

    private func simplify(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var result = [points[0]], current = 0
        while current < points.count - 1 {
            var next = points.count - 1
            while next > current + 1 && !segmentIsWalkable(from: points[current], to: points[next]) { next -= 1 }
            // Every adjacent grid edge was already checked. Keep that edge if a
            // longer shortcut would intersect a bowl or clip a concave floor edge.
            if Self.distance(result.last!, points[next]) > Self.epsilon { result.append(points[next]) }
            current = next
        }
        return result
    }

    private func pointIsOnFloor(_ point: CGPoint) -> Bool {
        guard point.x >= bounds.minX - Self.epsilon, point.x <= bounds.maxX + Self.epsilon,
              point.y >= bounds.minY - Self.epsilon, point.y <= bounds.maxY + Self.epsilon else { return false }
        var inside = false
        for index in floor.indices {
            let a = floor[index], b = floor[(index + 1) % floor.count]
            let area = Self.cross(a, b, point)
            if abs(area) < Self.epsilon && point.x >= min(a.x, b.x) - Self.epsilon
                && point.x <= max(a.x, b.x) + Self.epsilon && point.y >= min(a.y, b.y) - Self.epsilon
                && point.y <= max(a.y, b.y) + Self.epsilon { return true }
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
        }
        return inside
    }

    private static func finite(_ point: CGPoint) -> Bool { point.x.isFinite && point.y.isFinite }
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
    private static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }
    private func floorVertices(at p: CGPoint) -> [CGPoint] {
        let a = footprint.width / 2, b = footprint.height / 2
        switch floorFootprintShape {
        case .rectangle:
            return [CGPoint(x: p.x - a, y: p.y - b), CGPoint(x: p.x + a, y: p.y - b),
                    CGPoint(x: p.x + a, y: p.y + b), CGPoint(x: p.x - a, y: p.y + b)]
        case .clippedCorners:
            // This octagon contains the same-bounds ellipse and retains every
            // axis extreme. Obstacle collisions still use the full rectangle.
            return [CGPoint(x: p.x - a, y: p.y - b / 2), CGPoint(x: p.x - a / 2, y: p.y - b),
                    CGPoint(x: p.x + a / 2, y: p.y - b), CGPoint(x: p.x + a, y: p.y - b / 2),
                    CGPoint(x: p.x + a, y: p.y + b / 2), CGPoint(x: p.x + a / 2, y: p.y + b),
                    CGPoint(x: p.x - a / 2, y: p.y + b), CGPoint(x: p.x - a, y: p.y + b / 2)]
        }
    }
    private static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for point in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 { lower.removeLast() }
            lower.append(point)
        }
        for point in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 { upper.removeLast() }
            upper.append(point)
        }
        lower.removeLast(); upper.removeLast()
        return lower + upper
    }

    private static func segment(_ start: CGPoint, _ end: CGPoint, intersects rect: CGRect) -> Bool {
        var low: CGFloat = 0, high: CGFloat = 1
        for (origin, delta, minimum, maximum) in [
            (start.x, end.x - start.x, rect.minX, rect.maxX),
            (start.y, end.y - start.y, rect.minY, rect.maxY)
        ] {
            if abs(delta) < epsilon {
                if origin < minimum - epsilon || origin > maximum + epsilon { return false }
            } else {
                let first = (minimum - origin) / delta, second = (maximum - origin) / delta
                low = max(low, min(first, second)); high = min(high, max(first, second))
                if low > high + epsilon { return false }
            }
        }
        return true
    }

    /// Clip a floor edge to the strict interior of a counterclockwise convex hull.
    /// Collinear contact with the floor boundary is allowed; crossing it is not.
    private static func segmentEntersInterior(_ start: CGPoint, _ end: CGPoint, of polygon: [CGPoint]) -> Bool {
        var low: CGFloat = 0, high: CGFloat = 1
        for index in polygon.indices {
            let a = polygon[index], b = polygon[(index + 1) % polygon.count]
            let edgeLength = distance(a, b)
            guard edgeLength > epsilon else { continue }
            let initial = cross(a, b, start) / edgeLength
            let delta = cross(a, b, end) / edgeLength - initial
            if abs(delta) < epsilon {
                if initial <= epsilon { return false }
            } else {
                let boundary = (epsilon - initial) / delta
                if delta > 0 { low = max(low, boundary) } else { high = min(high, boundary) }
                if low >= high - epsilon { return false }
            }
        }
        return low < high - epsilon
    }
}

private struct NavigationHeap {
    struct Entry {
        let index: Int
        let cost: CGFloat
        let estimate: CGFloat
    }
    private var entries: [Entry] = []
    mutating func push(_ entry: Entry) {
        entries.append(entry)
        var index = entries.count - 1
        while index > 0 {
            let parent = (index - 1) / 2
            guard precedes(entries[index], entries[parent]) else { break }
            entries.swapAt(index, parent); index = parent
        }
    }
    mutating func pop() -> Entry? {
        guard !entries.isEmpty else { return nil }
        if entries.count == 1 { return entries.removeLast() }
        let result = entries[0]
        entries[0] = entries.removeLast()
        var index = 0
        while index * 2 + 1 < entries.count {
            let left = index * 2 + 1, right = left + 1
            let best = right < entries.count && precedes(entries[right], entries[left]) ? right : left
            guard precedes(entries[best], entries[index]) else { break }
            entries.swapAt(best, index); index = best
        }
        return result
    }
    private func precedes(_ lhs: Entry, _ rhs: Entry) -> Bool {
        lhs.estimate == rhs.estimate ? lhs.index < rhs.index : lhs.estimate < rhs.estimate
    }
}
