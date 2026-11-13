import Foundation
import Testing
@testable import CatGameCore

@Suite("Native save durability")
struct FileSaveRepositoryTests {
    let now = Date(timeIntervalSince1970: 1_793_318_400)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CatGameCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func freshSaveRoundTripsLayoutAndGeneratedCats() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        #expect(await repository.lastLoadDisposition == .created)
        _ = GameEngine.feed(&state, catID: "cat_001", now: now)
        _ = GameEngine.setBowlPosition(&state, .init(x: 0.58, y: 0.72), now: now)
        state.cats.append(CatState(id: "kitten_existing", name: "小猫", now: now))
        _ = GameEngine.startWork(&state, now: now)
        try await repository.save(state)
        let reopened = FileSaveRepository(directory: folder)
        let loaded = try await reopened.loadOrCreate(now: now.addingTimeInterval(60))
        #expect(loaded == state)
        #expect(loaded.cats.contains { $0.id == "kitten_existing" })
        #expect(loaded.player.activeWork?.id == state.player.activeWork?.id)
        #expect(loaded.home.bowlPosition == .init(x: 0.58, y: 0.72))
    }

    @Test func interruptedWorkSurvivesReloadAndPaysOnce() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        _ = GameEngine.startWork(&state, now: now)
        try await repository.save(state)
        var restored = try await repository.loadOrCreate(now: now.addingTimeInterval(300))
        #expect(GameEngine.synchronize(&restored, now: now.addingTimeInterval(300)).kind == .workFinished)
        try await repository.save(restored)
        var again = try await repository.loadOrCreate(now: now.addingTimeInterval(301))
        #expect(GameEngine.synchronize(&again, now: now.addingTimeInterval(301)).kind == .none)
        #expect(again.player.gold == 260)
    }

    @Test func corruptedPrimaryRecoversValidatedBackupAndPreservesEvidence() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let first = try await repository.loadOrCreate(now: now)
        var second = first
        _ = GameEngine.feed(&second, catID: "cat_001", now: now)
        try await repository.save(second)
        let damaged = Data("broken save".utf8)
        try damaged.write(to: repository.saveURL)
        let recovered = try await repository.loadOrCreate(now: now)
        #expect(recovered == first)
        #expect(await repository.lastLoadDisposition == .recoveredBackup)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let preserved = try #require(files.first { $0.lastPathComponent.hasPrefix("unreadable-save-") })
        #expect(try Data(contentsOf: preserved) == damaged)
        #expect(try await repository.loadOrCreate(now: now) == first)
    }

    @Test func retiredTaskReceiptsLoadFromPrimaryAndBackupAndRemainWritable() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var expected = try await repository.loadOrCreate(now: now)
        #expect(GameEngine.feed(&expected, catID: expected.activeCatID, now: now).succeeded)
        #expect(GameEngine.claimTask(&expected, id: "tutorial_feed", now: now).succeeded)
        #expect(GameEngine.claimTask(&expected, id: "daily_feed", expectedDayKey: expected.tasks.dailyDayKey, now: now).succeeded)
        try await repository.save(expected, now: now)
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repository.saveURL)) as? [String: Any])
        var tasks = try #require(object["tasks"] as? [String: Any])
        tasks["claimedTaskIDs"] = ["retired_tutorial", "tutorial_feed"]
        tasks["dailyClaimedTaskIDs"] = ["daily_feed", "retired_daily"]
        object["tasks"] = tasks
        let original = try JSONSerialization.data(withJSONObject: object)
        try original.write(to: repository.saveURL)
        try original.write(to: repository.backupURL)

        let loaded = try await repository.loadOrCreate(now: now)
        #expect(loaded == expected)
        #expect(await repository.lastLoadDisposition == .loaded)
        #expect(try Data(contentsOf: repository.saveURL) == original)
        try await repository.checkWritable()
        try await repository.save(loaded, now: now)
        #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == expected)
        #expect(try Data(contentsOf: repository.backupURL) == original)

        try Data("damaged primary".utf8).write(to: repository.saveURL)
        var recovered = try await repository.loadOrCreate(now: now)
        #expect(recovered == expected)
        #expect(await repository.lastLoadDisposition == .recoveredBackup)
        #expect(GameEngine.claimTask(&recovered, id: "tutorial_feed", now: now).failure == .taskAlreadyClaimed)
        #expect(GameEngine.claimTask(&recovered, id: "daily_feed", expectedDayKey: recovered.tasks.dailyDayKey, now: now).failure == .taskAlreadyClaimed)
        #expect(recovered == expected)
        try await repository.save(recovered, now: now)
        #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == expected)
    }

    @Test func corruptedSaveWithoutBackupIsNeverReplacedWithNewGame() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let damaged = Data("{invalid".utf8)
        try damaged.write(to: repository.saveURL)
        await #expect(throws: SaveRepositoryError.unreadableSave) {
            _ = try await repository.loadOrCreate(now: now)
        }
        #expect(try Data(contentsOf: repository.saveURL) == damaged)
    }

    @Test func corruptBackupAndPrimaryRemainUntouched() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let primary = Data("bad primary".utf8)
        let backup = Data("bad backup".utf8)
        try primary.write(to: repository.saveURL)
        try backup.write(to: repository.backupURL)
        await #expect(throws: SaveRepositoryError.unreadableSave) {
            _ = try await repository.loadOrCreate(now: now)
        }
        #expect(try Data(contentsOf: repository.saveURL) == primary)
        #expect(try Data(contentsOf: repository.backupURL) == backup)
    }

    @Test func futureSchemaRefusesDowngradeEvenWithGoodBackup() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        _ = GameEngine.feed(&state, catID: "cat_001", now: now)
        try await repository.save(state)
        let future = Data("{\"schemaVersion\":99,\"futureData\":\"keep\"}".utf8)
        try future.write(to: repository.saveURL)
        await #expect(throws: SaveRepositoryError.unsupportedSchemaVersion(99)) {
            _ = try await repository.loadOrCreate(now: now)
        }
        await #expect(throws: SaveRepositoryError.unsupportedSchemaVersion(99)) {
            try await repository.save(state)
        }
        #expect(try Data(contentsOf: repository.saveURL) == future)
    }

    @Test func schemaOnePurchasesAndSelectedCowMigrateOnlyOnSuccessfulSave() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var expected = GameSnapshot.fresh(now: now)
        expected.player.level = 4
        expected.player.gold = 5000
        expected.player.profile.name = "Milo"
        expected.home.name = "Quiet home"
        expected.settings.language = .traditionalChinese
        #expect(GameEngine.upgradeHome(&expected, toLevel: 2, now: now).succeeded)
        #expect(GameEngine.purchaseEquipment(&expected, itemID: "advanced_cap", now: now).succeeded)
        #expect(GameEngine.equipItem(&expected, itemID: "advanced_cap", now: now).succeeded)
        #expect(GameEngine.adoptCat(&expected, catID: CatCatalog.cowCatID, now: now).succeeded)
        #expect(GameEngine.selectCompanion(&expected, catID: CatCatalog.cowCatID, now: now).succeeded)
        expected.cats[1].customName = "Milk🐾"
        #expect(GameEngine.startWork(&expected, now: now).succeeded)
        #expect(GameEngine.startCatRest(&expected, catID: CatCatalog.cowCatID,
            furnitureID: "catBed", sessionID: "migration-rest", now: now).succeeded)
        try await repository.save(expected, now: now)
        var legacy = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repository.saveURL)) as? [String: Any])
        legacy["schemaVersion"] = 1
        let legacyBytes = try snapshotFixtureData(legacy, options: [.sortedKeys])
        try legacyBytes.write(to: repository.saveURL)
        expected = expectedCompanionMigration(expected)

        let migrated = try await repository.loadOrCreate(now: now.addingTimeInterval(60))
        #expect(migrated == expected)
        #expect(migrated.schemaVersion == GameSnapshot.currentSchemaVersion && migrated.activeCat?.appearance == .cow)
        #expect(await repository.lastLoadDisposition == .loaded)
        #expect(try Data(contentsOf: repository.saveURL) == legacyBytes)
        var invalid = migrated
        invalid.player.gold = -1
        await #expect(throws: SaveRepositoryError.invalidSnapshot) { try await repository.save(invalid) }
        #expect(try Data(contentsOf: repository.saveURL) == legacyBytes)

        try await repository.save(migrated, now: now)
        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repository.saveURL)) as? [String: Any])
        #expect(saved["schemaVersion"] as? Int == GameSnapshot.currentSchemaVersion)
        #expect(try Data(contentsOf: repository.backupURL) == legacyBytes)
        #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == expected)
        try Data("interrupted migrated primary".utf8).write(to: repository.saveURL)
        #expect(try await repository.loadOrCreate(now: now) == expected)
        #expect(await repository.lastLoadDisposition == .recoveredBackup)
        try await repository.save(expected, now: now)
        #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == expected)
    }

    @Test func originalSchemaOneWithoutNewFieldsKeepsProgressAndReceivesDefaults() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var expected = GameSnapshot.fresh(now: now)
        expected.player.gold = 572
        expected.inventory.food = 11
        expected.cats[0].intimacy = 37
        try await repository.save(expected, now: now)
        var legacy = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repository.saveURL)) as? [String: Any])
        legacy["schemaVersion"] = 1
        legacy.removeValue(forKey: "activeCatID")
        legacy.removeValue(forKey: "settings")
        var cats = try #require(legacy["cats"] as? [[String: Any]])
        cats[0].removeValue(forKey: "appearance")
        cats[0].removeValue(forKey: "customName")
        legacy["cats"] = cats
        var home = try #require(legacy["home"] as? [String: Any])
        home.removeValue(forKey: "roomLevel")
        legacy["home"] = home
        let legacyBytes = try snapshotFixtureData(legacy, options: [.sortedKeys])
        try legacyBytes.write(to: repository.saveURL)

        let migrated = try await repository.loadOrCreate(now: now)
        #expect(migrated == expected)
        #expect(migrated.schemaVersion == GameSnapshot.currentSchemaVersion && migrated.home.roomLevel == 1)
        #expect(migrated.activeCat?.appearance == .orange)
        #expect(try Data(contentsOf: repository.saveURL) == legacyBytes)
        try await repository.save(migrated, now: now)
        #expect(try await FileSaveRepository(directory: folder).loadOrCreate(now: now) == expected)
    }

    @Test func unsupportedSchemaIsRejectedBeforeAnyGameplayFieldsDecode() throws {
        for version in [0, GameSnapshot.currentSchemaVersion + 1, 99] {
            let data = Data("{\"schemaVersion\":\(version),\"player\":null,\"cats\":\"future-format\"}".utf8)
            #expect(throws: SaveRepositoryError.unsupportedSchemaVersion(version)) {
                try JSONDecoder().decode(GameSnapshot.self, from: data)
            }
        }
    }

    @Test func storageProbeLeavesPrimaryCheckpointAndDirectoryContentsUnchanged() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        state.player.gold += 5
        try await repository.save(state, now: now)
        let primary = try Data(contentsOf: repository.saveURL)
        let backup = try Data(contentsOf: repository.backupURL)
        let modifiedAt = try FileManager.default.attributesOfItem(atPath: repository.saveURL.path)[.modificationDate] as? Date
        let checkpointAt = try FileManager.default.attributesOfItem(atPath: repository.backupURL.path)[.modificationDate] as? Date
        let files = try Set(FileManager.default.contentsOfDirectory(atPath: folder.path))
        for _ in 0..<3 { try await repository.checkWritable() }
        #expect(try Data(contentsOf: repository.saveURL) == primary)
        #expect(try Data(contentsOf: repository.backupURL) == backup)
        #expect(try FileManager.default.attributesOfItem(atPath: repository.saveURL.path)[.modificationDate] as? Date == modifiedAt)
        #expect(try FileManager.default.attributesOfItem(atPath: repository.backupURL.path)[.modificationDate] as? Date == checkpointAt)
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: folder.path)) == files)
    }

    @Test func failedStorageProbeDoesNotReplaceAFileBlockingTheDirectory() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        state.player.gold += 5
        try await repository.save(state, now: now)
        let primary = try Data(contentsOf: repository.saveURL)
        let backup = try Data(contentsOf: repository.backupURL)
        let files = try Set(FileManager.default.contentsOfDirectory(atPath: folder.path))
        let blocked = FileSaveRepository(directory: repository.saveURL)
        await #expect(throws: (any Error).self) { try await blocked.checkWritable() }
        #expect(try Data(contentsOf: repository.saveURL) == primary)
        #expect(try Data(contentsOf: repository.backupURL) == backup)
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: folder.path)) == files)
    }

    @Test func storageProbeHonorsPrimaryAndCheckpointProtectionWithoutRepairingFiles() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        _ = try await repository.loadOrCreate(now: now)
        let primary = try Data(contentsOf: repository.saveURL)
        let future = Data("{\"schemaVersion\":99,\"unknownFields\":true}".utf8)
        try future.write(to: repository.saveURL)
        await #expect(throws: SaveRepositoryError.unsupportedSchemaVersion(99)) { try await repository.checkWritable() }
        #expect(try Data(contentsOf: repository.saveURL) == future)
        let corrupt = Data("broken primary".utf8)
        try corrupt.write(to: repository.saveURL)
        await #expect(throws: (any Error).self) { try await repository.checkWritable() }
        #expect(try Data(contentsOf: repository.saveURL) == corrupt)
        try primary.write(to: repository.saveURL)
        try future.write(to: repository.backupURL)
        await #expect(throws: SaveRepositoryError.unsupportedSchemaVersion(99)) { try await repository.checkWritable() }
        #expect(try Data(contentsOf: repository.backupURL) == future)
        // A normal save can replace a broken checkpoint from the valid primary.
        try corrupt.write(to: repository.backupURL)
        try await repository.checkWritable()
        #expect(try Data(contentsOf: repository.backupURL) == corrupt)
        #expect(try Data(contentsOf: repository.saveURL) == primary)
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: folder.path))
            == Set([repository.saveURL.lastPathComponent, repository.backupURL.lastPathComponent]))
    }

    @Test func invalidStateCannotOverwriteValidSave() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let fresh = try await repository.loadOrCreate(now: now)
        var invalid = fresh
        invalid.cats[0].satiety = 101
        await #expect(throws: SaveRepositoryError.invalidSnapshot) {
            try await repository.save(invalid)
        }
        #expect(try await repository.loadOrCreate(now: now) == fresh)
    }

    @Test func millisecondTimestampsArePersisted() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let timestamp = now.addingTimeInterval(0.123)
        _ = try await repository.loadOrCreate(now: timestamp)
        let loaded = try await repository.loadOrCreate(now: now)
        #expect(abs(loaded.meta.createdAt.timeIntervalSince(timestamp)) < 0.001)
        let json = try String(contentsOf: repository.saveURL, encoding: .utf8)
        #expect(json.contains(".123Z"))
    }

    @Test func missingPrimaryRecoversExistingBackup() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let first = try await repository.loadOrCreate(now: now)
        var second = first
        _ = GameEngine.feed(&second, catID: "cat_001", now: now)
        try await repository.save(second)
        try FileManager.default.removeItem(at: repository.saveURL)
        #expect(try await repository.loadOrCreate(now: now) == first)
        #expect(await repository.lastLoadDisposition == .recoveredBackup)
    }

    @Test func frequentSavesPreserveCheckpointAndRotateAtTheIntervalAcrossReopen() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        let first = try Data(contentsOf: repository.saveURL)
        state.player.gold += 1
        try await repository.save(state, now: now)
        #expect(try Data(contentsOf: repository.backupURL) == first)
        for second in [1.0, 15, 60, 180, 299] {
            state.player.gold += 1
            try await FileSaveRepository(directory: folder).save(state, now: now.addingTimeInterval(second))
            #expect(try Data(contentsOf: repository.backupURL) == first)
        }
        let checkpoint = try Data(contentsOf: repository.saveURL)
        state.player.gold += 1
        try await FileSaveRepository(directory: folder).save(state, now: now.addingTimeInterval(300))
        #expect(try Data(contentsOf: repository.backupURL) == checkpoint)
        #expect(try await repository.loadOrCreate(now: now) == state)
        // Moving the clock backward or saving again shortly afterward cannot rotate it again.
        for second in [-1.0, 301, 599] {
            state.player.gold += 1
            try await FileSaveRepository(directory: folder).save(state, now: now.addingTimeInterval(second))
            #expect(try Data(contentsOf: repository.backupURL) == checkpoint)
        }
        try Data("interrupted primary".utf8).write(to: repository.saveURL)
        let recovered = try await repository.loadOrCreate(now: now)
        #expect(recovered.player.gold == 206)
        #expect(try Data(contentsOf: repository.saveURL) == checkpoint)
    }

    @Test func identicalSaveDoesNotPostponeTheNextCheckpoint() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        state.player.gold += 1
        try await repository.save(state, now: now)
        let checkpoint = try Data(contentsOf: repository.backupURL)
        try await repository.save(state, now: now.addingTimeInterval(400))
        #expect(try Data(contentsOf: repository.backupURL) == checkpoint)
        let saved = try Data(contentsOf: repository.saveURL)
        state.player.gold += 1
        try await repository.save(state, now: now.addingTimeInterval(401))
        #expect(try Data(contentsOf: repository.backupURL) == saved)
    }

    @Test func malformedBackupIsRepairedButFutureBackupIsNeverDowngraded() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        let initial = try Data(contentsOf: repository.saveURL)
        try Data("bad checkpoint".utf8).write(to: repository.backupURL)
        state.player.gold += 1
        try await repository.save(state, now: now)
        #expect(try Data(contentsOf: repository.backupURL) == initial)
        let primary = try Data(contentsOf: repository.saveURL)
        let future = Data("{\"schemaVersion\":99,\"futureData\":\"keep\"}".utf8)
        try future.write(to: repository.backupURL)
        state.player.gold += 1
        await #expect(throws: SaveRepositoryError.unsupportedSchemaVersion(99)) {
            try await repository.save(state, now: now.addingTimeInterval(1))
        }
        #expect(try Data(contentsOf: repository.saveURL) == primary)
        #expect(try Data(contentsOf: repository.backupURL) == future)
    }

    @Test func recoveryEvidenceIsBoundedDeduplicatedAndDoesNotDeleteUnrelatedFiles() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        state.player.gold += 1
        try await repository.save(state, now: now)
        let unrelated = folder.appendingPathComponent("unreadable-save-not-a-generated-uuid.json")
        try Data("personal notes".utf8).write(to: unrelated)
        func evidence() throws -> [URL] {
            try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("unreadable-save-")
                    && $0.lastPathComponent != unrelated.lastPathComponent }
        }
        for number in 1...7 {
            let damaged = Data("damaged primary \(number)".utf8)
            try damaged.write(to: repository.saveURL)
            #expect(try await repository.loadOrCreate(now: now).player.gold == 200)
            let files = try evidence()
            #expect(files.count == min(number, FileSaveRepository.maximumRecoveryFiles))
            let newest = try #require(files.first { (try? Data(contentsOf: $0)) == damaged })
            // Give the previous recoveries deterministic ages; no sleeps are needed.
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(Double(number))],
                                                  ofItemAtPath: newest.path)
        }
        let preserved = try Set(evidence().map { try Data(contentsOf: $0) })
        #expect(preserved == Set((5...7).map { Data("damaged primary \($0)".utf8) }))
        let repeated = Data("damaged primary 5".utf8)
        for _ in 0..<4 {
            try repeated.write(to: repository.saveURL)
            _ = try await repository.loadOrCreate(now: now)
        }
        #expect(try evidence().count == 3)
        #expect(try Set(evidence().map { try Data(contentsOf: $0) }) == preserved)
        #expect(try Data(contentsOf: unrelated) == Data("personal notes".utf8))
    }

    @Test func cappedReceiptAndFailedActionProgressSurviveReloadAndNeverPayTwice() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var state = try await repository.loadOrCreate(now: now)
        state.player.gold = GameSnapshot.maximumGold - 7
        state.inventory.food = 0
        _ = GameEngine.startWork(&state, now: now)
        try await repository.save(state)
        let later = now.addingTimeInterval(1440)
        #expect(!GameEngine.feed(&state, catID: "cat_001", now: later).succeeded)
        #expect(state.player.lastWorkResult?.goldReward == 7 && state.player.exp == 22)
        try await repository.save(state)
        var loaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: later)
        #expect(loaded == state)
        #expect(GameEngine.synchronize(&loaded, now: later).kind == .none)
        #expect(loaded == state)
        _ = GameEngine.buyFood(&loaded, now: later)
        _ = GameEngine.synchronize(&loaded, now: later.addingTimeInterval(3600))
        #expect(loaded.player.gold == GameSnapshot.maximumGold - GameEngine.foodPrice)
        #expect(loaded.player.exp == 22 && loaded.player.completedWorkCount == 1)
    }
}
