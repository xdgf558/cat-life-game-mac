import Foundation
import CoreGraphics

/// Physical sprites and saved positions belong to the world. Camera scaling
/// changes only their projection into the viewport.
struct RoomWorldGeometry: Sendable {
    let viewportSize: CGSize
    let worldScale: CGFloat

    var worldSize: CGSize {
        CGSize(width: viewportSize.width * worldScale, height: viewportSize.height * worldScale)
    }

}
