import Foundation
import Testing
@testable import CatGameCore

@Suite("Mac capacity is an explicit runtime policy, not a save format")
struct HomeLayoutRulesTests {
    let now = Date(timeIntervalSince1970: 1_793_600_000)

    private func state(level: Int = 1) -> GameSnapshot {
        var value = GameSnapshot.fresh(now: now)
        value.home = HomeState(roomLevel: level)
        return value
    }

    private func stored(_ count: Int, floor: HomeFloor, in state: inout GameSnapshot) -> [FurniturePlacement] {
        (0..<count).map { index in
            let id = "capacity-\(floor.rawValue)-\(index)"
            state.inventory.furniture.append(FurnitureItem(id: id, kind: .plant))
            return FurniturePlacement(itemID: id, position: .init(x: 0.5, y: 0.7), floor: floor)
        }
    }

    @Test func macAddsSevenSlotsPerUnlockedFloorWithoutChangingStandardLimits() {
        #expect(HomeCatalog.all.map(\.capacity) == [9, 12, 16, 20, 24, 48, 56, 64])
        #expect(HomeCatalog.all.map { $0.floorCapacity(using: .macDesktop) } == [16, 19, 23, 27, 31, 31, 35, 39])
        #expect(HomeCatalog.all.map { $0.capacity(using: .macDesktop) } == [16, 19, 23, 27, 31, 62, 70, 78])
        for room in HomeCatalog.all {
            #expect(room.capacity(using: .standard) == room.capacity)
            #expect(room.capacity(on: .ground) == room.floorCapacity)
            #expect(room.capacity(on: .upper, rules: .macDesktop) == (room.level < 6 ? 0 : room.floorCapacity + 7))
        }
    }

    @Test func firstMacRoomAllowsSixteenButStandardCallerStillAllowsNine() {
        var value = state()
        let additional = stored(8, floor: .ground, in: &value)
        let proposed = value.home.furniture + Array(additional.prefix(7))
        let before = value
        let standard = GameEngine.setRoomLayout(&value, bowlPosition: value.home.bowlPosition,
                                                 furniture: proposed, now: now)
        #expect(standard.failure == .roomCapacityReached && standard.amount == 9)
        #expect(value == before)
        #expect(GameEngine.setRoomLayout(&value, bowlPosition: value.home.bowlPosition,
            furniture: proposed, rules: .macDesktop, now: now).succeeded)
        #expect(value.home.furniture.count == 16)
        let full = value
        let denied = GameEngine.setRoomLayout(&value, bowlPosition: value.home.bowlPosition,
            furniture: proposed + [additional[7]], rules: .macDesktop, now: now)
        #expect(denied.failure == .roomCapacityReached && denied.amount == 16)
        #expect(value == full && value.player.gold == before.player.gold)
    }

    @Test func macSecondFloorHasItsOwnLimitAndNeverUnlocksEarly() {
        var locked = state(level: 5)
        let upstairs = stored(1, floor: .upper, in: &locked)
        let original = locked
        #expect(GameEngine.setRoomLayout(&locked, bowlPosition: .init(x: 0.5, y: 0.8),
            furniture: upstairs, floor: .upper, rules: .macDesktop, now: now).failure == .roomInvalidFurnitureLayout)
        #expect(locked == original)

        var value = state(level: 6)
        let extraGround = stored(22, floor: .ground, in: &value)
        let upper = stored(32, floor: .upper, in: &value)
        #expect(GameEngine.setRoomLayout(&value, bowlPosition: value.home.bowlPosition,
            furniture: value.home.furniture + extraGround, rules: .macDesktop, now: now).succeeded)
        let ground = value.home.furniture
        let denied = GameEngine.setRoomLayout(&value, bowlPosition: .init(x: 0.5, y: 0.8),
            furniture: upper, floor: .upper, rules: .macDesktop, now: now)
        #expect(denied.failure == .roomCapacityReached && denied.amount == 31)
        #expect(value.home.furniture == ground && value.home.placements(on: .upper).isEmpty)
        #expect(GameEngine.setRoomLayout(&value, bowlPosition: .init(x: 0.5, y: 0.8),
            furniture: Array(upper.prefix(31)), floor: .upper, rules: .macDesktop, now: now).succeeded)
        #expect(value.home.furniture.count == 62 && value.isValid)
    }

    @Test func macBackupStillDecodesAndCanBeRearrangedByStandardRulesWithoutAddingItems() throws {
        var value = state()
        let additional = stored(8, floor: .ground, in: &value)
        #expect(GameEngine.setRoomLayout(&value, bowlPosition: value.home.bowlPosition,
            furniture: value.home.furniture + Array(additional.prefix(7)), rules: .macDesktop, now: now).succeeded)
        let data = try NativeSaveTransfer.encode(snapshot: value, exportedAt: now)
        var imported = try NativeSaveTransfer.decode(data, now: now).snapshot
        #expect(imported == value && imported.schemaVersion == GameSnapshot.currentSchemaVersion)
        var moved = imported.home.furniture
        moved[0].position = .init(x: 0.4, y: 0.7)
        #expect(GameEngine.setRoomLayout(&imported, bowlPosition: imported.home.bowlPosition,
            furniture: moved, now: now).succeeded, "An imported Mac layout can still be moved or stored on iOS.")
        let before = imported
        #expect(GameEngine.setRoomLayout(&imported, bowlPosition: imported.home.bowlPosition,
            furniture: moved + [additional[7]], now: now).failure == .roomCapacityReached)
        #expect(imported == before)
        #expect(GameEngine.setRoomLayout(&imported, bowlPosition: imported.home.bowlPosition,
            furniture: Array(moved.prefix(9)), now: now).succeeded)
        #expect(imported.home.furniture.count == 9 && imported.isValid)
    }
}
