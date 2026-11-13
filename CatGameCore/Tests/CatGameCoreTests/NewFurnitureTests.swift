import Foundation
import Testing
@testable import CatGameCore

@Suite("New shop furniture stays owned across arrangement and storage")
struct NewFurnitureTests {
    private let now = Date(timeIntervalSince1970: 1_793_318_400)

    @Test func eachNewPieceCanBePurchasedPlacedStoredAndReloadedWithoutChangingStarterRoom() throws {
        let newKinds: [FurnitureKind] = [.bookcase, .rattanChair, .sideTable, .wallSunrise]
        for kind in newKinds {
            var state = GameSnapshot.fresh(now: now)
            let original = state
            state.player.level = 3
            state.player.gold = 1_000
            let offer = try #require(ShopCatalog.furnitureOffers.first { $0.kind == kind })
            #expect(GameEngine.purchaseFurniture(&state, offerID: offer.id, now: now).succeeded)
            #expect(state.home == original.home)
            #expect(state.inventory.furniture.prefix(original.inventory.furniture.count) == original.inventory.furniture[...])
            var item = try #require(state.inventory.furniture.last)
            #expect(item.kind == kind)
            #expect(GameEngine.catRestDuration(for: kind) == nil)
            let position = NormalizedPoint(x: 0.60, y: FurnitureCatalog.metadata(for: kind).isWall ? 0.27 : 0.65)
            let positions = [FurniturePlacement(itemID: item.id, position: position)]
            let direction: FurnitureOrientation = kind.supportsRotation ? .left : .front
            #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
                furniture: positions, orientations: [item.id: direction], now: now).succeeded)
            #expect(state.home.furniture == positions)
            #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
                furniture: [], now: now).succeeded)
            item.orientation = direction
            #expect(state.inventory.furniture.contains(item))
            let loaded = try JSONDecoder().decode(GameSnapshot.self, from: JSONEncoder().encode(state))
            #expect(loaded == state && loaded.isValid)
            #expect(loaded.inventory.furniture.contains(item) && loaded.home.furniture.isEmpty)
        }
    }

    @Test func sunrisePictureIsWallOnlyAndRejectsRotation() throws {
        #expect(FurnitureCatalog.metadata(for: .wallSunrise).isWall)
        #expect(!FurnitureKind.wallSunrise.supportsRotation)
        let invalid = FurnitureItem(id: "sunrise", kind: .wallSunrise, orientation: .left)
        #expect(throws: SaveRepositoryError.invalidSnapshot) {
            try JSONDecoder().decode(FurnitureItem.self, from: JSONEncoder().encode(invalid))
        }
    }
}
