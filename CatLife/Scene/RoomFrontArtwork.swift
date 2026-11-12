import SpriteKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import CatGameCore

/// Front-facing architecture uses the existing textures, with no floating cutaway outline.
@MainActor
final class RoomFrontArtwork: SKNode {
    private(set) var contentBounds = CGRect.zero
    private(set) var windowGroundAnchor: CGPoint?
    private lazy var woodTexture = SKTexture(imageNamed: "room-floor-wood")
    private lazy var plasterTexture = SKTexture(imageNamed: "room-wall-plaster")
    private lazy var windowTexture = SKTexture(imageNamed: "room-window-arched")

    override init() { super.init(); name = "room-front-artwork" }
    required init?(coder: NSCoder) { fatalError("RoomFrontArtwork is created in code") }

    func configure(projection: RoomViewProjection, floor homeFloor: HomeFloor) {
        removeAllChildren()
        windowGroundAnchor = nil
        guard let front = projection.frontFloor else { contentBounds = .zero; return }
        let floor = front.destination
        let height = projection.wallHeight
        contentBounds = CGRect(x: floor.minX, y: floor.minY, width: floor.width, height: floor.height + height)
        let unit = floor.width
        // The bleed sits behind the safe interaction area; it keeps the stage covered while zooming or panning.
        let wall = SKSpriteNode(texture: plasterTexture)
        wall.name = "room-shell-far-wall"
        wall.anchorPoint = CGPoint(x: 0.5, y: 0)
        wall.position = CGPoint(x: floor.midX, y: floor.maxY)
        wall.size = CGSize(width: unit * 5, height: max(height * 4, unit * 3))
        wall.color = homeFloor == .upper ? UIColor(red: 0.87, green: 0.79, blue: 0.93, alpha: 1)
            : UIColor(red: 0.98, green: 0.89, blue: 0.71, alpha: 1)
        wall.colorBlendFactor = homeFloor == .upper ? 0.6 : 0.15
        wall.zPosition = -40
        addChild(wall)

        // Tiles share one texture and fixed world anchors, so grain does not swim when the camera moves.
        for row in 0..<3 {
            for column in -1...1 {
                let tile = SKSpriteNode(texture: woodTexture)
                tile.name = row == 0 && column == 0 ? "room-shell-floor-texture" : "room-front-floor-tile"
                tile.anchorPoint = CGPoint(x: 0, y: 1)
                tile.position = CGPoint(x: floor.minX + CGFloat(column) * unit, y: floor.maxY - CGFloat(row) * unit)
                tile.size = CGSize(width: unit + 0.5, height: unit + 0.5)
                tile.color = .black
                tile.colorBlendFactor = homeFloor == .upper ? 0.12 : 0
                tile.zPosition = -14
                addChild(tile)
            }
        }
        let baseboard = SKSpriteNode(color: UIColor(red: 0.68, green: 0.72, blue: 0.50, alpha: 1),
                                     size: CGSize(width: unit * 5, height: max(3, unit * 0.016)))
        baseboard.position = CGPoint(x: floor.midX, y: floor.maxY + baseboard.size.height / 2)
        baseboard.zPosition = -12
        baseboard.name = "room-front-baseboard"
        addChild(baseboard)
        let trim = SKSpriteNode(color: UIColor(red: 0.99, green: 0.94, blue: 0.81, alpha: 1),
                               size: CGSize(width: unit * 5, height: max(2, unit * 0.008)))
        trim.position = CGPoint(x: floor.midX, y: floor.maxY + baseboard.size.height + trim.size.height / 2)
        trim.zPosition = -11
        addChild(trim)

        let windowHeight = height * 0.84
        let imageSize = windowTexture.size()
        let window = SKSpriteNode(texture: windowTexture)
        window.name = "room-shell-window"
        window.size = CGSize(width: windowHeight * imageSize.width / max(1, imageSize.height), height: windowHeight)
        let windowX = floor.minX + unit * (homeFloor == .upper ? 0.80 : 0.18)
        window.position = CGPoint(x: windowX, y: floor.maxY + height * 0.51)
        window.zPosition = -28
        addChild(window)
        windowGroundAnchor = front.unproject(CGPoint(x: windowX, y: floor.maxY))
    }
}
