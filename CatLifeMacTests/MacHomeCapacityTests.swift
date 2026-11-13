#if os(macOS)
import XCTest
import CatGameCore
@testable import CatLifeMac

@MainActor
final class MacHomeCapacityTests: XCTestCase {
    func testStoreAndUpgradeSummariesUseMacLimitsWithoutLoadingOrRepairingALayout() throws {
        let suite = "MacHomeCapacityTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GameStore(repository: MacCapacityRepository(GameSnapshot.fresh(now: Date())),
                              reminderDefaults: defaults)
        XCTAssertEqual(store.homeLayoutRules, .macDesktop)
        XCTAssertEqual(store.furnitureCapacity, 16)
        XCTAssertEqual(store.furnitureCapacity(on: .upper), 0)
        for room in HomeCatalog.all {
            XCTAssertEqual(store.floorFurnitureCapacity(for: room), room.floorCapacity + 7)
            XCTAssertEqual(store.totalFurnitureCapacity(for: room), (room.floorCapacity + 7) * room.floors.count)
        }
        let celebration = HomeUpgradeCelebration(level: 6, rules: store.homeLayoutRules)
        XCTAssertEqual(HomeCatalog.level(celebration.level)?.capacity(using: celebration.rules), 62)
    }
}

private actor MacCapacityRepository: GameSaveRepository {
    var value: GameSnapshot
    var lastLoadDisposition: SaveLoadDisposition { .loaded }
    init(_ value: GameSnapshot) { self.value = value }
    func loadOrCreate(now: Date) -> GameSnapshot { value }
    func save(_ snapshot: GameSnapshot) { value = snapshot }
    func checkWritable() {}
}
#endif
