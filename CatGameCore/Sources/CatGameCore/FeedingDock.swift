import Foundation
import CoreGraphics

/// A fixed-facing meal dock in room coordinates (+y is up). Walking and room
/// placement still use their normal footprint; only the final approach and
/// backward exit use this offset rectangle of ground-contacting paws.
public struct FeedingDock: Sendable {
    public let eatingPoint: CGPoint
    public let footprint: CGSize

    private let bowlSize: CGSize
    private let bowlCenter: CGPoint
    private let footCenterOffset: CGPoint

    /// Landmarks are pixels in the untrimmed 1374 × 1145 bowl-full.png, measured
    /// from its top left. Rear food targets (610,315)/(764,315) keep the feet
    /// behind the solid bowl while the head reaches over its rim. The food
    /// ellipse is centered at (687,415), with radii (250,135).
    ///
    /// Registered cat-meal frames 2/3 have mouth offsets (.3791C,.1472C) and
    /// (.3084C,.1472C); their mean is (.34375C,.1472C). These measurements use
    /// frame 0's 356-pixel reference height and a 1.20 × .91 display scale.
    public init(catWidth: CGFloat, bowlSize: CGSize, bowlCenter: CGPoint, facing: CGFloat) {
        let direction: CGFloat = facing < 0 ? -1 : 1
        self.bowlSize = bowlSize
        self.bowlCenter = bowlCenter
        footprint = CGSize(width: 1.17 * catWidth, height: 0.14 * catWidth)
        footCenterOffset = CGPoint(x: -0.135 * direction * catWidth, y: 0.07 * catWidth)

        let foodPixelX: CGFloat = direction > 0 ? 610 : 764
        let foodTarget = CGPoint(x: bowlCenter.x + (foodPixelX / 1374 - 0.5) * bowlSize.width,
                                 y: bowlCenter.y + (0.5 - 315.0 / 1145) * bowlSize.height)
        eatingPoint = CGPoint(x: foodTarget.x - direction * 0.34375 * catWidth,
                              y: foodTarget.y - 0.1472 * catWidth)
    }

    /// Pass this center (not the actor's foot anchor) to a RoomNavigation whose
    /// footprint is `footprint`. The right-facing paw bounds are x[-.72,+.45]C
    /// and y[0,+.14]C; facing left mirrors their horizontal bias.
    public func footCenter(at actorPoint: CGPoint) -> CGPoint {
        CGPoint(x: actorPoint.x + footCenterOffset.x, y: actorPoint.y + footCenterOffset.y)
    }

    public func feetRect(at actorPoint: CGPoint) -> CGRect {
        let center = footCenter(at: actorPoint)
        return CGRect(x: center.x - footprint.width / 2, y: center.y - footprint.height / 2,
                      width: footprint.width, height: footprint.height)
    }

    /// Checks a mouth point against the visible food surface, not the entire
    /// head or bowl texture. Transparent margins and the bowl's body do not count.
    public func containsFoodContact(_ point: CGPoint) -> Bool {
        guard point.x.isFinite, point.y.isFinite, bowlCenter.x.isFinite, bowlCenter.y.isFinite,
              bowlSize.width.isFinite, bowlSize.height.isFinite,
              bowlSize.width > 0, bowlSize.height > 0 else { return false }
        let rawX = 687 + (point.x - bowlCenter.x) / bowlSize.width * 1374
        let rawY = 1145.0 / 2 - (point.y - bowlCenter.y) / bowlSize.height * 1145
        let x = (rawX - 687) / 250
        let y = (rawY - 415) / 135
        return x * x + y * y <= 1
    }
}
