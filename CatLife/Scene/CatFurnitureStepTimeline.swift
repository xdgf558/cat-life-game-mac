import Foundation
import CoreGraphics

enum CatFurnitureStepPhase: String, Sendable {
    case none, reaching, frontPaws, lifting, supported, frontPawsDown, lowering, rearPawsDown
}

struct CatFurnitureStepKeyframe: Sendable {
    let frame: Int
    let phase: CatFurnitureStepPhase
    let travel: CGFloat
    let progress: CGFloat
    let elevation: CGFloat
    let shadowElevation: CGFloat
    let duration: TimeInterval
}


/// Calibrated pose timing and support heights; the actor owns nodes, cancellation,
/// and interpolation so extracting these values cannot create a second animator.
enum CatFurnitureStepTimeline {
    static let defaultContactProgress: CGFloat = 0.14
    // Keep most of the entry after the paws have caught the rim. A larger
    // required reach is not a supported step and must remain blocked.
    static let maximumContactProgress: CGFloat = 0.40

    static func ascending(elevation: CGFloat,
                          contactProgress: CGFloat = defaultContactProgress) -> [CatFurnitureStepKeyframe] {
        // Most translation happens only after the front paws have caught the
        // edge. Each stop is a weight transfer, not another ground walk cycle.
        let keys: [CatFurnitureStepKeyframe] = [
            .init(frame: 0, phase: .reaching, travel: 0, progress: 0,
                  elevation: 0, shadowElevation: 0, duration: 0.12),
            .init(frame: 1, phase: .reaching, travel: 0.025, progress: 0.025,
                  elevation: 0, shadowElevation: 0, duration: 0.28),
            .init(frame: 2, phase: .frontPaws, travel: contactProgress, progress: contactProgress,
                  elevation: 0, shadowElevation: 0, duration: 0.30),
            .init(frame: 2, phase: .frontPaws, travel: contactProgress, progress: contactProgress,
                  elevation: 0, shadowElevation: 0, duration: 0.24),
            .init(frame: 3, phase: .lifting, travel: 0.78, progress: 0.78,
                  elevation: elevation, shadowElevation: elevation * 0.78, duration: 0.65),
            .init(frame: 4, phase: .lifting, travel: 1, progress: 1,
                  elevation: elevation, shadowElevation: elevation, duration: 0.45),
            .init(frame: 4, phase: .supported, travel: 1, progress: 1,
                  elevation: elevation, shadowElevation: elevation, duration: 0.22)
        ]
        return keys
    }

    static func descending(elevation: CGFloat) -> [CatFurnitureStepKeyframe] {
        let keys: [CatFurnitureStepKeyframe] = [
            .init(frame: 4, phase: .supported, travel: 0, progress: 1,
                  elevation: elevation, shadowElevation: elevation, duration: 0.24),
            .init(frame: 5, phase: .frontPawsDown, travel: 0.12, progress: 0.88,
                  elevation: elevation, shadowElevation: elevation, duration: 0.36),
            .init(frame: 5, phase: .frontPawsDown, travel: 0.12, progress: 0.88,
                  elevation: elevation, shadowElevation: elevation, duration: 0.18),
            .init(frame: 6, phase: .lowering, travel: 0.78, progress: 0.22,
                  elevation: elevation * 0.12, shadowElevation: elevation * 0.12, duration: 0.64),
            .init(frame: 7, phase: .rearPawsDown, travel: 1, progress: 0,
                  elevation: 0, shadowElevation: 0, duration: 0.34),
            .init(frame: 7, phase: .rearPawsDown, travel: 1, progress: 0,
                  elevation: 0, shadowElevation: 0, duration: 0.15)
        ]
        return keys
    }

    static func retreating(startingFrame: Int, progress: CGFloat, elevation: CGFloat,
                           shadowElevation: CGFloat) -> [CatFurnitureStepKeyframe] {
        // This is a withdrawal of the entry just attained, not a turn followed
        // by a full descent from an imaginary completed visit. In particular,
        // the first key preserves the interrupted frame, position and height.
        let frame = min(4, max(0, startingFrame))
        var keys = [CatFurnitureStepKeyframe(frame: frame, phase: .rearPawsDown, travel: 0, progress: progress,
                                elevation: elevation, shadowElevation: shadowElevation, duration: 0.08)]
        if frame >= 3 {
            keys.append(.init(frame: 3, phase: .rearPawsDown, travel: 0.42, progress: progress * 0.58,
                              elevation: 0, shadowElevation: 0, duration: 0.38))
        }
        if frame >= 2 {
            keys.append(.init(frame: 2, phase: .rearPawsDown, travel: 0.68, progress: progress * 0.32,
                              elevation: 0, shadowElevation: 0, duration: 0.24))
        }
        if frame >= 1 {
            keys.append(.init(frame: 1, phase: .rearPawsDown, travel: 0.86, progress: progress * 0.14,
                              elevation: 0, shadowElevation: 0, duration: 0.24))
        }
        keys.append(.init(frame: 0, phase: .rearPawsDown, travel: 1, progress: 0,
                          elevation: 0, shadowElevation: 0, duration: 0.24))
        return keys
    }

    static func stationary(from frame: Int) -> [CatFurnitureStepKeyframe] {
        let keys = [CatFurnitureStepKeyframe(frame: min(1, max(0, frame)), phase: .reaching, travel: 0,
                                progress: 0, elevation: 0, shadowElevation: 0, duration: 0.18),
                    CatFurnitureStepKeyframe(frame: 0, phase: .rearPawsDown, travel: 0,
                                 progress: 0, elevation: 0, shadowElevation: 0, duration: 0.12)]
        return keys
    }
}
