#if os(macOS)
import XCTest
import CatGameCore
@testable import CatLifeMac

@MainActor
final class MacWorkPersistenceTests: XCTestCase {
    func testFailedCancellationKeepsTheShiftThenRetryCommitsItWithoutPaying() async throws {
        let suite = "MacWorkPersistenceTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Date()
        var state = GameSnapshot.fresh(now: date)
        XCTAssertTrue(GameEngine.startWork(&state, now: date).succeeded)
        let repository = MacWorkTestRepository(state)
        let store = GameStore(repository: repository, reminderDefaults: defaults)
        await store.load()
        let before = try XCTUnwrap(store.snapshot)
        await repository.setFailing(true)
        let failed = await store.cancelWork()
        XCTAssertFalse(failed)
        XCTAssertEqual(store.snapshot, before)
        let diskBefore = await repository.value
        XCTAssertEqual(diskBefore.player.activeWork, before.player.activeWork)
        await repository.setFailing(false)
        let saved = await store.cancelWork()
        XCTAssertTrue(saved)
        XCTAssertNil(store.snapshot?.player.activeWork)
        XCTAssertEqual(store.snapshot?.player.completedWorkCount, before.player.completedWorkCount)
        XCTAssertEqual(store.snapshot?.player.gold, before.player.gold)
        let diskAfter = await repository.value
        XCTAssertNil(diskAfter.player.activeWork)
    }
    func testMacLocalisationIncludesEveryNewKeyInEachLanguage() {
        let groups = [
            [GameStrings.macShellChinese, GameStrings.macShellTraditional, GameStrings.macShellEnglish],
            [GameStrings.macSettingsChinese, GameStrings.macSettingsTraditional, GameStrings.macSettingsEnglish],
            [GameStrings.macContent69Chinese, GameStrings.macContent69TraditionalChinese, GameStrings.macContent69English]
        ]
        for group in groups {
            let keys = Set(group[0].keys)
            for dictionary in group {
                XCTAssertEqual(Set(dictionary.keys), keys)
                XCTAssertTrue(dictionary.values.allSatisfy { !$0.isEmpty })
            }
        }
        XCTAssertEqual(AppVersion.current.version, "0.24.0")
        XCTAssertEqual(AppVersion.current.build, "69")
        XCTAssertEqual(AppRelease.recent.map(\.build), [69, 68, 67])
    }
}
private actor MacWorkTestRepository: GameSaveRepository {
    var value: GameSnapshot
    var lastLoadDisposition: SaveLoadDisposition { .loaded }
    func checkWritable() throws { if failing { throw CocoaError(.fileWriteOutOfSpace) } }
    var failing = false
    init(_ value: GameSnapshot) { self.value = value }
    func loadOrCreate(now: Date) -> GameSnapshot { value }
    func save(_ snapshot: GameSnapshot) throws {
        if failing { throw CocoaError(.fileWriteOutOfSpace) }
        value = snapshot
    }
    func setFailing(_ value: Bool) { failing = value }
}
#endif
