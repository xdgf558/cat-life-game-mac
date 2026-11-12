import CoreGraphics
import Foundation

/// Includes walking, eating and rest frames: HUD avoidance never pauses with care.
struct CatVisualFrameSampler {
    private var sampledAt = -Double.infinity
    private(set) var frame: CGRect?

    mutating func sample(_ proposed: CGRect?, at time: TimeInterval) -> Bool {
        guard time < sampledAt || time - sampledAt >= 0.1 else { return false }
        sampledAt = time
        if let frame, let proposed {
            guard abs(frame.minX - proposed.minX) > 1 || abs(frame.minY - proposed.minY) > 1
                    || abs(frame.width - proposed.width) > 1 || abs(frame.height - proposed.height) > 1 else { return false }
        } else if frame == nil, proposed == nil { return false }
        frame = proposed
        return true
    }
}
