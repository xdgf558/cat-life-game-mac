#if os(macOS)
import XCTest
@testable import CatLifeMac

final class MacTownViewportTests: XCTestCase {
    func testUnzoomedMapCannotBeDraggedOutOfView() {
        XCTAssertEqual(MacTownViewport69.clamped(CGSize(width: 900, height: -500), size: CGSize(width: 800, height: 600), scale: 1), .zero)
    }

    func testZoomedPanKeepsAllViewportEdgesInsideTheMap() {
        let size = CGSize(width: 800, height: 600)
        XCTAssertEqual(MacTownViewport69.clamped(CGSize(width: 900, height: -500), size: size, scale: 2), CGSize(width: 400, height: -300))
        XCTAssertEqual(MacTownViewport69.clamped(CGSize(width: -35, height: 60), size: size, scale: 1.5), CGSize(width: -35, height: 60))
    }

    @MainActor func testAllPlacesHaveDistinctVisiblePositionsAndThreeLanguageLabels() {
        let positions = TownPlace.allCases.map(MacTownViewport69.position)
        XCTAssertEqual(Set(positions.map { "\($0.x),\($0.y)" }).count, TownPlace.allCases.count)
        XCTAssertTrue(positions.allSatisfy { (0.05...0.95).contains($0.x) && (0.05...0.95).contains($0.y) })
        XCTAssertEqual(Set(GameStrings.macContent69Chinese.keys), Set(GameStrings.macContent69English.keys))
        XCTAssertEqual(Set(GameStrings.macContent69Chinese.keys), Set(GameStrings.macContent69TraditionalChinese.keys))
        for key in GameStrings.macContent69English.keys {
            XCTAssertFalse(GameStrings.macContent69Chinese[key, default: ""].isEmpty)
            XCTAssertFalse(GameStrings.macContent69TraditionalChinese[key, default: ""].isEmpty)
        }
    }
}
#endif
