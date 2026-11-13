import Foundation
import Testing
@testable import CatGameCore

@Suite("Persistent player sleep and cat recovery")
struct RestRecoveryTests {
    let now = Date(timeIntervalSince1970: 1_793_318_400)
    let catID = "cat_001"

    private func state() -> GameSnapshot {
        var value = GameSnapshot.fresh(now: now)
        value.player.stamina = 20
        value.player.mood = 30
        value.cats[0].energy = 40
        return value
    }

    @Test func sleepUsesWholePointsPreservesFractionsAndNeverAddsPassiveRecovery() {
        var value = state()
        #expect(GameEngine.startSleep(&value, now: now).kind == .sleepStarted)
        var started = value
        _ = GameEngine.synchronize(&started, now: now.addingTimeInterval(100))
        #expect(GameEngine.startSleep(&value, now: now.addingTimeInterval(100)).kind == .none)
        #expect(value == started)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(179))
        #expect(value.player.stamina == 20 && value.player.mood == 30)
        #expect(value.player.sleepStaminaRemainder == 179)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(180))
        #expect(value.player.stamina == 21 && value.player.mood == 31)
        #expect(value.player.sleepStaminaRemainder == 0)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(3599))
        #expect(value.player.stamina == 39 && value.player.mood == 49)
        #expect(value.player.sleepMoodRemainder == 179)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(3600))
        #expect(value.player.stamina == 40 && value.player.mood == 50)
        #expect(value.player.activeSleep?.startedAt == now)
        let settled = value
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(3600))
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(-30))
        #expect(value == settled)
    }

    @Test func wakingAndSleepingAgainRetainsFractionWithoutSameFrameReward() {
        var value = state()
        _ = GameEngine.startSleep(&value, now: now)
        #expect(GameEngine.wakeUp(&value, now: now.addingTimeInterval(90)).kind == .sleepEnded)
        #expect(value.player.stamina == 20 && value.player.sleepStaminaRemainder == 90)
        var awake = value
        _ = GameEngine.synchronize(&awake, now: now.addingTimeInterval(100))
        #expect(GameEngine.wakeUp(&value, now: now.addingTimeInterval(100)).kind == .none)
        #expect(value == awake)
        _ = GameEngine.startSleep(&value, now: now.addingTimeInterval(120))
        _ = GameEngine.wakeUp(&value, now: now.addingTimeInterval(210))
        #expect(value.player.stamina == 21 && value.player.mood == 31)
        #expect(value.player.sleepStaminaRemainder == 0 && value.player.sleepMoodRemainder == 0)
        let before = value
        _ = GameEngine.startSleep(&value, now: now.addingTimeInterval(210))
        _ = GameEngine.wakeUp(&value, now: now.addingTimeInterval(210))
        #expect(value == before)
    }

    @Test func awakeRemainderSurvivesSleepButSleepingHoursAreNotPaidTwice() {
        var value = state()
        _ = GameEngine.startSleep(&value, now: now.addingTimeInterval(900))
        _ = GameEngine.wakeUp(&value, now: now.addingTimeInterval(4500))
        #expect(value.player.stamina == 40)
        #expect(value.player.staminaUpdatedAt == now.addingTimeInterval(3600))
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(7199))
        #expect(value.player.stamina == 40)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(7200))
        #expect(value.player.stamina == 45)
    }

    @Test func workAndSleepExcludeEachOtherButCareRemainsAvailable() {
        var value = state()
        _ = GameEngine.startWork(&value, now: now)
        var working = value
        _ = GameEngine.synchronize(&working, now: now.addingTimeInterval(60))
        #expect(GameEngine.startSleep(&value, now: now.addingTimeInterval(60)).messageKey == "sleep.workActive")
        #expect(value == working)
        #expect(GameEngine.startSleep(&value, now: now.addingTimeInterval(120)).succeeded)
        #expect(value.player.activeWork == nil && value.player.gold == 260)
        var sleeping = value
        _ = GameEngine.synchronize(&sleeping, now: now.addingTimeInterval(121))
        #expect(GameEngine.startWork(&value, now: now.addingTimeInterval(121)).messageKey == "work.sleeping")
        #expect(value == sleeping)
        #expect(GameEngine.feed(&value, catID: catID, now: now.addingTimeInterval(121)).succeeded)
        #expect(value.player.activeSleep != nil && value.inventory.food == 2)
        _ = GameEngine.wakeUp(&value, now: now.addingTimeInterval(122))
        #expect(GameEngine.startWork(&value, now: now.addingTimeInterval(122)).succeeded)
    }

    @Test func sleepCapsEachStatIndependentlyAndDiscardsCappedCredit() {
        var value = state()
        value.player.stamina = 99
        _ = GameEngine.startSleep(&value, now: now)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(359))
        #expect(value.player.stamina == 100 && value.player.sleepStaminaRemainder == 0)
        #expect(value.player.mood == 31 && value.player.sleepMoodRemainder == 179)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(360))
        #expect(value.player.mood == 32 && value.player.sleepMoodRemainder == 0)
        _ = GameEngine.wakeUp(&value, now: now.addingTimeInterval(360))
        _ = GameEngine.startWork(&value, now: now.addingTimeInterval(360))
        #expect(value.player.stamina == 90)
        #expect(value.player.staminaUpdatedAt == now.addingTimeInterval(360))
    }

    @Test func bedRecoveryIsGradualAndPausesOnlyEnergyWithExistingDecayRemainder() {
        var value = state()
        value.cats[0].decayTracker.mood = now.addingTimeInterval(-60)
        value.cats.append(CatState(id: "other", name: "小白", now: now))
        _ = GameEngine.startCatRest(&value, catID: catID, furnitureID: "catBed", sessionID: "bed", now: now.addingTimeInterval(290))
        #expect(value.cats[0].energy == 40)
        #expect(value.cats[0].activeRest?.endsAt == now.addingTimeInterval(302))
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(296))
        #expect(value.cats[0].energy == 50 && value.cats[0].activeRest?.energyGranted == 10)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(302))
        #expect(value.cats[0].energy == 61 && value.cats[0].activeRest == nil)
        #expect(value.cats[0].mood == 84)
        #expect(value.cats[1].energy == 79)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(311))
        #expect(value.cats[0].energy == 61)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(312))
        #expect(value.cats[0].energy == 60)
    }

    @Test func cushionEarlyExitEarnsOnlyElapsedFractionAndCannotBeReplayed() {
        var value = state()
        value.home.comfortScore = 100
        let inventory = value.inventory
        _ = GameEngine.startCatRest(&value, catID: catID, furnitureID: "floorCushion", sessionID: "pad", now: now)
        #expect(value.cats[0].activeRest?.energyReward == 25)
        #expect(value.cats[0].activeRest?.endsAt == now.addingTimeInterval(9))
        _ = GameEngine.endCatRest(&value, catID: catID, sessionID: "pad", now: now.addingTimeInterval(4.5))
        #expect(value.cats[0].energy == 52 && value.cats[0].activeRest == nil)
        #expect(value.inventory == inventory && value.player.gold == 200)
        var stopped = value
        _ = GameEngine.synchronize(&stopped, now: now.addingTimeInterval(9))
        #expect(GameEngine.endCatRest(&value, catID: catID, sessionID: "pad", now: now.addingTimeInterval(5)).kind == .none)
        #expect(GameEngine.startCatRest(&value, catID: catID, furnitureID: "floorCushion", sessionID: "pad", now: now.addingTimeInterval(9)).kind == .none)
        #expect(value == stopped)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(9))
        #expect(value.cats[0].energy == 52)
    }

    @Test func offlineExpiryPaysAtMostOneRestAndThenResumesNormalDecay() {
        var value = state()
        value.cats[0].energy = 10
        _ = GameEngine.startCatRest(&value, catID: catID, furnitureID: "catBed", sessionID: "offline", now: now)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(912))
        #expect(value.cats[0].activeRest == nil)
        #expect(value.cats[0].energy == 28) // 10 + 21 - three post-rest decay intervals.
        var settled = value
        _ = GameEngine.synchronize(&settled, now: now.addingTimeInterval(1000))
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(912))
        _ = GameEngine.startCatRest(&value, catID: catID, furnitureID: "catBed", sessionID: "offline", now: now.addingTimeInterval(1000))
        #expect(value == settled)
    }

    @Test func duplicateStartAndLateExitCannotRestartOrEndAnotherSession() {
        var value = state()
        _ = GameEngine.startCatRest(&value, catID: catID, furnitureID: "catBed", sessionID: "first", now: now)
        var initial = value
        _ = GameEngine.synchronize(&initial, now: now.addingTimeInterval(4))
        _ = GameEngine.startCatRest(&value, catID: catID, furnitureID: "floorCushion", sessionID: "other", now: now.addingTimeInterval(3))
        _ = GameEngine.endCatRest(&value, catID: catID, sessionID: "stale", now: now.addingTimeInterval(4))
        #expect(value == initial)
        _ = GameEngine.endCatRest(&value, catID: catID, sessionID: "first", now: now.addingTimeInterval(6))
        _ = GameEngine.startCatRest(&value, catID: catID, furnitureID: "catBed", sessionID: "second", now: now.addingTimeInterval(6))
        var second = value
        _ = GameEngine.synchronize(&second, now: now.addingTimeInterval(10))
        _ = GameEngine.endCatRest(&value, catID: catID, sessionID: "first", now: now.addingTimeInterval(10))
        #expect(value == second)
        _ = GameEngine.endCatRest(&value, catID: catID, sessionID: "second", now: now.addingTimeInterval(10))
        #expect(value.cats[0].energy == 57)
    }

    @Test func onlyPlacedRestFurnitureAndValidSessionsCanStartRecovery() {
        var value = state()
        value.home.furniture.removeAll { $0.itemID == "catBed" }
        let before = value
        for item in ["missing", "catBed", "cabinet", "catTree", "wallFlower", "plantLarge"] {
            #expect(GameEngine.startCatRest(&value, catID: catID, furnitureID: item, now: now).messageKey == "rest.invalidFurniture")
            #expect(value == before)
        }
        #expect(!GameEngine.startCatRest(&value, catID: "missing", furnitureID: "floorCushion", now: now).succeeded)
        #expect(GameEngine.startCatRest(&value, catID: catID, furnitureID: "floorCushion", sessionID: " ", now: now).messageKey == "rest.invalidSession")
        #expect(!GameEngine.startSleep(&value, now: Date(timeIntervalSince1970: .nan)).succeeded)
        #expect(value == before)
    }

    @Test func failedCareKeepsRestButEverySuccessfulCareSettlesAndEndsIt() {
        for action in [ActionKind.feed, .clean, .play] {
            var value = state()
            value.inventory.food = 0
            value.inventory.litter = 0
            value.inventory.toys = 0
            _ = GameEngine.startCatRest(&value, catID: catID, furnitureID: "catBed", now: now)
            var before = value
            _ = GameEngine.synchronize(&before, now: now.addingTimeInterval(6))
            let failed: ActionOutcome
            switch action {
            case .feed: failed = GameEngine.feed(&value, catID: catID, now: now.addingTimeInterval(6))
            case .clean: failed = GameEngine.clean(&value, catID: catID, now: now.addingTimeInterval(6))
            default: failed = GameEngine.play(&value, catID: catID, now: now.addingTimeInterval(6))
            }
            #expect(!failed.succeeded && value == before)
            value.inventory.food = 1
            value.inventory.litter = 1
            value.inventory.toys = 1
            switch action {
            case .feed: _ = GameEngine.feed(&value, catID: catID, now: now.addingTimeInterval(6))
            case .clean: _ = GameEngine.clean(&value, catID: catID, now: now.addingTimeInterval(6))
            default: _ = GameEngine.play(&value, catID: catID, now: now.addingTimeInterval(6))
            }
            #expect(value.cats[0].activeRest == nil)
            #expect(value.cats[0].energy == (action == .play ? 40 : 50))
        }
    }

    @Test func invalidOrUnchangedLayoutKeepsRestWhileChangedLayoutSettlesItSafely() {
        var value = state()
        _ = GameEngine.startCatRest(&value, catID: catID, furnitureID: "catBed", now: now)
        var before = value
        _ = GameEngine.synchronize(&before, now: now.addingTimeInterval(6))
        var invalid = value.home.furniture
        invalid.append(invalid[0])
        #expect(!GameEngine.setRoomLayout(&value, bowlPosition: value.home.bowlPosition, furniture: invalid, now: now.addingTimeInterval(6)).succeeded)
        #expect(value == before)
        let bowl = value.home.bowlPosition, furniture = value.home.furniture
        _ = GameEngine.setRoomLayout(&value, bowlPosition: bowl, furniture: furniture, now: now.addingTimeInterval(6))
        #expect(value == before)
        let stored = furniture.filter { $0.itemID != "catBed" }
        _ = GameEngine.setRoomLayout(&value, bowlPosition: bowl, furniture: stored, now: now.addingTimeInterval(6))
        #expect(value.cats[0].activeRest == nil && value.cats[0].energy == 50)
        #expect(value.inventory == before.inventory && value.player.gold == before.player.gold)
        #expect(value.isValid)
    }

    @Test func sameFrameExitAndClockRollbackCannotManufactureCatEnergy() {
        var value = state()
        _ = GameEngine.startCatRest(&value, catID: catID, furnitureID: "catBed", sessionID: "zero", now: now)
        _ = GameEngine.endCatRest(&value, catID: catID, now: now)
        #expect(value.cats[0].energy == 40)
        _ = GameEngine.startCatRest(&value, catID: catID, furnitureID: "catBed", sessionID: "future", now: now.addingTimeInterval(100))
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(106))
        _ = GameEngine.endCatRest(&value, catID: catID, now: now.addingTimeInterval(50))
        #expect(value.cats[0].energy == 50)
        _ = GameEngine.startCatRest(&value, catID: catID, furnitureID: "catBed", sessionID: "after", now: now.addingTimeInterval(20))
        #expect(value.cats[0].activeRest?.startedAt == now.addingTimeInterval(106))
        let before = value
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(70))
        #expect(value == before)
    }

    @Test func directRestExitAdvancesClockBeforeASecondTokenWithoutPriorSync() {
        var value = state()
        _ = GameEngine.startCatRest(&value, catID: catID, furnitureID: "catBed", sessionID: "A", now: now)
        _ = GameEngine.endCatRest(&value, catID: catID, sessionID: "A", now: now.addingTimeInterval(6))
        #expect(value.cats[0].energy == 50)
        #expect(value.meta.lastSyncAt == now.addingTimeInterval(6))
        _ = GameEngine.startCatRest(&value, catID: catID, furnitureID: "catBed", sessionID: "B", now: now)
        #expect(value.cats[0].activeRest?.startedAt == now.addingTimeInterval(6))
        #expect(value.cats[0].activeRest?.endsAt == now.addingTimeInterval(18))
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(6))
        #expect(value.cats[0].energy == 50 && value.cats[0].activeRest?.energyGranted == 0)
        _ = GameEngine.endCatRest(&value, catID: catID, sessionID: "B", now: now)
        #expect(value.cats[0].energy == 50 && value.cats[0].activeRest == nil)
        #expect(value.meta.lastSyncAt == now.addingTimeInterval(6))
    }

    @Test func oldSchemaOneWithoutRestFieldsKeepsEveryExistingProgressField() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var expected = state()
        expected.player.gold = 321
        expected.player.completedWorkCount = 8
        expected.settings.language = .traditionalChinese
        expected.home.name = "我的小屋🐈"
        expected.home.furniture.removeLast()
        expected.inventory.food = 17
        expected.cats.append(CatState(id: "kept-cat", name: "小白", now: now))
        try await repository.save(expected)
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repository.saveURL)) as? [String: Any])
        var player = try #require(object["player"] as? [String: Any])
        for key in ["activeSleep", "sleepStaminaRemainder", "sleepMoodRemainder"] { player.removeValue(forKey: key) }
        object["player"] = player
        var cats = try #require(object["cats"] as? [[String: Any]])
        for index in cats.indices {
            cats[index].removeValue(forKey: "activeRest")
            cats[index].removeValue(forKey: "lastRestSessionID")
        }
        object["cats"] = cats
        let legacy = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try legacy.write(to: repository.saveURL)
        let loaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: now)
        #expect(loaded == expected)
        #expect(loaded.player.activeSleep == nil && loaded.cats.allSatisfy { $0.activeRest == nil })
        #expect(try Data(contentsOf: repository.saveURL) == legacy)
    }

    @Test func partialRestAndSleepSurviveRealSaveReloadAndColdStartEarlyExit() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var value = state()
        _ = GameEngine.startSleep(&value, now: now)
        _ = GameEngine.startCatRest(&value, catID: catID, furnitureID: "catBed", sessionID: "persisted", now: now)
        _ = GameEngine.synchronize(&value, now: now.addingTimeInterval(5))
        try await FileSaveRepository(directory: folder).save(value)
        var loaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: now.addingTimeInterval(9))
        #expect(loaded == value)
        _ = GameEngine.synchronize(&loaded, now: now.addingTimeInterval(9))
        _ = GameEngine.endCatRest(&loaded, catID: catID, now: now.addingTimeInterval(9))
        #expect(loaded.cats[0].energy == 55 && loaded.cats[0].activeRest == nil)
        #expect(loaded.player.activeSleep != nil && loaded.player.sleepStaminaRemainder == 9)
        try await FileSaveRepository(directory: folder).save(loaded)
        loaded = try await FileSaveRepository(directory: folder).loadOrCreate(now: now.addingTimeInterval(3600))
        _ = GameEngine.synchronize(&loaded, now: now.addingTimeInterval(3600))
        #expect(loaded.player.stamina == 40 && loaded.player.mood == 50)
        #expect(loaded.cats[0].energy == 44)
        let inventory = loaded.inventory
        let settled = loaded
        _ = GameEngine.startCatRest(&loaded, catID: catID, furnitureID: "catBed", sessionID: "persisted", now: now.addingTimeInterval(3600))
        #expect(loaded == settled && loaded.inventory == inventory)
    }

    @Test func awakeSleepRemainderSurvivesColdReloadAndRollbackWakeCannotAddPoints() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var value = state()
        _ = GameEngine.startSleep(&value, now: now)
        _ = GameEngine.wakeUp(&value, now: now.addingTimeInterval(90))
        try await FileSaveRepository(directory: folder).save(value)
        var restored = try await FileSaveRepository(directory: folder).loadOrCreate(now: now.addingTimeInterval(120))
        #expect(restored.player.activeSleep == nil && restored.player.sleepStaminaRemainder == 90)
        _ = GameEngine.startSleep(&restored, now: now.addingTimeInterval(120))
        _ = GameEngine.synchronize(&restored, now: now.addingTimeInterval(210))
        #expect(restored.player.stamina == 21 && restored.player.mood == 31)
        _ = GameEngine.wakeUp(&restored, now: now.addingTimeInterval(30))
        #expect(restored.player.stamina == 21 && restored.player.sleepStaminaRemainder == 0)
        _ = GameEngine.startSleep(&restored, now: now)
        #expect(restored.player.activeSleep?.startedAt == now.addingTimeInterval(210))
        _ = GameEngine.wakeUp(&restored, now: now.addingTimeInterval(100))
        #expect(restored.player.stamina == 21 && restored.player.mood == 31)
    }

    @Test func malformedRecoveryStateCannotOverwritePrimaryOrBackup() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = FileSaveRepository(directory: folder)
        var valid = state()
        try await repository.save(valid)
        valid.player.gold = 201
        try await repository.save(valid)
        let primary = try Data(contentsOf: repository.saveURL)
        let backup = try Data(contentsOf: repository.backupURL)
        var candidates: [GameSnapshot] = []
        for remainder in [-1.0, 180.0, .infinity, .nan] {
            var invalid = valid
            invalid.player.sleepStaminaRemainder = remainder
            candidates.append(invalid)
            invalid = valid
            invalid.player.sleepMoodRemainder = remainder
            candidates.append(invalid)
        }
        var both = valid
        both.player.activeSleep = PlayerSleep(startedAt: now)
        both.player.activeWork = ActiveWork(startedAt: now, endsAt: now.addingTimeInterval(120))
        candidates.append(both)
        var invalidRest = valid
        _ = GameEngine.startCatRest(&invalidRest, catID: catID, furnitureID: "catBed", sessionID: "invalid", now: now)
        invalidRest.cats[0].activeRest?.energyGranted = 26
        candidates.append(invalidRest)
        var resting = valid
        _ = GameEngine.startCatRest(&resting, catID: catID, furnitureID: "catBed", sessionID: "bad-shape", now: now)
        invalidRest = resting
        invalidRest.cats[0].activeRest?.endsAt = now.addingTimeInterval(9)
        candidates.append(invalidRest)
        invalidRest = resting
        invalidRest.home.furniture.removeAll { $0.itemID == "catBed" }
        candidates.append(invalidRest)
        invalidRest = resting
        invalidRest.cats[0].activeRest?.energyPausedUntil = now.addingTimeInterval(13)
        candidates.append(invalidRest)
        invalidRest = resting
        invalidRest.cats[0].lastRestSessionID = "different"
        candidates.append(invalidRest)
        var invalidSleep = valid
        invalidSleep.player.activeSleep = PlayerSleep(startedAt: Date(timeIntervalSince1970: .nan))
        candidates.append(invalidSleep)
        for invalid in candidates {
            #expect(!invalid.isValid)
            await #expect(throws: SaveRepositoryError.invalidSnapshot) { try await repository.save(invalid) }
            #expect(try Data(contentsOf: repository.saveURL) == primary)
            #expect(try Data(contentsOf: repository.backupURL) == backup)
        }
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CatRest17Tests-\(UUID().uuidString)")
    }
}
