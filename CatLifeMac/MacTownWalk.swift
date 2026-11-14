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

    /// The shortest road route from `from` (a destination, waypoint or the start) to `place`, excluding `from`.
    /// Every combination of connectors is tried, so a two-road change never detours via a side path.
    static func route(from: CGPoint, to place: TownPlace) -> [CGPoint] {
        let lane = startLane(from)
        let changes = abs(row(of: place) - lane)
        var options: [[Int]] = [[]]
        var step = lane
        for _ in 0..<changes {
            let down = row(of: place) > step
            let count = connectors[down ? step : step - 1].count
            options = options.flatMap { prefix in (0..<count).map { prefix + [$0] } }
            step += down ? 1 : -1
        }
        return options.map { build(from: from, to: place, links: $0) }
            .min { length(from: from, $0) < length(from: from, $1) } ?? []
    }

    /// Redirecting mid-leg: carry on to the leg's end or turn back to its start, whichever is shorter overall.
    static func route(from position: CGPoint, leg: (start: CGPoint, end: CGPoint)?, to place: TownPlace) -> [CGPoint] {
        guard let leg else { return route(from: position, to: place) }
        return [leg.start, leg.end].map { [$0] + route(from: $0, to: place) }
            .min { length(from: position, $0) < length(from: position, $1) } ?? []
    }

    static func length(from: CGPoint, _ points: [CGPoint]) -> CGFloat {
        var total: CGFloat = 0, previous = from
        for point in points { total += distance(previous, point); previous = point }
        return total
    }

    private static func startLane(_ point: CGPoint) -> Int { point.y > roads[2] + 0.02 ? 2 : nearestRoad(to: point.y) }

    private static func build(from: CGPoint, to place: TownPlace, links: [Int]) -> [CGPoint] {
        var points: [CGPoint] = []
        var here = from
        func go(_ point: CGPoint) {
            guard abs(point.x - here.x) > 0.001 || abs(point.y - here.y) > 0.001 else { return }
            points.append(point); here = point
        }
        // Step back onto a road first.
        var lane = startLane(here)
        if here.y > roads[2] + 0.02 {
            // On a bottom spur: back to that spur's line, then up to the road.
            let spurX = spurLines.min { abs($0 - here.x) < abs($1 - here.x) } ?? here.x
            go(CGPoint(x: spurX, y: here.y))
            go(CGPoint(x: spurX, y: roads[2]))
        } else {
            go(CGPoint(x: here.x, y: roads[lane]))
        }
        for choice in links {
            let down = row(of: place) > lane
            let link = connectors[down ? lane : lane - 1][choice]
            go(CGPoint(x: down ? link.top : link.bottom, y: roads[lane]))
            lane += down ? 1 : -1
            go(CGPoint(x: down ? link.bottom : link.top, y: roads[lane]))
        }
        if isOnSpur(place) {
            let spurX = MacTownViewport69.position(place).x
            go(CGPoint(x: spurX, y: roads[2]))
            go(CGPoint(x: spurX, y: spurDepth))
        }
        go(destination(for: place))
        return points
    }

    private static var spurLines: [CGFloat] { TownPlace.mapPlaces.filter(isOnSpur).map { MacTownViewport69.position($0).x } }

    static func nearestRoad(to y: CGFloat) -> Int {
        roads.indices.min { abs(roads[$0] - y) < abs(roads[$1] - y) } ?? 2
    }
    /// Map-space distance, with height weighted for the map's wide aspect.
    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, (a.y - b.y) * 0.7)
    }
}
