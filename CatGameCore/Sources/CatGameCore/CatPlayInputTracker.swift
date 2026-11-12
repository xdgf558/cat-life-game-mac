import Foundation

/// Prototype parameters use playable-widths/second, independent of pixels and frame rate.
public struct CatPlayInputTracker: Sendable {
    public private(set) var kind: CatPlayInputKind = .still
    public private(set) var duration: TimeInterval = 0
    public private(set) var movementDuration: TimeInterval = 0
    private var previous: NormalizedPoint?
    private var previousTime: TimeInterval?
    private var lastMovementAt: TimeInterval?
    private var lastStillSampleAt: TimeInterval?
    private var episodeAt: TimeInterval?
    private var slowDuration: TimeInterval = 0
    public init() {}

    public mutating func move(to point: NormalizedPoint, at time: TimeInterval) {
        guard GameSnapshot.isUnitPosition(point), time.isFinite else { return }
        guard let previous, let previousTime else {
            self.previous = point; self.previousTime = time; return
        }
        let delta = time - max(previousTime, lastStillSampleAt ?? previousTime)
        guard delta > 0 else { return }
        let distance = hypot(point.x - previous.x, point.y - previous.y)
        guard distance > 0.001 else { tick(at: time); return }
        self.previous = point; self.previousTime = time
        if lastStillSampleAt != nil { movementDuration = 0; lastStillSampleAt = nil }
        // A long gap is not continuous dragging and cannot manufacture a slow interval.
        if delta > 0.35 { resetEpisode(at: time) }
        let speed = distance / delta
        let next: CatPlayInputKind = speed > 0.8 ? .tooFast : .slowMove
        if kind != next { episodeAt = time - min(delta, 0.25); slowDuration = 0 }
        kind = next
        movementDuration = min(20, movementDuration + min(delta, 0.25))
        if next == .slowMove { slowDuration = min(20, slowDuration + min(delta, 0.25)) }
        else { slowDuration = 0 }
        lastMovementAt = time
        duration = next == .slowMove ? slowDuration : min(20, time - (episodeAt ?? time))
    }

    public mutating func tick(at time: TimeInterval) {
        guard time.isFinite, let lastMovementAt, time >= lastMovementAt else { return }
        let pause = time - lastMovementAt
        if pause > 0.35 { lastStillSampleAt = time }
        if pause >= 0.55 && slowDuration >= 0.6 {
            kind = .moveAndPause; duration = min(20, slowDuration + pause)
        } else if pause > 0.35 { kind = .still; duration = 0 }
    }

    public mutating func reset() { self = Self() }
    private mutating func resetEpisode(at time: TimeInterval) {
        kind = .still; duration = 0; movementDuration = 0; slowDuration = 0; episodeAt = time; lastMovementAt = nil
    }
}
