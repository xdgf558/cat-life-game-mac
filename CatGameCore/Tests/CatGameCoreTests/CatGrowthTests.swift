import Foundation
import Testing
@testable import CatGameCore

@Suite("Cat growth anchors, companionship, and save migration")
struct CatGrowthTests {
    let now = Date(timeIntervalSince1970: 1_793_318_400)
    let day: TimeInterval = 86_400

    private func object(_ state: GameSnapshot) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: NativeSaveCodec.encoder().encode(state)) as? [String: Any])
    }

    private func data(_ object: [String: Any]) throws -> Data {
        try snapshotFixtureData(object)
    }

    private func legacyData(_ state: GameSnapshot, schema: Int) throws -> Data {
        var saved = try object(state)
        saved["schemaVersion"] = schema
        var cats = try #require(saved["cats"] as? [[String: Any]])
        for index in cats.indices { cats[index].removeValue(forKey: "growthState") }
        saved["cats"] = cats
        return try data(saved)
    }

    @Test func catalogAndFreshRecordsAreDeterministic() throws {
        #expect(CatAppearance.allCases.map { CatGrowthCatalog.initialAgeDays(for: $0) } == [90, 180, 365, 180, 90])
        #expect(CatAppearance.allCases.map { CatGrowthCatalog.sex(for: $0) } == [.male, .female, .male, .male, .female])
        #expect(GameSnapshot.fresh(now: now) == GameSnapshot.fresh(now: now))
        let record = try #require(GameSnapshot.fresh(now: now).activeCat?.growthState)
        #expect(record.recordedSince == now && record.adoptedAt == now && !record.isLegacyRecord)
        #expect(record.ageDays(at: now) == 90 && record.companionshipDays(at: now) == 0)
    }

    @Test func ageAndStageUseTenfoldTimeWhileCompanionshipUsesWholeRealDays() {
        let kitten = CatGrowthState(recordedSince: now, adoptedAt: now, initialAgeDays: 179, sex: .female)
        #expect(kitten.stage(at: now) == .kitten)
        #expect(kitten.ageDays(at: now.addingTimeInterval(day / 10 - 0.01)) == 179)
        #expect(kitten.stage(at: now.addingTimeInterval(day / 10)) == .junior)
        let junior = CatGrowthState(recordedSince: now, adoptedAt: now, initialAgeDays: 364, sex: .male)
        #expect(junior.stage(at: now) == .junior)
        #expect(junior.stage(at: now.addingTimeInterval(day / 10)) == .adult)
        #expect(junior.ageDays(at: now.addingTimeInterval(day)) == 374)
        #expect(junior.companionshipDays(at: now.addingTimeInterval(day - 0.01)) == 0)
        #expect(junior.companionshipDays(at: now.addingTimeInterval(day)) == 1)
        #expect(junior.ageDays(at: now.addingTimeInterval(-day)) == 364)
        #expect(junior.companionshipDays(at: now.addingTimeInterval(-day)) == 0)
        #expect(CatGrowthStage.allCases.map(\.minimumAgeDays) == [0, 180, 365])
        #expect(CatGrowthStage.kitten.next == .junior && CatGrowthStage.junior.next == .adult && CatGrowthStage.adult.next == nil)
    }

    @Test func bondStagesReuseExistingIntimacyWithoutChangingCareRewards() throws {
        for (points, stage) in [(0, CatBondStage.newFriend), (24, .newFriend), (25, .familiar),
                                (49, .familiar), (50, .trusted), (74, .trusted), (75, .close), (100, .close)] {
            #expect(CatBondStage.stage(for: points) == stage)
        }
        #expect(CatBondStage.allCases.map(\.minimumIntimacy) == [0, 25, 50, 75])
        #expect(CatBondStage.newFriend.next == .familiar && CatBondStage.close.next == nil)
        var state = GameSnapshot.fresh(now: now)
        state.inventory.toys = 2
        let record = state.cats[0].growthState
        #expect(GameEngine.play(&state, catID: state.activeCatID, now: now).succeeded)
        #expect(state.cats[0].intimacy == 24 && CatBondStage.stage(for: state.cats[0].intimacy) == .newFriend)
        #expect(GameEngine.play(&state, catID: state.activeCatID, now: now).succeeded)
        #expect(state.cats[0].intimacy == 36 && CatBondStage.stage(for: state.cats[0].intimacy) == .familiar)
        #expect(state.cats[0].growthState == record && state.player.gold == 200)
        #expect(state.inventory.toys == 0 && state.player.exp == 0)
    }

    @Test func synchronizationKeepsAnchorsAndDoesNotReverseGrowthOnClockRollback() throws {
        var state = GameSnapshot.fresh(now: now)
        let anchor = try #require(state.cats[0].growthState)
        let later = now.addingTimeInterval(10 * day)
        #expect(GameEngine.synchronize(&state, now: later).succeeded)
        #expect(state.cats[0].growthState == anchor)
        #expect(anchor.ageDays(at: state.meta.lastSyncAt) == 190)
        #expect(anchor.companionshipDays(at: state.meta.lastSyncAt) == 10)
        let settled = state
        #expect(GameEngine.synchronize(&state, now: now.addingTimeInterval(-day)).succeeded)
        #expect(state == settled)
        #expect(GameEngine.synchronize(&state, now: later).succeeded && state == settled)
        #expect(state.player.gold == 200 && state.player.exp == 0)
    }

    @Test func adoptionKeepsEachCatsAgeAndCompanionshipIndependent() throws {
        var state = GameSnapshot.fresh(now: now)
        state.player.level = 4
        state.player.gold = 2_000
        state.home.roomLevel = 3
        let later = now.addingTimeInterval(3 * day)
        #expect(GameEngine.adoptCat(&state, catID: CatCatalog.cowCatID, now: later).succeeded)
        let first = try #require(state.cats[0].growthState)
        let second = try #require(state.cats[1].growthState)
        #expect(first.adoptedAt == now && second.adoptedAt == later)
        #expect(first.companionshipDays(at: state.meta.lastSyncAt) == 3)
        #expect(second.companionshipDays(at: state.meta.lastSyncAt) == 0)
        #expect(first.ageDays(at: later) == 120 && second.ageDays(at: later) == 180)
        #expect(GameEngine.selectCompanion(&state, catID: CatCatalog.cowCatID, now: later).succeeded)
        #expect(state.cats[0].growthState == first && state.cats[1].growthState == second)
        let archive = try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: state, exportedAt: later), now: later)
        #expect(archive.snapshot == state)
    }

    @Test func allPreGrowthSchemasStartRecordsAtMigrationWithoutInventingAdoptionHistory() throws {
        var original = GameSnapshot.fresh(now: now)
        original.player.gold = 654
        original.cats[0].customName = "老朋友"
        original.cats[0].intimacy = 81
        original.cats.append(CatState(id: CatCatalog.cowCatID, name: "牛奶", now: now, appearance: .cow))
        let migrationDate = now.addingTimeInterval(90 * day)
        for schema in 1...8 {
            let loaded = try NativeSaveCodec.decodeSnapshot(legacyData(original, schema: schema), now: migrationDate)
            var expected = original
            for index in expected.cats.indices {
                expected.cats[index].growthState = .legacy(appearance: expected.cats[index].appearance, now: migrationDate)
            }
            expected = expectedCompanionMigration(expected)
            #expect(loaded == expected && loaded.isValid)
            for cat in loaded.cats {
                let record = try #require(cat.growthState)
                #expect(record.isLegacyRecord && record.adoptedAt == nil && record.recordedSince == migrationDate)
                #expect(record.companionshipDays(at: migrationDate) == 0)
                #expect(record.ageDays(at: migrationDate) == CatGrowthCatalog.initialAgeDays(for: cat.appearance))
            }
        }
    }

    @Test func migratedAnchorsSurviveDurableSaveColdLaunchAndArchiveImport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CatGrowth-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let original = GameSnapshot.fresh(now: now)
        let bytes = try legacyData(original, schema: 8)
        try bytes.write(to: repository.saveURL)
        let migrationDate = now.addingTimeInterval(5 * day)
        let loaded = try await repository.loadOrCreate(now: migrationDate)
        #expect(loaded.activeCat?.growthState?.recordedSince == migrationDate)
        try await repository.save(loaded, now: migrationDate)
        #expect(try Data(contentsOf: repository.backupURL) == bytes)
        let reopened = try await FileSaveRepository(directory: folder).loadOrCreate(now: migrationDate.addingTimeInterval(day))
        #expect(reopened == loaded)
        let archive = try NativeSaveTransfer.decode(
            NativeSaveTransfer.encode(snapshot: loaded, exportedAt: migrationDate), now: migrationDate.addingTimeInterval(10 * day))
        #expect(archive.snapshot == loaded && archive.snapshot.activeCat?.growthState?.adoptedAt == nil)
    }

    @Test func currentSchemaRejectsMissingNullAndDamagedGrowthInsteadOfResettingIt() throws {
        let original = try object(GameSnapshot.fresh(now: now))
        let originalCats = try #require(original["cats"] as? [[String: Any]])
        let originalGrowth = try #require(originalCats[0]["growthState"] as? [String: Any])
        for replacement in [nil, NSNull()] as [Any?] {
            var saved = original
            var cats = originalCats
            cats[0]["growthState"] = replacement
            saved["cats"] = cats
            #expect(throws: (any Error).self) { try NativeSaveCodec.decodeSnapshot(data(saved), now: now) }
        }
        for key in ["recordedSince", "initialAgeDays", "sex", "isLegacyRecord", "adoptedAt"] {
            var saved = original
            var cats = originalCats
            var growth = originalGrowth
            growth.removeValue(forKey: key)
            cats[0]["growthState"] = growth
            saved["cats"] = cats
            #expect(throws: (any Error).self) { try NativeSaveCodec.decodeSnapshot(data(saved), now: now) }
        }
        for (key, value) in [("initialAgeDays", -1 as Any), ("initialAgeDays", 36_501 as Any),
                             ("sex", "missing" as Any), ("recordedSince", "not a date" as Any),
                             ("isLegacyRecord", true as Any)] {
            var saved = original
            var cats = originalCats
            var growth = originalGrowth
            growth[key] = value
            cats[0]["growthState"] = growth
            saved["cats"] = cats
            #expect(throws: (any Error).self) { try NativeSaveCodec.decodeSnapshot(data(saved), now: now) }
        }
    }

    @Test func growthDatesParticipateInImportClockValidationWithoutBlockingExport() throws {
        var state = GameSnapshot.fresh(now: now)
        let future = now.addingTimeInterval(day + 1)
        state.cats[0].growthState = .adopted(appearance: .orange, now: future)
        #expect(state.isValid && state.meta.lastSyncAt == now)
        let archive = try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: state, exportedAt: now), now: now)
        #expect(archive.snapshot == state)
        #expect(throws: NativeSaveTransferError.futureProgress) { try NativeSaveTransfer.validateImportTime(archive, now: now) }
        try NativeSaveTransfer.validateImportTime(archive, now: now.addingTimeInterval(1))
        state.cats[0].growthState = .legacy(appearance: .orange, now: future)
        let legacy = try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: state, exportedAt: now), now: now)
        #expect(throws: NativeSaveTransferError.futureProgress) { try NativeSaveTransfer.validateImportTime(legacy, now: now) }
    }

    @Test func invalidAnchorsCannotBeSavedOrExportedOverValidProgress() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CatGrowthInvalid-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let original = try await repository.loadOrCreate(now: now)
        let bytes = try Data(contentsOf: repository.saveURL)
        let invalidRecords = [
            CatGrowthState(recordedSince: Date(timeIntervalSince1970: .infinity), adoptedAt: nil, initialAgeDays: 90, sex: .male),
            CatGrowthState(recordedSince: now, adoptedAt: now.addingTimeInterval(1), initialAgeDays: 90, sex: .male),
            CatGrowthState(recordedSince: now, adoptedAt: now, initialAgeDays: -1, sex: .male)
        ]
        for record in invalidRecords {
            var invalid = original
            invalid.cats[0].growthState = record
            #expect(!invalid.isValid)
            await #expect(throws: SaveRepositoryError.invalidSnapshot) { try await repository.save(invalid, now: now) }
            #expect(throws: NativeSaveTransferError.invalidArchive) { try NativeSaveTransfer.encode(snapshot: invalid, exportedAt: now) }
            #expect(try Data(contentsOf: repository.saveURL) == bytes)
        }
    }

    @Test func explicitMalePregnancyIsRejectedWithoutOverwritingDurableProgress() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CatGrowthPregnancy-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        let original = try await repository.loadOrCreate(now: now)
        let bytes = try Data(contentsOf: repository.saveURL)
        var invalid = original
        invalid.cats[0].isPregnant = true
        #expect(invalid.cats[0].growthState?.sex == .male && !invalid.isValid)
        let before = invalid
        #expect(GameEngine.feed(&invalid, catID: invalid.activeCatID, now: now).failure == .gameInvalidState)
        #expect(invalid == before)
        // An explicit sex is authoritative even if the surrounding header claims an older schema.
        for schema in 1...GameSnapshot.currentSchemaVersion {
            var saved = try object(invalid)
            saved["schemaVersion"] = schema
            #expect(throws: SaveRepositoryError.invalidSnapshot) {
                try NativeSaveCodec.decodeSnapshot(data(saved), now: now)
            }
        }
        await #expect(throws: SaveRepositoryError.invalidSnapshot) { try await repository.save(invalid, now: now) }
        #expect(throws: NativeSaveTransferError.invalidArchive) { try NativeSaveTransfer.encode(snapshot: invalid, exportedAt: now) }
        #expect(try Data(contentsOf: repository.saveURL) == bytes)
        invalid.cats[0].growthState = .legacy(appearance: .orange, now: now)
        #expect(!invalid.isValid, "A legacy origin is not permission to rewrite an already recorded male sex.")
    }

    @Test func preGrowthPregnancyMigratesToFemaleWithoutErasingPregnancyOrOtherProgress() throws {
        var original = GameSnapshot.fresh(now: now)
        original.player.gold = 654
        original.cats = CatAppearance.allCases.map { appearance in
            CatState(id: appearance == .orange ? CatCatalog.initialCatID : "legacy-\(appearance.rawValue)",
                     name: appearance.rawValue, intimacy: 81, isPregnant: true, now: now, appearance: appearance)
        }
        let migrationDate = now.addingTimeInterval(30 * day)
        for schema in 1...8 {
            let bytes = try legacyData(original, schema: schema)
            var loaded = try NativeSaveCodec.decodeSnapshot(bytes, now: migrationDate)
            var expected = original
            for index in expected.cats.indices {
                expected.cats[index].growthState = .legacy(appearance: expected.cats[index].appearance,
                    now: migrationDate, isPregnant: true)
            }
            expected = expectedCompanionMigration(expected)
            #expect(loaded == expected && loaded.isValid)
            #expect(loaded.cats.allSatisfy { $0.isPregnant && $0.growthState?.sex == .female
                && $0.growthState?.adoptedAt == nil && $0.growthState?.recordedSince == migrationDate })
            let archive = try NativeSaveTransfer.decode(
                NativeSaveTransfer.encode(snapshot: loaded, exportedAt: migrationDate), now: migrationDate.addingTimeInterval(day))
            #expect(archive.snapshot == loaded, "Reloading must keep the migrated sex and original pregnancy.")
            #expect(GameEngine.feed(&loaded, catID: loaded.activeCatID, now: migrationDate).amount == 2)
            #expect(loaded.inventory.food == original.inventory.food - 2 && loaded.cats[0].isPregnant)

            var rawDecoded = try NativeSaveCodec.decoder().decode(GameSnapshot.self, from: bytes)
            #expect(rawDecoded.cats.allSatisfy { $0.growthState == nil })
            #expect(GameEngine.synchronize(&rawDecoded, now: migrationDate).succeeded)
            #expect(rawDecoded.cats.allSatisfy { $0.isPregnant && $0.growthState?.sex == .female })
        }
    }

    @Test func growthTrackingHasItsOwnUnchangedSaturationLimit() {
        #expect(CatGrowthState.maximumTrackedDays == 1_000_000_000)
        let record = CatGrowthState.adopted(appearance: .orange, now: now)
        let maximum = CatGrowthState.maximumTrackedDays
        let farFuture = now.addingTimeInterval(Double(maximum + 100) * day)
        #expect(record.ageDays(at: farFuture) == maximum)
        #expect(record.companionshipDays(at: farFuture) == maximum)
        #expect(record.stage(at: farFuture) == .adult)
        #expect(record.ageDays(at: now.addingTimeInterval(2 * day)) == 110)
        #expect(record.companionshipDays(at: now.addingTimeInterval(2 * day)) == 2)
    }
}
