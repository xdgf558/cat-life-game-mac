import CoreGraphics
import Foundation

/// A continuous triangle fan straightens the legacy floor without changing saved or navigable coordinates.
struct RoomFrontFloorProjection: Sendable {
    let sourcePolygon: [CGPoint]
    let sourceCenter: CGPoint
    let destination: CGRect
    private let destinationPolygon: [CGPoint]

    init?(polygon: [CGPoint], destination: CGRect) {
        guard destination.minX.isFinite, destination.minY.isFinite,
              destination.width.isFinite, destination.height.isFinite,
              destination.width > 0, destination.height > 0,
              polygon.count >= 4, polygon.allSatisfy(Self.finite) else { return nil }
        var points: [CGPoint] = []
        for point in polygon where points.last.map({ Self.distanceSquared($0, point) > 0.00000001 }) ?? true {
            points.append(point)
        }
        if let first = points.first, let last = points.last,
           Self.distanceSquared(first, last) <= 0.00000001 { points.removeLast() }
        guard points.count >= 4 else { return nil }
        let area = Self.signedArea(points)
        guard area.isFinite, abs(area) > 0.000001 else { return nil }
        if area > 0 { points.reverse() }
        let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
        guard maxX > minX, maxY > minY else { return nil }
        let tolerance = max(maxX - minX, maxY - minY) * 0.0000001
        func corner(at x: CGFloat, highest: Bool) -> Int? {
            let candidates = points.indices.filter { abs(points[$0].x - x) <= tolerance }
            return highest ? candidates.max { points[$0].y < points[$1].y }
                : candidates.min { points[$0].y < points[$1].y }
        }
        guard let leftBack = corner(at: minX, highest: true),
              let rightBack = corner(at: maxX, highest: true),
              let rightFront = corner(at: maxX, highest: false),
              let leftFront = corner(at: minX, highest: false) else { return nil }
        let corners = [leftBack, rightBack, rightFront, leftFront]
        guard Set(corners).count == 4 else { return nil }
        let offsets = corners.map { ($0 - leftBack + points.count) % points.count }
        guard zip(offsets, offsets.dropFirst()).allSatisfy({ $0.0 < $0.1 }) else { return nil }

        // The window-bay notch is concave: the bounding-box center alone is not a general kernel guarantee.
        var kernel = [CGPoint(x: minX, y: minY), CGPoint(x: minX, y: maxY),
                      CGPoint(x: maxX, y: maxY), CGPoint(x: maxX, y: minY)]
        for index in points.indices {
            kernel = Self.clipKernel(kernel, edgeStart: points[index], edgeEnd: points[(index + 1) % points.count])
            guard kernel.count >= 3 else { return nil }
        }
        guard abs(Self.signedArea(kernel)) > 0.000001 else { return nil }
        let center = CGPoint(x: kernel.map(\.x).reduce(0, +) / CGFloat(kernel.count),
                             y: kernel.map(\.y).reduce(0, +) / CGFloat(kernel.count))
        let targetCorners = [CGPoint(x: destination.minX, y: destination.maxY),
                             CGPoint(x: destination.maxX, y: destination.maxY),
                             CGPoint(x: destination.maxX, y: destination.minY),
                             CGPoint(x: destination.minX, y: destination.minY)]
        var source: [CGPoint] = [], target: [CGPoint] = []
        for side in 0..<4 {
            let first = corners[side], last = corners[(side + 1) % 4]
            var chain = [points[first]], index = first
            while index != last {
                index = (index + 1) % points.count
                chain.append(points[index])
            }
            let lengths = zip(chain, chain.dropFirst()).map { sqrt(Self.distanceSquared($0.0, $0.1)) }
            let length = lengths.reduce(0, +)
            guard length > 0.000001 else { return nil }
            var distance: CGFloat = 0
            for index in 0..<(chain.count - 1) {
                source.append(chain[index])
                target.append(Self.interpolate(targetCorners[side], targetCorners[(side + 1) % 4], distance / length))
                distance += lengths[index]
            }
        }
        let targetCenter = CGPoint(x: destination.midX, y: destination.midY)
        for index in source.indices {
            let next = (index + 1) % source.count
            guard Self.cross(Self.subtract(source[index], center), Self.subtract(source[next], center)) < -0.000001,
                  Self.cross(Self.subtract(target[index], targetCenter), Self.subtract(target[next], targetCenter)) < -0.000001 else { return nil }
        }
        sourcePolygon = source
        sourceCenter = center
        self.destination = destination
        destinationPolygon = target
    }

    func project(_ point: CGPoint) -> CGPoint {
        map(point, from: sourcePolygon, center: sourceCenter,
            to: destinationPolygon, targetCenter: CGPoint(x: destination.midX, y: destination.midY))
    }

    func unproject(_ point: CGPoint) -> CGPoint {
        map(point, from: destinationPolygon, center: CGPoint(x: destination.midX, y: destination.midY),
            to: sourcePolygon, targetCenter: sourceCenter)
    }

    private func map(_ point: CGPoint, from source: [CGPoint], center: CGPoint,
                     to target: [CGPoint], targetCenter: CGPoint) -> CGPoint {
        guard Self.finite(point) else { return point }
        let offset = Self.subtract(point, center)
        var nearest = (index: 0, u: CGFloat.zero, v: CGFloat.zero, penalty: CGFloat.infinity)
        for index in source.indices {
            let next = (index + 1) % source.count
            let a = Self.subtract(source[index], center), b = Self.subtract(source[next], center)
            let determinant = Self.cross(a, b)
            let u = Self.cross(offset, b) / determinant
            let v = Self.cross(a, offset) / determinant
            let penalty = max(0, -u) + max(0, -v)
            if penalty < nearest.penalty { nearest = (index, u, v, penalty) }
            // The angular sector also extrapolates points outside the floor, keeping contact offsets reversible.
            if u >= -0.00000001, v >= -0.00000001 { break }
        }
        let next = (nearest.index + 1) % target.count
        let a = Self.subtract(target[nearest.index], targetCenter)
        let b = Self.subtract(target[next], targetCenter)
        return CGPoint(x: targetCenter.x + nearest.u * a.x + nearest.v * b.x,
                       y: targetCenter.y + nearest.u * a.y + nearest.v * b.y)
    }

    private static func clipKernel(_ polygon: [CGPoint], edgeStart: CGPoint, edgeEnd: CGPoint) -> [CGPoint] {
        guard let last = polygon.last else { return [] }
        let edge = subtract(edgeEnd, edgeStart)
        func distance(_ point: CGPoint) -> CGFloat { -cross(edge, subtract(point, edgeStart)) }
        var result: [CGPoint] = [], previous = last, previousDistance = distance(last)
        for current in polygon {
            let currentDistance = distance(current)
            if (previousDistance >= 0) != (currentDistance >= 0) {
                result.append(interpolate(previous, current, previousDistance / (previousDistance - currentDistance)))
            }
            if currentDistance >= 0 { result.append(current) }
            previous = current
            previousDistance = currentDistance
        }
        return result
    }

    private static func signedArea(_ polygon: [CGPoint]) -> CGFloat {
        polygon.indices.reduce(0) { $0 + cross(polygon[$1], polygon[($1 + 1) % polygon.count]) } / 2
    }
    private static func finite(_ point: CGPoint) -> Bool { point.x.isFinite && point.y.isFinite }
    private static func subtract(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    private static func cross(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x * b.y - a.y * b.x }
    private static func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let delta = subtract(a, b)
        return delta.x * delta.x + delta.y * delta.y
    }
    private static func interpolate(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
