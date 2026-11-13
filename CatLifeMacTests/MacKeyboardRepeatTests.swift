#if os(macOS)
import XCTest
@testable import CatLifeMac

@MainActor
final class MacKeyboardRepeatTests: XCTestCase {
    private func withPreferences(_ body: (MacPreferences) throws -> Void) rethrows {
        let name = "MacKeyboardRepeatTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(MacPreferences(defaults: defaults))
    }

    func testHoldingAnActionKeyCallsTheHandlerOnlyOnce() {
        withPreferences { preferences in
            for command in MacCommand.allCases where !command.acceptsKeyRepeat {
                var actions = 0
                let router = MacKeyboardRouter(preferences: preferences) { candidate in
                    guard candidate == command else { return false }
                    actions += 1; return true
                }
                let key = preferences.binding(for: command)
                XCTAssertTrue(router.dispatch(key, isRepeat: false))
                for _ in 0..<30 { XCTAssertTrue(router.dispatch(key, isRepeat: true)) }
                XCTAssertEqual(actions, 1, "Holding \(command) must not repeat a purchase, care action or selection.")
            }
        }
    }

    func testListSelectionAndCanvasNudgesCanStillRepeat() {
        withPreferences { preferences in
            for command in MacCommand.allCases where command.acceptsKeyRepeat {
                var actions = 0
                let router = MacKeyboardRouter(preferences: preferences) { candidate in
                    guard candidate == command else { return false }
                    actions += 1; return true
                }
                for _ in 0..<15 { router.dispatch(preferences.binding(for: command), isRepeat: true) }
                XCTAssertEqual(actions, 15)
            }
        }
    }

    func testRepeatingListKeyStillWorksWhenAHomeActionUsesTheSameBinding() {
        withPreferences { preferences in
            let key = preferences.binding(for: .listUp)
            XCTAssertNil(preferences.rebind(.feed, to: key))
            var listMoves = 0, careActions = 0
            let router = MacKeyboardRouter(preferences: preferences) { command in
                if command == .feed { careActions += 1; return false }
                if command == .listUp { listMoves += 1; return true }
                return false
            }
            for _ in 0..<15 { router.dispatch(key, isRepeat: true) }
            XCTAssertEqual(careActions, 0)
            XCTAssertEqual(listMoves, 15)
        }
    }

    func testNativeFocusKeysRemainAvailableAndRepeatedActivationIsSwallowed() {
        withPreferences { preferences in
            let router = MacKeyboardRouter(preferences: preferences) { _ in XCTFail("Native focus must win"); return true }
            for key in ["tab", "space", "return"] {
                XCTAssertFalse(router.dispatch(.init(key: key), isRepeat: false, nativeNavigation: true))
                XCTAssertNotNil(preferences.rebind(.feed, to: .init(key: key)))
            }
            for key in ["return", "space"] {
                XCTAssertTrue(router.dispatch(.init(key: key), isRepeat: true, nativeNavigation: true))
            }
            for key in ["up", "down", "left", "right"] {
                XCTAssertTrue(MacKeyboardRouter.yieldsToNativeNavigation(.init(key: key), canvasFocused: false, controlFocused: true))
                XCTAssertFalse(MacKeyboardRouter.yieldsToNativeNavigation(.init(key: key), canvasFocused: true, controlFocused: false))
            }
        }
    }
}
#endif
