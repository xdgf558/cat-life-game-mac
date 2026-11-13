#if os(macOS)
import XCTest
import AppKit

/// Real desktop controls; DEBUG launch flags select CatLifeMac-UITests storage.
@MainActor
final class MacDesktopUITests: XCTestCase {
    private var app: XCUIApplication!
    private func launchFreshHome() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-test-save", "--skip-onboarding", "--skip-welcome"]
        app.launch()
        XCTAssertTrue(control("macHomePage").waitForExistence(timeout: 60),
                      "Resource preparation must reach the real desktop home.")
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    private func finishTest() {
        if let app, app.state != .notRunning {
            attach("Desktop - final state")
            app.terminate()
        }
        app = nil
    }

    func testDesktopNavigationAndPlayChoiceCancellation() async throws {
        defer { finishTest() }
        try await launchFreshHome()
        click("macPlay")
        XCTAssertTrue(control("playChoicesSheet68").waitForExistence(timeout: 10))
        XCTAssertTrue(control("quickPlayChoice").exists)
        XCTAssertTrue(control("playTogetherChoice").exists)
        attach("Desktop - quick play and play together choices")
        app.typeKey(.escape, modifierFlags: [])
        waitUntilGone("playChoicesSheet68")
        XCTAssertTrue(control("macHomePage").exists)

        let destinations = [
            ("work", "macWorkPage"), ("shop", "macShopPage"),
            ("town", "macTownPage"), ("cats", "macCatsPage"),
            ("settings", "macSettingsContent"), ("home", "macHomePage")
        ]
        for (page, identifier) in destinations {
            click("macNav_" + page)
            XCTAssertTrue(control(identifier).waitForExistence(timeout: 15), "The navigation rail must open \(page).")
            attach("Desktop - " + page)
        }
        // Returning to a retained scene must restore the room-idle gate, not just show a sheet.
        click("macPlay")
        click("playTogetherChoice")
        XCTAssertTrue(control("playTogetherStage").waitForExistence(timeout: 15))
        attach("Desktop - play together after returning home")
        click("playTogetherClose")
        XCTAssertTrue(control("playTogetherResult").waitForExistence(timeout: 10))
        click("playTogetherFinishButton")
        XCTAssertTrue(control("macHomePage").waitForExistence(timeout: 10))
    }

    func testPlayerCanSleepAndWakeUpFromTheWorkPage() async throws {
        defer { finishTest() }
        try await launchFreshHome()
        click("macNav_work")
        click("macWorkRest")
        XCTAssertTrue(control("macWorkRestSheet").waitForExistence(timeout: 10))
        click("sleepStartButton")
        XCTAssertTrue(control("sleepWakeButton").waitForExistence(timeout: 10))
        attach("Desktop - player resting")
        click("sleepWakeButton")
        XCTAssertTrue(control("sleepStartButton").waitForExistence(timeout: 10))
        click("macWorkRestClose")
        waitUntilGone("macWorkRestSheet")
        XCTAssertTrue(control("macStartWork").isEnabled)
    }

    func testRoomArrangementEntersAndCancelsWithoutSaving() async throws {
        defer { finishTest() }
        try await launchFreshHome()
        click("macDecorate")
        XCTAssertTrue(control("macBuildView").waitForExistence(timeout: 15))
        XCTAssertTrue(control("macBuildSave").exists)
        XCTAssertTrue(control("macBuildGrid").exists)
        attach("Desktop - furniture arrangement")
        click("macBuildCancel")
        waitUntilGone("macBuildView")
        XCTAssertTrue(control("macHomePage").waitForExistence(timeout: 10))
        XCTAssertTrue(control("macDecorate").isEnabled)
        attach("Desktop - arrangement cancelled")
    }

    func testSupportedMinimumWindowUsesRealDisplaySetting() async throws {
        defer { finishTest() }
        try await launchFreshHome()
        click("macNav_settings")
        XCTAssertTrue(control("macSettingsContent").waitForExistence(timeout: 10))
        click("macSettingsTab_display")
        click("macWindowSize")
        let minimum = app.menuItems["1280 × 720"].firstMatch
        XCTAssertTrue(minimum.waitForExistence(timeout: 5), "Use the same window-size menu as a player.")
        minimum.click()

        let window = app.windows.firstMatch
        let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(window.frame.width - 1280) <= 2 && window.frame.height >= 720 && window.frame.height <= 770
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 10), .completed,
                       "The native frame must contain 1280×720 content plus title-bar chrome, rather than a scaled screenshot.")
        attach("Desktop - minimum window settings")
        click("macNav_home")
        XCTAssertTrue(control("macHomePage").waitForExistence(timeout: 10))
        for id in ["macDecorate", "macFeed", "macClean", "macPlay"] {
            XCTAssertTrue(control(id).isHittable, "\(id) must remain reachable at the minimum window size.")
        }
        attach("Desktop - 1280 by 720 home content")
    }

    private func control(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private func click(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = control(identifier)
        XCTAssertTrue(element.waitForExistence(timeout: 15), "Missing \(identifier)", file: file, line: line)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.isEnabled && element.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, "Unavailable \(identifier)", file: file, line: line)
        element.click()
    }
    private func waitUntilGone(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in self?.control(identifier).exists == false }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, "Still showing \(identifier)", file: file, line: line)
    }
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
