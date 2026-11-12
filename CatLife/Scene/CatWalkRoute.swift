import Foundation
import CoreGraphics

/// Geometry is supplied by the room. Keep its exact straight segments;
/// smoothing a corner here could cut through an obstacle the route avoided.
struct CatWalkRoute {
    struct Segment {
        let origin: CGPoint
        let destination: CGPoint
        let startDistance: CGFloat
        let length: CGFloat
    }

    let segments: [Segment]
    let distance: CGFloat
    var origin: CGPoint { segments[0].origin }
    var destination: CGPoint { segments[segments.count - 1].destination }

    init?(_ points: [CGPoint]) {
        guard points.count > 1, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        var result: [Segment] = []
        var distance: CGFloat = 0
        for (origin, destination) in zip(points, points.dropFirst()) {
            let length = hypot(destination.x - origin.x, destination.y - origin.y)
            guard length.isFinite else { return nil }
            // Duplicate waypoints do not create a pause or reset the gait.
            guard length > 0 else { continue }
            result.append(Segment(origin: origin, destination: destination,
                                  startDistance: distance, length: length))
            distance += length
        }
        guard distance.isFinite, distance > 0, !result.isEmpty else { return nil }
        segments = result
        self.distance = distance
    }

    func sample(at travelled: CGFloat) -> (point: CGPoint, horizontalDirection: CGFloat) {
        let travelled = min(distance, max(0, travelled))
        let segment = segments.first { travelled < $0.startDistance + $0.length } ?? segments[segments.count - 1]
        let fraction = min(1, max(0, (travelled - segment.startDistance) / segment.length))
        let dx = segment.destination.x - segment.origin.x
        return (CGPoint(x: segment.origin.x + dx * fraction,
                        y: segment.origin.y + (segment.destination.y - segment.origin.y) * fraction), dx)
    }
}
