import Foundation
import Testing
@testable import CatGameCore

@Suite("Player appearances, equipment and captured work terms")
struct PlayerEquipmentTests {
    let now = Date(timeIntervalSince1970: 1_793_318_400)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CatPlayerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func modifiedData(_ data: Data, _ edit: (inout [String: Any]) throws -> Void) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try edit(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func revisedQuote(_ original: WorkQuote, _ edit: (inout [String: Any]) throws -> Void) throws -> WorkQuote {
        try JSONDecoder().decode(WorkQuote.self, from: modifiedData(JSONEncoder().encode(original), edit))
    }

    @Test func catalogContainsSixCosmeticAvatarsAndOneStarterItemPerSlot() throws {
        #expect(PlayerCatalog.avatars.map(\.id) == ["male_sunny", "male_forest", "male_scholarly",
            "female_sunny", "female_forest", "female_scholarly"])
        #expect(PlayerCatalog.avatars.filter { $0.gender == .male }.count == 3)
        #expect(PlayerCatalog.avatars.filter { $0.gender == .female }.count == 3)
        #expect(Set(PlayerCatalog.equipment.map(\.slot)) == Set(EquipmentSlot.allCases))
        let starters = PlayerCatalog.starterEquipmentIDs.compactMap { PlayerCatalog.item(id: $0) }
        #expect(starters.count == 4 && Set(starters.map(\.slot)) == Set(EquipmentSlot.allCases))
        var state = GameSnapshot.fresh(now: now)
        #expect(state.player.profile.avatarID == nil && state.player.profile.equipped.isEmpty)
        _ = GameEngine.equipStarterSet(&state, now: now)
        let terms = try #require(GameEngine.workQuote(for: state.player))
        let nonAppearance = state
        for avatar in PlayerCatalog.avatars {
            #expect(GameEngine.selectAvatar(&state, avatarID: avatar.id, now: now).succeeded)
            #expect(GameEngine.workQuote(for: state.player) == terms)
            #expect(state.player.gold == nonAppearance.player.gold && state.inventory == nonAppearance.inventory)
            #expect(state.player.stamina == 80 && state.player.mood == 80)
        }
    }

    @Test func missingLegacyProfileGiftsOnceAndPreservesEveryExistingField() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var original = GameSnapshot.fresh(now: now)
        original.player.gold = 912
        original.player.level = 4
        original.player.exp = 39
        original.player.completedWorkCount = 27
        original.inventory.food = 11
        original.home.name = "Quiet home"
        original.settings.language = .traditionalChinese
        original.cats.append(CatState(id: "generated-cat", name: "Clover", now: now))
        try await repository.save(original)
        let legacy = try modifiedData(Data(contentsOf: repository.saveURL)) { object in
            var player = try #require(object["player"] as? [String: Any])
            player.removeValue(forKey: "profile")
            object["player"] = player
        }
        try legacy.write(to: repository.saveURL)
        let migrated = try await repository.loadOrCreate(now: now)
        #expect(migrated == original)
        #expect(migrated.player.profile.ownedEquipmentIDs == PlayerCatalog.starterEquipmentIDs)
        #expect(migrated.player.profile.equipped.isEmpty)
        #expect(try Data(contentsOf: repository.saveURL) == legacy)
        try await repository.save(migrated)
        for _ in 0..<3 {
            #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == migrated)
        }
    }

    @Test func explicitEmptyOwnershipNeverRegrantsStarterItemsOnReload() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        state.player.profile.ownedEquipmentIDs = []
        try await repository.save(state)
        for _ in 0..<3 {
            var restored = try await FileSaveRepository(directory: folder).loadOrCreate(now: now)
            #expect(restored.player.profile.ownedEquipmentIDs.isEmpty)
            #expect(GameEngine.equipStarterSet(&restored, now: now).messageKey == "equipment.notOwned")
            #expect(restored == state)
            try await repository.save(restored)
        }
    }

    @Test func selectingEquippingAndRemovingSurviveRepositoryReloadWithoutResourceCosts() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        let resources = state
        #expect(GameEngine.selectAvatar(&state, avatarID: "female_forest", now: now).succeeded)
        for item in PlayerCatalog.starterEquipmentIDs.compactMap({ PlayerCatalog.item(id: $0) }) {
            #expect(GameEngine.equipItem(&state, itemID: item.id, now: now).succeeded)
            #expect(state.player.profile.equipped[item.slot] == item.id)
        }
        let dressed = state
        #expect(GameEngine.equipStarterSet(&state, now: now).succeeded)
        #expect(state == dressed)
        try await repository.save(state)
        var restored = try await FileSaveRepository(directory: folder).loadOrCreate(now: now)
        #expect(restored == state)
        #expect(GameEngine.unequipSlot(&restored, slot: .head, now: now).succeeded)
        #expect(restored.player.profile.equipped[.head] == nil)
        #expect(restored.player.profile.ownedEquipmentIDs == PlayerCatalog.starterEquipmentIDs)
        #expect(restored.player.gold == resources.player.gold && restored.inventory == resources.inventory)
        #expect(restored.player.stamina == resources.player.stamina && restored.player.mood == resources.player.mood)
        try await repository.save(restored)
        #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == restored)
    }

    @Test func eachItemAffectsOnlyItsOwnDeclaredWorkCategory() throws {
        for item in PlayerCatalog.starterEquipmentIDs.compactMap({ PlayerCatalog.item(id: $0) }) {
            var state = GameSnapshot.fresh(now: now)
            #expect(GameEngine.equipItem(&state, itemID: item.id, now: now).succeeded)
            let quote = try #require(GameEngine.workQuote(for: state.player))
            switch item.id {
            case "starter_cap":
                #expect(quote.durationSeconds == 120 && quote.staminaCost == 10 && quote.moodCost == 4)
            case "starter_jacket":
                #expect(quote.durationSeconds == 120 && quote.staminaCost == 9 && quote.moodCost == 5)
            case "starter_sneakers":
                #expect(quote.durationSeconds == 108 && quote.staminaCost == 10 && quote.moodCost == 5)
            case "starter_charm":
                #expect(quote.durationSeconds == 114 && quote.staminaCost == 10 && quote.moodCost == 5)
            default: Issue.record("Unexpected starter item")
            }
            #expect(quote.equipmentIDs == [item.id])
        }
    }

    @Test func starterOutfitUsesExactRoundedCostsAndDeadlinesForEveryCareer() throws {
        let expected = [(102, 9, 4), (153, 13, 7), (204, 17, 10), (510, 26, 10),
                        (1530, 43, 16), (2295, 56, 20), (3060, 68, 23)]
        try #require(expected.count == WorkCatalog.all.count)
        for (index, job) in WorkCatalog.all.enumerated() {
            var state = GameSnapshot.fresh(now: now)
            state.player.level = job.unlockLevel
            state.player.stamina = 100
            state.player.mood = 100
            _ = GameEngine.equipStarterSet(&state, now: now)
            let quote = try #require(GameEngine.workQuote(for: state.player, jobID: job.id))
            #expect(quote.durationSeconds == expected[index].0)
            #expect(quote.staminaCost == expected[index].1)
            #expect(quote.moodCost == expected[index].2)
            #expect(quote.bonuses == EquipmentBonuses(durationReductionPercent: 15,
                staminaReductionPercent: 15, moodReductionPercent: 20))
            #expect(GameEngine.startWork(&state, jobID: job.id, now: now).succeeded)
            let work = try #require(state.player.activeWork)
            #expect(work.quote == quote)
            #expect(work.endsAt == now.addingTimeInterval(Double(quote.durationSeconds)))
            #expect(state.player.stamina == 100 - quote.staminaCost)
            #expect(state.player.mood == 100 - quote.moodCost)
            let alreadyStarted = state
            #expect(!GameEngine.startWork(&state, jobID: job.id, now: now).succeeded)
            #expect(state == alreadyStarted)
            _ = GameEngine.synchronize(&state, now: work.endsAt.addingTimeInterval(-0.1))
            #expect(state.player.gold == 200)
            #expect(GameEngine.synchronize(&state, now: work.endsAt).kind == .workFinished)
            #expect(state.player.gold == 200 + job.goldReward && state.player.exp == job.expReward)
        }
    }

    @Test func workStaminaGateUsesDiscountedCostAndClampsLowMood() {
        var state = GameSnapshot.fresh(now: now)
        _ = GameEngine.equipStarterSet(&state, now: now)
        state.player.stamina = 8
        let before = state
        #expect(GameEngine.startWork(&state, now: now).messageKey == "work.staminaRequired")
        #expect(state == before)
        state.player.stamina = 9
        state.player.mood = 1
        #expect(GameEngine.startWork(&state, now: now).succeeded)
        #expect(state.player.stamina == 0 && state.player.mood == 0)
        #expect(state.player.activeWork?.quote?.moodCost == 4)
    }

    @Test func changingAnActiveOutfitDoesNotRewriteCapturedTermsOrChargeAgain() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        _ = GameEngine.equipStarterSet(&state, now: now)
        _ = GameEngine.startWork(&state, now: now)
        let work = try #require(state.player.activeWork)
        for slot in EquipmentSlot.allCases { _ = GameEngine.unequipSlot(&state, slot: slot, now: now.addingTimeInterval(30)) }
        _ = GameEngine.selectAvatar(&state, avatarID: "male_scholarly", now: now.addingTimeInterval(30))
        #expect(state.player.activeWork == work)
        #expect(state.player.stamina == 71 && state.player.mood == 76)
        #expect(GameEngine.workQuote(for: state.player)?.durationSeconds == 120)
        try await repository.save(state)
        var loaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: now.addingTimeInterval(102))
        #expect(loaded.player.activeWork == work)
        _ = GameEngine.synchronize(&loaded, now: work.endsAt)
        #expect(loaded.player.gold == 260 && loaded.player.exp == 22)
        #expect(loaded.player.lastWorkResult?.completedAt == work.endsAt)
        #expect(GameEngine.startWork(&loaded, now: work.endsAt).succeeded)
        #expect(loaded.player.activeWork?.endsAt == work.endsAt.addingTimeInterval(120))
        #expect(loaded.player.stamina == 61 && loaded.player.mood == 71)
    }

    @Test func equippingDuringABaseShiftOnlySpeedsTheNextShift() throws {
        var state = GameSnapshot.fresh(now: now)
        _ = GameEngine.startWork(&state, now: now)
        let work = try #require(state.player.activeWork)
        _ = GameEngine.equipStarterSet(&state, now: now.addingTimeInterval(10))
        #expect(state.player.activeWork == work)
        #expect(state.player.stamina == 70 && state.player.mood == 75)
        #expect(GameEngine.workQuote(for: state.player)?.durationSeconds == 102)
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(102))
        #expect(state.player.activeWork != nil && state.player.gold == 200)
        _ = GameEngine.synchronize(&state, now: work.endsAt)
        #expect(state.player.gold == 260)
        _ = GameEngine.startWork(&state, now: work.endsAt)
        #expect(state.player.activeWork?.endsAt == work.endsAt.addingTimeInterval(102))
        #expect(state.player.stamina == 61 && state.player.mood == 71)
    }

    @Test func legacyInFlightWorkKeepsItsDeadlineAfterMigrationAndOutfitChanges() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = GameSnapshot.fresh(now: now)
        _ = GameEngine.startWork(&state, now: now)
        try await repository.save(state)
        let data = try modifiedData(Data(contentsOf: repository.saveURL)) { object in
            var player = try #require(object["player"] as? [String: Any])
            player.removeValue(forKey: "profile")
            var work = try #require(player["activeWork"] as? [String: Any])
            work.removeValue(forKey: "quote")
            player["activeWork"] = work
            object["player"] = player
        }
        try data.write(to: repository.saveURL)
        var loaded = try await repository.loadOrCreate(now: now)
        let legacy = try #require(loaded.player.activeWork)
        #expect(legacy.quote == nil && legacy.endsAt == now.addingTimeInterval(120))
        _ = GameEngine.equipStarterSet(&loaded, now: now.addingTimeInterval(20))
        #expect(loaded.player.activeWork == legacy)
        try await repository.save(loaded)
        _ = GameEngine.synchronize(&loaded, now: legacy.endsAt)
        #expect(loaded.player.gold == 260 && loaded.player.exp == 22)
        try await repository.save(loaded)
        #expect(try await repository.loadOrCreate(now: now) == loaded)
    }

    @Test func equippedOfflineCompletionSurvivesReloadAndRollbackWithoutDoubleRewards() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        state.player.exp = 90
        _ = GameEngine.equipStarterSet(&state, now: now)
        _ = GameEngine.startWork(&state, now: now)
        let work = try #require(state.player.activeWork)
        try await repository.save(state)
        let returned = now.addingTimeInterval(86_400)
        var loaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: returned)
        _ = GameEngine.synchronize(&loaded, now: returned)
        #expect(loaded.player.gold == 260 && loaded.player.level == 2 && loaded.player.exp == 12)
        #expect(loaded.player.lastWorkResult?.id == work.id && loaded.player.completedWorkCount == 1)
        #expect(loaded.player.lastWorkResult?.completedAt == now.addingTimeInterval(102))
        try await repository.save(loaded)
        let settled = loaded
        for time in [returned, now, now.addingTimeInterval(-60)] {
            var reopened = try await FileSaveRepository(directory: folder).loadOrCreate(now: time)
            #expect(GameEngine.synchronize(&reopened, now: time).kind == .none)
            #expect(reopened == settled)
        }
    }

    @Test func unknownAndUnownedSelectionsFailWithoutPartialStateChanges() {
        var state = GameSnapshot.fresh(now: now)
        let original = state
        #expect(GameEngine.selectAvatar(&state, avatarID: "unknown", now: now).messageKey == "player.avatarMissing")
        #expect(GameEngine.equipItem(&state, itemID: "unknown", now: now).messageKey == "equipment.itemMissing")
        #expect(state == original)
        state.player.profile.ownedEquipmentIDs.removeAll { $0 == "starter_charm" }
        let partial = state
        #expect(GameEngine.equipItem(&state, itemID: "starter_charm", now: now).messageKey == "equipment.notOwned")
        #expect(GameEngine.equipStarterSet(&state, now: now).messageKey == "equipment.notOwned")
        #expect(state == partial && state.player.profile.equipped.isEmpty)
        #expect(GameEngine.workQuote(for: state.player, jobID: "unknown") == nil)
    }

    @Test func equipmentDoesNotBypassCareerLevelOrSleepExclusion() {
        var state = GameSnapshot.fresh(now: now)
        _ = GameEngine.startSleep(&state, now: now)
        _ = GameEngine.equipStarterSet(&state, now: now)
        let sleeping = state
        #expect(GameEngine.startWork(&state, now: now).messageKey == "work.sleeping")
        #expect(state == sleeping)
        _ = GameEngine.wakeUp(&state, now: now)
        let awake = state
        #expect(GameEngine.startWork(&state, jobID: "job_cat_cafe_manager", now: now).messageKey == "work.levelRequired")
        #expect(state == awake)
        _ = GameEngine.startWork(&state, now: now)
        let working = state
        #expect(GameEngine.startSleep(&state, now: now).messageKey == "sleep.workActive")
        #expect(state == working)
    }

    @Test func additiveBonusesAreCappedAndSmallPositiveCostsNeverBecomeZero() {
        let forty = EquipmentBonuses(durationReductionPercent: 40, staminaReductionPercent: 40, moodReductionPercent: 40)
        #expect(forty.adding(forty) == EquipmentBonuses(durationReductionPercent: 50, staminaReductionPercent: 50, moodReductionPercent: 50))
        #expect(EquipmentBonuses(durationReductionPercent: Int.max, staminaReductionPercent: -1).durationReductionPercent == 50)
        #expect(EquipmentBonuses(staminaReductionPercent: -1).staminaReductionPercent == 0)
        #expect(WorkQuote.discount(0, by: 50) == 0)
        #expect(WorkQuote.discount(1, by: 50) == 1)
        #expect(WorkQuote.discount(3, by: 50) == 2)
        #expect(WorkQuote.discount(15, by: 15) == 13)
    }

    @Test func invalidProfilesCannotOverwriteValidPrimaryOrBackup() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        _ = GameEngine.equipStarterSet(&state, now: now)
        try await repository.save(state)
        let primary = try Data(contentsOf: repository.saveURL)
        let backup = try Data(contentsOf: repository.backupURL)
        let mutations: [(inout PlayerProfile) -> Void] = [
            { $0.avatarID = "missing" },
            { $0.ownedEquipmentIDs.append("starter_cap") },
            { $0.ownedEquipmentIDs.append("unknown") },
            { $0.ownedEquipmentIDs.removeAll() },
            { $0.equipped[.head] = "starter_jacket" },
            { $0.equipped[.head] = "unknown" }
        ]
        for mutation in mutations {
            var invalid = state
            mutation(&invalid.player.profile)
            #expect(!invalid.isValid)
            #expect(GameEngine.workQuote(for: invalid.player) == nil)
            let unchanged = invalid
            #expect(!GameEngine.selectAvatar(&invalid, avatarID: "male_sunny", now: now).succeeded)
            #expect(invalid == unchanged)
            await #expect(throws: SaveRepositoryError.invalidSnapshot) { try await repository.save(invalid) }
            #expect(try Data(contentsOf: repository.saveURL) == primary)
            #expect(try Data(contentsOf: repository.backupURL) == backup)
        }
    }

    @Test func unknownSlotOrIncompleteProfileUsesValidatedBackupInsteadOfResetting() async throws {
        for mode in ["slot", "inventory", "null"] {
            let folder = try directory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let repository = FileSaveRepository(directory: folder)
            var state = try await repository.loadOrCreate(now: now)
            _ = GameEngine.selectAvatar(&state, avatarID: "female_scholarly", now: now)
            try await repository.save(state, now: now)
            let validBackup = try await FileSaveRepository(directory: folder).loadOrCreate(now: now)
            state.player.gold += 1
            try await repository.save(state, now: now.addingTimeInterval(FileSaveRepository.backupInterval))
            let corrupt = try modifiedData(Data(contentsOf: repository.saveURL)) { object in
                var player = try #require(object["player"] as? [String: Any])
                var profile = try #require(player["profile"] as? [String: Any])
                if mode == "slot" { profile["equipped"] = ["unknown-slot": "starter_cap"] }
                if mode == "inventory" { profile.removeValue(forKey: "ownedEquipmentIDs") }
                player["profile"] = mode == "null" ? NSNull() : profile
                object["player"] = player
            }
            try corrupt.write(to: repository.saveURL)
            let restored = try await repository.loadOrCreate(now: now)
            #expect(restored == validBackup)
            #expect(await repository.lastLoadDisposition == .recoveredBackup)
            #expect(restored.player.profile.avatarID == "female_scholarly")
            let preserved = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("unreadable-save-") }
            #expect(preserved.count == 1)
            #expect(try Data(contentsOf: preserved[0]) == corrupt)
        }
    }

    @Test func invalidCapturedQuoteCannotOverwriteEitherSaveFile() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        _ = GameEngine.equipStarterSet(&state, now: now)
        _ = GameEngine.startWork(&state, now: now)
        try await repository.save(state)
        let original = try #require(state.player.activeWork?.quote)
        let primary = try Data(contentsOf: repository.saveURL)
        let backup = try Data(contentsOf: repository.backupURL)
        let mutations: [(inout [String: Any]) throws -> Void] = [
            { $0["durationSeconds"] = 0 }, { $0["staminaCost"] = -1 },
            { $0["baseDurationSeconds"] = Int.max }, { $0["baseMoodCost"] = 101 },
            { $0["jobID"] = "job_store" },
            { $0["equipmentIDs"] = ["starter_cap", "starter_cap"] },
            { $0["equipmentIDs"] = ["unknown"] },
            { value in
                var bonuses = try #require(value["bonuses"] as? [String: Any])
                bonuses["durationReductionPercent"] = 100
                value["bonuses"] = bonuses
            }
        ]
        for mutation in mutations {
            var invalid = state
            invalid.player.activeWork?.quote = try revisedQuote(original, mutation)
            #expect(!invalid.isValid)
            await #expect(throws: SaveRepositoryError.invalidSnapshot) { try await repository.save(invalid) }
            #expect(try Data(contentsOf: repository.saveURL) == primary)
            #expect(try Data(contentsOf: repository.backupURL) == backup)
        }
    }

    @Test func capturedBaselineIsNotRepricedFromCurrentCatalog() throws {
        var state = GameSnapshot.fresh(now: now)
        _ = GameEngine.equipStarterSet(&state, now: now)
        _ = GameEngine.startWork(&state, now: now)
        let original = try #require(state.player.activeWork?.quote)
        let historical = try revisedQuote(original) { $0["baseDurationSeconds"] = 300; $0["durationSeconds"] = 255 }
        state.player.activeWork?.quote = historical
        state.player.activeWork?.endsAt = now.addingTimeInterval(255)
        #expect(state.isValid)
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(102))
        #expect(state.player.gold == 200 && state.player.activeWork?.quote == historical)
        _ = GameEngine.synchronize(&state, now: now.addingTimeInterval(255))
        #expect(state.player.gold == 260 && state.player.exp == 22)
    }
}
