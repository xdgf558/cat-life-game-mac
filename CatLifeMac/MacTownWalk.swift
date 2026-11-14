import CoreGraphics
import SwiftUI

/// Route planning for the player walking on the Mac town map. Coordinates are normalized
/// (0...1) map positions like `MacTownViewport69.position`; nothing here enters a save.
///
/// The map has three east-west roads joined by the bridge and a few side paths, and short
/// spurs down to the bottom lots. A walk follows those roads instead of crossing the grass.
enum MacTownWalk {
    /// Road heights, top to bottom (see `MacTownView.mapGround`).
    static let roads: [CGFloat] = [0.205, 0.53, 0.785]
    /// Where neighbouring roads connect: between road 0 and 1 only the bridge; between 1 and 2 three paths.
    static let connectors: [[(top: CGFloat, bottom: CGFloat)]] = [
        [(0.52, 0.52)],
        [(0.52, 0.52), (0.24, 0.16), (0.80, 0.80)]
    ]
    static let spurDepth: CGFloat = 0.86
    /// Stand a little to the right of the name plaque, so the plaque stays readable.
    static let standOffset: CGFloat = 0.07

    /// Where the player waits when the town opens for the first time this session: just outside home.
    static let start = CGPoint(x: MacTownViewport69.position(.home).x + standOffset, y: roads[2])
    /// The last spot is remembered for this run of the app only (presentation state, never saved).
    @MainActor static var lastSpot = start

    static func row(of place: TownPlace) -> Int {
        let y = MacTownViewport69.position(place).y
        return y < 0.3 ? 0 : (y < 0.6 ? 1 : 2)
    }
    static func isOnSpur(_ place: TownPlace) -> Bool { MacTownViewport69.position(place).y > 0.79 }

    static func destination(for place: TownPlace) -> CGPoint {
        let x = MacTownViewport69.position(place).x
        // Bottom lots sit near the right edge, so on a spur the player waits on the left of the sign.
        if isOnSpur(place) { return CGPoint(x: x - standOffset * 0.8, y: spurDepth) }
        return CGPoint(x: min(0.97, x + standOffset), y: roads[row(of: place)])
    }

    /// Waypoints from `from` (a previous destination or the start) to `place`, excluding `from`.
    static func route(from: CGPoint, to place: TownPlace) -> [CGPoint] {
        var points: [CGPoint] = []
        var here = from
        func go(_ point: CGPoint) {
            guard abs(point.x - here.x) > 0.001 || abs(point.y - here.y) > 0.001 else { return }
            points.append(point); here = point
        }
        // Step back onto a road first.
        var lane = nearestRoad(to: here.y)
        if here.y > roads[2] + 0.02 {
            // On a bottom spur: walk back to the spur line, then up to the road.
            go(CGPoint(x: here.x + standOffset * 0.8, y: here.y))
            go(CGPoint(x: here.x, y: roads[2])); lane = 2
        } else {
            go(CGPoint(x: here.x, y: roads[lane]))
        }
        let target = row(of: place)
        let goal = destination(for: place).x
        while lane != target {
            let down = target > lane
            let pair = down ? connectors[lane] : connectors[lane - 1]
            // The connector that makes the shortest walk: here → its near end, far end → the goal.
            func cost(_ link: (top: CGFloat, bottom: CGFloat)) -> CGFloat {
                abs((down ? link.top : link.bottom) - here.x) + abs((down ? link.bottom : link.top) - goal)
            }
            guard let link = pair.min(by: { cost($0) < cost($1) }) else { break }
            go(CGPoint(x: down ? link.top : link.bottom, y: roads[lane]))
            lane += down ? 1 : -1
            go(CGPoint(x: down ? link.bottom : link.top, y: roads[lane]))
        }
        let end = destination(for: place)
        if isOnSpur(place) {
            let spurX = MacTownViewport69.position(place).x
            go(CGPoint(x: spurX, y: roads[2]))
            go(CGPoint(x: spurX, y: spurDepth))
        }
        go(end)
        return points
    }

    static func nearestRoad(to y: CGFloat) -> Int {
        roads.indices.min { abs(roads[$0] - y) < abs(roads[$1] - y) } ?? 2
    }
    /// Map-space distance, with height weighted for the map's wide aspect.
    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, (a.y - b.y) * 0.7)
    }
}
