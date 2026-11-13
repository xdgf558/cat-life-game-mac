import Foundation
import Testing
@testable import CatGameCore

@Suite("Purchases and room growth")
struct ShopAndHomeUpgradeTests {
    let now = Date(timeIntervalSince1970: 1_793_318_400)

    private func funded() -> GameSnapshot {
        var state = GameSnapshot.fresh(now: now)
        state.player.level = 4
        state.player.gold = 30_000
        return state
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CatShopHomeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func roomLevelData(_ data: Data, value: Any?) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var home = try #require(object["home"] as? [String: Any])
        if let value { home["roomLevel"] = value } else {
            home.removeValue(forKey: "roomLevel")
            object["schemaVersion"] = 14
        }
        object["home"] = home
        return try snapshotFixtureData(object, options: [.sortedKeys])
    }

    @Test func catalogHasFourPaidSlotsAndNeverAddsPaidItemsToTheStarterGift() throws {
        let state = GameSnapshot.fresh(now: now)
        let paid = try ShopCatalog.equipmentOffers.map { try #require(PlayerCatalog.item(id: $0.itemID)) }
        #expect(paid.count == 4 && Set(paid.map(\.slot)) == Set(EquipmentSlot.allCases))
        #expect(Set(paid.map(\.id)).isDisjoint(with: state.player.profile.ownedEquipmentIDs))
        #expect(state.player.profile.ownedEquipmentIDs == PlayerCatalog.starterEquipmentIDs)
        #expect(ShopCatalog.equipmentOffers.allSatisfy { $0.price > 0 && $0.unlockLevel >= 2 })
        #expect(ShopCatalog.furnitureOffers.map(\.kind) ==
            [.plant, .floorCushion, .bookcase, .rattanChair, .sideTable, .wallSunrise])
        #expect(ShopCatalog.furnitureOffers.allSatisfy { $0.maxOwned == 10 && !$0.assetName.isEmpty })
        #expect(HomeCatalog.all.map(\.capacity) == [9, 12, 16, 20, 24, 48, 56, 64])
        #expect(HomeCatalog.all.map(\.worldScale) == [1, 1.25, 1.5, 1.65, 1.8, 1.8, 1.9, 2])
        #expect(HomeCatalog.nextLevel(after: 8) == nil)
        #expect(HomeCatalog.nextLevel(after: Int.max) == nil)
        #expect(HomeCatalog.level(0) == nil && HomeCatalog.level(9) == nil)
    }

    @Test func equipmentPurchaseChargesExactlyOnceAndDoesNotAutomaticallyEquip() {
        for offer in ShopCatalog.equipmentOffers {
            var state = funded()
            state.player.level = offer.unlockLevel
            state.player.gold = offer.price
            let original = state
            let result = GameEngine.purchaseEquipment(&state, itemID: offer.itemID, now: now)
            #expect(result.succeeded && result.kind == .purchase && result.amount == offer.price)
            #expect(result.messageKey == "shop.equipmentPurchased")
            var expected = original
            expected.player.gold = 0
            expected.player.profile.ownedEquipmentIDs.append(offer.itemID)
            #expect(state == expected)
            #expect(GameEngine.purchaseEquipment(&state, itemID: offer.itemID, now: now).failure == .shopAlreadyOwned)
            #expect(state == expected)
        }
    }

    @Test func lockedUnknownAndUnaffordablePurchasesNeverChargeOrGrant() {
        var state = funded()
        let original = state
        #expect(GameEngine.purchaseEquipment(&state, itemID: "missing", now: now).failure == .shopItemMissing)
        #expect(GameEngine.purchaseEquipment(&state, itemID: "starter_cap", now: now).failure == .shopItemMissing)
        #expect(GameEngine.purchaseFurniture(&state, offerID: "missing", now: now).failure == .shopItemMissing)
        #expect(state == original)
        for offer in ShopCatalog.equipmentOffers {
            state = original
            state.player.level = offer.unlockLevel - 1
            let locked = state
            #expect(GameEngine.purchaseEquipment(&state, itemID: offer.itemID, now: now).failure == .shopLevelRequired)
            #expect(state == locked)
            state.player.level = offer.unlockLevel
            state.player.gold = offer.price - 1
            let poor = state
            #expect(GameEngine.purchaseEquipment(&state, itemID: offer.itemID, now: now).failure == .shopGoldRequired)
            #expect(state == poor)
        }
        for offer in ShopCatalog.furnitureOffers {
            state = original
            state.player.level = offer.unlockLevel - 1
            let locked = state
            #expect(GameEngine.purchaseFurniture(&state, offerID: offer.id, now: now).failure == .shopLevelRequired)
            #expect(state == locked)
            state.player.level = offer.unlockLevel
            state.player.gold = offer.price - 1
            let poor = state
            #expect(GameEngine.purchaseFurniture(&state, offerID: offer.id, now: now).failure == .shopGoldRequired)
            #expect(state == poor)
        }
    }

    @Test func furnitureInstancesAreUniqueStoredAndBoundedPerPurchasedSKU() {
        var state = funded()
        let original = state
        var spent = 0
        for offer in ShopCatalog.furnitureOffers {
            #expect(ShopCatalog.ownedFurnitureCount(offerID: offer.id, in: state.inventory.furniture) == 0)
            for count in 1...offer.maxOwned {
                let result = GameEngine.purchaseFurniture(&state, offerID: offer.id, now: now)
                #expect(result.succeeded && result.messageKey == "shop.furniturePurchased")
                spent += offer.price
                #expect(ShopCatalog.ownedFurnitureCount(offerID: offer.id, in: state.inventory.furniture) == count)
                #expect(state.inventory.furniture.last?.kind == offer.kind)
            }
            let full = state
            #expect(GameEngine.purchaseFurniture(&state, offerID: offer.id, now: now).failure == .shopFurnitureLimit)
            #expect(state == full)
        }
        #expect(state.player.gold == original.player.gold - spent)
        let expectedCount = original.inventory.furniture.count + ShopCatalog.furnitureOffers.reduce(0) { $0 + $1.maxOwned }
        #expect(state.inventory.furniture.count == expectedCount)
        #expect(Set(state.inventory.furniture.map(\.id)).count == expectedCount)
        #expect(Array(state.inventory.furniture.prefix(9)) == original.inventory.furniture)
        #expect(state.home == original.home && state.cats == original.cats)
        #expect(state.inventory.food == original.inventory.food && state.inventory.litter == original.inventory.litter)
        #expect(state.isValid)
    }

    @Test func anExistingInstanceIDIsNeverOverwritten() {
        var state = funded()
        let reserved = FurnitureItem(id: "shop_potted_plant_1", kind: .plant)
        state.inventory.furniture.append(reserved)
        #expect(GameEngine.purchaseFurniture(&state, offerID: "potted_plant", now: now).succeeded)
        #expect(state.inventory.furniture.contains(reserved))
        #expect(state.inventory.furniture.last?.id == "shop_potted_plant_2")
        #expect(ShopCatalog.ownedFurnitureCount(offerID: "potted_plant", in: state.inventory.furniture) == 2)
    }

    @Test func buyingAndEquippingAdvancedGearPreservesTheAlreadyCapturedShift() throws {
        var state = funded()
        #expect(GameEngine.equipStarterSet(&state, now: now).succeeded)
        #expect(GameEngine.startWork(&state, now: now).succeeded)
        let active = try #require(state.player.activeWork)
        let stamina = state.player.stamina
        let mood = state.player.mood
        for offer in ShopCatalog.equipmentOffers {
            #expect(GameEngine.purchaseEquipment(&state, itemID: offer.itemID, now: now).succeeded)
            #expect(GameEngine.equipItem(&state, itemID: offer.itemID, now: now).succeeded)
        }
        #expect(state.player.activeWork == active)
        #expect(state.player.stamina == stamina && state.player.mood == mood)
        let next = try #require(GameEngine.workQuote(for: state.player))
        #expect(next.durationSeconds == 84 && next.staminaCost == 8 && next.moodCost == 4)
        #expect(active.quote?.durationSeconds == 102)
        #expect(GameEngine.synchronize(&state, now: active.endsAt).succeeded)
        #expect(state.player.lastWorkResult?.goldReward == active.goldReward)
        #expect(state.player.lastWorkResult?.expReward == active.expReward)
    }

    @Test func upgradesAreSequentialAtomicAndKeepAllCoordinatesAndWorkTerms() throws {
        var state = funded()
        state.player.level = 16
        state.home.name = "My room"
        state.home.bowlPosition = .init(x: 0.65, y: 0.72)
        state.home.furniture[0].position = .init(x: 0.42, y: 0.45)
        #expect(GameEngine.startWork(&state, now: now).succeeded)
        let original = state
        #expect(GameEngine.upgradeHome(&state, toLevel: 3, now: now).failure == .homeUpgradeUnavailable)
        #expect(state == original)
        var expected = original
        for next in HomeCatalog.all.dropFirst() {
            let result = GameEngine.upgradeHome(&state, toLevel: next.level, now: now)
            #expect(result.succeeded && result.messageKey == "home.upgraded" && result.amount == next.upgradeCost)
            expected.player.gold -= next.upgradeCost
            expected.home.roomLevel = next.level
            if next.level >= 6 { expected.home.upperBowlPosition = HomeState.defaultBowlPosition }
            #expect(state == expected)
            #expect(GameEngine.upgradeHome(&state, toLevel: next.level, now: now).failure == .homeUpgradeUnavailable)
            #expect(state == expected)
        }
        #expect(GameEngine.upgradeHome(&state, toLevel: 9, now: now).failure == .homeUpgradeUnavailable)
        #expect(state == expected)
        #expect(state.player.activeWork == original.player.activeWork)
    }

    @Test func rejectedUpgradesDoNotChangeMoneyRoomOrRestAndExactCostIsEnough() {
        for next in HomeCatalog.all.dropFirst() {
            var state = funded()
            state.home = HomeState(roomLevel: next.level - 1)
            state.player.level = next.requiredPlayerLevel - 1
            let locked = state
            #expect(GameEngine.upgradeHome(&state, toLevel: next.level, now: now).failure == .homeLevelRequired)
            #expect(state == locked)
            state.player.level = next.requiredPlayerLevel
            state.player.gold = next.upgradeCost - 1
            let poor = state
            #expect(GameEngine.upgradeHome(&state, toLevel: next.level, now: now).failure == .shopGoldRequired)
            #expect(state == poor)
            state.player.gold += 1
            #expect(GameEngine.upgradeHome(&state, toLevel: next.level, now: now).succeeded)
            #expect(state.player.gold == 0 && state.home.roomLevel == next.level)
        }
        var state = funded()
        for target in [Int.min, -1, 0, 1, Int.max] {
            let original = state
            #expect(GameEngine.upgradeHome(&state, toLevel: target, now: now).failure == .homeUpgradeUnavailable)
            #expect(state == original)
        }
    }

    @Test func upgradingEndsCatRestWithoutReplayingItsRecovery() throws {
        var state = funded()
        state.cats[0].energy = 20
        #expect(GameEngine.startCatRest(&state, catID: "cat_001", furnitureID: "catBed",
                                        sessionID: "before-expansion", now: now).succeeded)
        let at = now.addingTimeInterval(5)
        var settled = state
        #expect(GameEngine.endCatRest(&settled, catID: "cat_001", sessionID: "before-expansion", now: at).succeeded)
        #expect(GameEngine.upgradeHome(&state, toLevel: 2, now: at).succeeded)
        #expect(state.cats == settled.cats)
        #expect(state.cats[0].activeRest == nil)
        #expect(state.home.furniture == settled.home.furniture)
    }

    @Test func roomLimitsGateOnlyNewPlacementsAndUnlockAfterAnUpgrade() {
        var state = funded()
        for _ in 0..<4 { #expect(GameEngine.purchaseFurniture(&state, offerID: "potted_plant", now: now).succeeded) }
        let purchased = Array(state.inventory.furniture.suffix(4))
        let additions = purchased.map { FurniturePlacement(itemID: $0.id, position: .init(x: 0.6, y: 0.7)) }
        let original = state
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: .init(x: 0.5, y: 0.6),
            furniture: original.home.furniture + additions.prefix(1), now: now).failure == .roomCapacityReached)
        #expect(state == original)
        #expect(GameEngine.upgradeHome(&state, toLevel: 2, now: now).succeeded)
        let upgraded = state
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
            furniture: original.home.furniture + additions, now: now).failure == .roomCapacityReached)
        #expect(state == upgraded)
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
            furniture: original.home.furniture + additions.prefix(3), now: now).succeeded)
        #expect(state.home.furniture.count == 12)
        #expect(state.inventory == original.inventory)
    }

    @Test func historicalOverCapacityLayoutsCanMoveAndShrinkWithoutBeingDiscarded() async throws {
        var state = funded()
        for index in 1...3 {
            let id = "legacy-extra-\(index)"
            state.inventory.furniture.append(.init(id: id, kind: .plant))
            state.home.furniture.append(.init(itemID: id, position: .init(x: 0.5, y: 0.65)))
        }
        #expect(state.isValid && state.home.furniture.count == 12 && state.home.roomLevel == 1)
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        try await repository.save(state)
        state = try await repository.loadOrCreate(now: now)
        var moved = Array(state.home.furniture.reversed())
        moved[0].position = .init(x: 0.55, y: 0.66)
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition, furniture: moved, now: now).succeeded)
        #expect(state.home.furniture == moved)
        #expect(GameEngine.purchaseFurniture(&state, offerID: "cozy_cushion", now: now).succeeded)
        let newest = state.inventory.furniture.last!.id
        let original = state
        var replacement = moved
        replacement[0] = .init(itemID: newest, position: .init(x: 0.4, y: 0.5))
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
                                         furniture: replacement, now: now).failure == .roomCapacityReached)
        #expect(state == original)
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
                                         furniture: Array(moved.dropLast()), now: now).succeeded)
        #expect(state.home.furniture.count == 11)
        #expect(GameEngine.setRoomLayout(&state, bowlPosition: state.home.bowlPosition,
                                         furniture: Array(replacement.prefix(9)), now: now).succeeded)
        #expect(state.home.furniture.contains { $0.itemID == newest })
        #expect(state.inventory == original.inventory)
    }

    @Test func missingRoomLevelMigratesInPlaceAndPurchasesSurviveRealRepositoryReload() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var original = funded()
        original.player.profile.name = "Milo"
        original.player.profile.avatarID = "female_forest"
        original.home.name = "Quiet home"
        original.inventory.food = 17
        original.settings.language = .english
        #expect(GameEngine.startWork(&original, now: now).succeeded)
        try await repository.save(original)
        let legacy = try roomLevelData(Data(contentsOf: repository.saveURL), value: nil)
        try legacy.write(to: repository.saveURL)
        var migrated = try await repository.loadOrCreate(now: now)
        #expect(migrated == original && migrated.home.roomLevel == 1 && migrated.schemaVersion == GameSnapshot.currentSchemaVersion)
        #expect(try Data(contentsOf: repository.saveURL) == legacy)
        #expect(GameEngine.purchaseEquipment(&migrated, itemID: "advanced_cap", now: now).succeeded)
        #expect(GameEngine.equipItem(&migrated, itemID: "advanced_cap", now: now).succeeded)
        #expect(GameEngine.purchaseFurniture(&migrated, offerID: "potted_plant", now: now).succeeded)
        #expect(GameEngine.purchaseFurniture(&migrated, offerID: "potted_plant", now: now).succeeded)
        #expect(GameEngine.upgradeHome(&migrated, toLevel: 2, now: now).succeeded)
        try await repository.save(migrated)
        let reopened = try await FileSaveRepository(directory: folder).loadOrCreate(now: now)
        #expect(reopened == migrated)
        #expect(reopened.player.activeWork == original.player.activeWork)
        #expect(reopened.home.furniture == original.home.furniture && reopened.home.bowlPosition == original.home.bowlPosition)
        #expect(reopened.settings == original.settings && reopened.cats == original.cats)
        #expect(ShopCatalog.ownedFurnitureCount(offerID: "potted_plant", in: reopened.inventory.furniture) == 2)
    }

    @Test func explicitInvalidRoomLevelsAreRejectedAndCannotOverwritePrimaryOrBackup() async throws {
        let original = funded()
        let encoded = try JSONEncoder().encode(original)
        for badValue: Any in [NSNull(), "2", 0, -1, 9, Int.max, 1.5] {
            do {
                let decoded = try JSONDecoder().decode(GameSnapshot.self, from: roomLevelData(encoded, value: badValue))
                #expect(!decoded.isValid)
            } catch { /* Invalid types and null must fail decoding. */ }
        }
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        try await repository.save(original, now: now)
        var current = original
        current.inventory.food += 1
        try await repository.save(current, now: now)
        let primary = try Data(contentsOf: repository.saveURL)
        let backup = try Data(contentsOf: repository.backupURL)
        for invalid in [0, -1, 9, Int.max] {
            var candidate = current
            candidate.home.roomLevel = invalid
            await #expect(throws: SaveRepositoryError.invalidSnapshot) { try await repository.save(candidate, now: now) }
            #expect(try Data(contentsOf: repository.saveURL) == primary)
            #expect(try Data(contentsOf: repository.backupURL) == backup)
        }
    }

    @Test func failedCommerceRetainsElapsedWorkSettlementButNoPurchaseSideEffects() {
        let actions: [(inout GameSnapshot, Date) -> ActionOutcome] = [
            { GameEngine.purchaseEquipment(&$0, itemID: "advanced_cap", now: $1) },
            { GameEngine.purchaseFurniture(&$0, offerID: "potted_plant", now: $1) },
            { GameEngine.upgradeHome(&$0, toLevel: 2, now: $1) }
        ]
        for action in actions {
            var state = funded()
            state.player.gold = 0
            #expect(GameEngine.startWork(&state, now: now).succeeded)
            let deadline = state.player.activeWork!.endsAt
            var settled = state
            #expect(GameEngine.synchronize(&settled, now: deadline).succeeded)
            #expect(action(&state, deadline).failure == .shopGoldRequired)
            #expect(state == settled)
            #expect(state.player.lastWorkResult?.goldReward == 60)
        }
    }
}
