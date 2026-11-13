#if os(macOS)
import XCTest
@testable import CatLifeMac

@MainActor
final class MacPreferencesTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "MacPreferencesTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
    func testDesktopSettingsPersistWithoutTouchingSaveData() {
        withDefaults { defaults in
            defaults.set("sentinel", forKey: "game-save")
            let preferences = MacPreferences(defaults: defaults)
            preferences.frameLimit = 30; preferences.interfaceScale = 1.25
            preferences.wheelReversed = true; preferences.alwaysOnTop = true
            let loaded = MacPreferences(defaults: defaults)
            XCTAssertEqual(loaded.frameLimit, 30)
            XCTAssertEqual(loaded.interfaceScale, 1.25)
            XCTAssertTrue(loaded.wheelReversed)
            XCTAssertTrue(loaded.alwaysOnTop)
            XCTAssertEqual(defaults.string(forKey: "game-save"), "sentinel")
        }
    }
    func testUnsupportedDisplayValuesAndCorruptPreferencesUseSafeDefaults() {
        withDefaults { defaults in
            let preferences = MacPreferences(defaults: defaults)
            preferences.frameLimit = 0; preferences.interfaceScale = .infinity
            XCTAssertEqual(preferences.frameLimit, 60)
            XCTAssertEqual(preferences.interfaceScale, 1)
            defaults.set(Data("{\"frameLimit\":999,\"interfaceScale\":0.2,\"windowMode\":\"unknown\"}".utf8), forKey: MacPreferences.storageKey)
            let loaded = MacPreferences(defaults: defaults)
            XCTAssertEqual(loaded.frameLimit, 60)
            XCTAssertEqual(loaded.interfaceScale, 1)
            XCTAssertEqual(loaded.windowMode, .windowed)
            XCTAssertFalse(loaded.notificationsEnabled)
        }
    }
    func testConflictingAndSystemReservedBindingsAreRejectedWithoutChangingPreviousBinding() {
        withDefaults { defaults in
            let preferences = MacPreferences(defaults: defaults)
            XCTAssertEqual(preferences.rebind(.feed, to: MacCommand.clean.defaultBinding), .duplicate(.clean))
            XCTAssertEqual(preferences.binding(for: .feed), MacCommand.feed.defaultBinding)
            XCTAssertEqual(preferences.rebind(.feed, to: MacKeyBinding(key: "q", modifiers: .command)), .reserved)
            XCTAssertEqual(preferences.rebind(.feed, to: MacKeyBinding(key: "unsupported")), .unsupported)
            XCTAssertNil(preferences.rebind(.settings, to: MacCommand.settings.defaultBinding))
        }
    }
    func testNonOverlappingScopesCanReuseAKeyAndLegalSwapSurvivesRestart() {
        withDefaults { defaults in
            let preferences = MacPreferences(defaults: defaults)
            XCTAssertNil(preferences.rebind(.feed, to: MacKeyBinding(key: "r")))
            XCTAssertNil(preferences.rebind(.clean, to: MacKeyBinding(key: "x")))
            XCTAssertNil(preferences.rebind(.play, to: MacCommand.clean.defaultBinding))
            XCTAssertNil(preferences.rebind(.clean, to: MacCommand.play.defaultBinding))
            let loaded = MacPreferences(defaults: defaults)
            XCTAssertEqual(loaded.binding(for: .feed), MacKeyBinding(key: "r"))
            XCTAssertEqual(loaded.binding(for: .play), MacCommand.clean.defaultBinding)
            XCTAssertEqual(loaded.binding(for: .clean), MacCommand.play.defaultBinding)
        }
    }
    func testInvalidStoredOverrideCannotCreateAConflictThroughItsFallback() throws {
        try withDefaults { defaults in
            let bindings = ["feed": MacKeyBinding(key: "q", modifiers: .command),
                            "clean": MacCommand.feed.defaultBinding, "play": MacCommand.clean.defaultBinding]
            let data = try JSONSerialization.data(withJSONObject: ["bindings": try JSONSerialization.jsonObject(with: JSONEncoder().encode(bindings))])
            defaults.set(data, forKey: MacPreferences.storageKey)
            let preferences = MacPreferences(defaults: defaults)
            for command in MacCommand.allCases {
                XCTAssertNil(MacPreferences.conflict(for: command, binding: preferences.binding(for: command), bindings: preferences.bindings))
            }
        }
    }
    func testInterfaceScaleKeepsEveryDesktopControlReachableInAScrollableCanvas() {
        for viewport in [CGSize(width: 1280, height: 720), CGSize(width: 1920, height: 1080), CGSize(width: 1440, height: 900)] {
            for scale in [1.0, 1.25, 1.5] {
                let layout = MacInterfaceLayout(viewport: viewport, scale: scale)
                XCTAssertGreaterThanOrEqual(layout.canvasSize.width, 1280)
                XCTAssertGreaterThanOrEqual(layout.canvasSize.height, 720)
                XCTAssertGreaterThanOrEqual(layout.displayedSize.width, viewport.width)
                XCTAssertGreaterThanOrEqual(layout.displayedSize.height, viewport.height)
                XCTAssertEqual(layout.displayedSize.width, layout.canvasSize.width * scale, accuracy: 0.001)
                XCTAssertEqual(layout.displayedSize.height, layout.canvasSize.height * scale, accuracy: 0.001)
            }
        }
        let enlarged = MacInterfaceLayout(viewport: CGSize(width: 1280, height: 720), scale: 1.5)
        XCTAssertEqual(enlarged.displayedSize, CGSize(width: 1920, height: 1080))
    }
    func testWorkNotificationRequiresThePreviouslyRunningJobAndOnlyFiresOnce() {
        let generation = UUID()
        var tracker = MacWorkNotificationTracker()
        XCTAssertNil(tracker.observe(.init(generation: generation, activeWorkID: nil, completedWorkID: "old")))
        XCTAssertNil(tracker.observe(.init(generation: generation, activeWorkID: "new", completedWorkID: "old")))
        let finished = MacWorkNotificationState(generation: generation, activeWorkID: nil, completedWorkID: "new")
        XCTAssertEqual(tracker.observe(finished), "new")
        XCTAssertNil(tracker.observe(finished))
        XCTAssertNil(tracker.observe(.init(generation: generation, activeWorkID: "canceled", completedWorkID: "new")))
        XCTAssertNil(tracker.observe(.init(generation: generation, activeWorkID: nil, completedWorkID: "new")))
    }
    func testImportedAndLoadedWorkHistoryDoesNotPostCompletionNotifications() {
        let generation = UUID(), imported = UUID()
        var tracker = MacWorkNotificationTracker()
        tracker.reset(.init(generation: generation, activeWorkID: "work", completedWorkID: nil))
        XCTAssertNil(tracker.observe(.init(generation: imported, activeWorkID: nil, completedWorkID: "work")))
        XCTAssertNil(tracker.observe(.init(generation: imported, activeWorkID: "loaded", completedWorkID: "work", isRestoring: true)))
        XCTAssertNil(tracker.observe(.init(generation: imported, activeWorkID: nil, completedWorkID: "loaded")))
        XCTAssertNil(tracker.observe(.init(generation: imported, activeWorkID: "real", completedWorkID: "loaded")))
        XCTAssertEqual(tracker.observe(.init(generation: imported, activeWorkID: nil, completedWorkID: "real")), "real")
    }
    func testResetShortcutsDoesNotResetDisplayPreferences() {
        withDefaults { defaults in
            let preferences = MacPreferences(defaults: defaults)
            preferences.frameLimit = 120
            XCTAssertNil(preferences.rebind(.feed, to: MacKeyBinding(key: "x")))
            preferences.restoreShortcuts()
            XCTAssertEqual(preferences.binding(for: .feed), MacCommand.feed.defaultBinding)
            XCTAssertEqual(preferences.frameLimit, 120)
        }
    }
}
#endif
