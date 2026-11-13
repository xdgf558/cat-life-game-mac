#if os(macOS)
import XCTest
@testable import CatLifeMac

final class MacQuitWaitPolicyTests: XCTestCase {
    func testHungSettingsTaskAndBusyStoreBothReachTheSameFiveSecondDeadline() {
        for status in [(false, false), (true, true), (false, true)] {
            XCTAssertEqual(MacQuitWaitPolicy.outcome(settingsFinished: status.0, storeBusy: status.1,
                elapsed: .milliseconds(4_999)), .waiting)
            XCTAssertEqual(MacQuitWaitPolicy.outcome(settingsFinished: status.0, storeBusy: status.1,
                elapsed: .seconds(5)), .timedOut)
        }
    }
    func testFinishingSettingsDoesNotRestartTheDeadlineForTheStore() {
        XCTAssertEqual(MacQuitWaitPolicy.outcome(settingsFinished: false, storeBusy: false,
            elapsed: .seconds(4)), .waiting)
        XCTAssertEqual(MacQuitWaitPolicy.outcome(settingsFinished: true, storeBusy: true,
            elapsed: .seconds(5)), .timedOut)
    }
    func testBothCompletedProceedsWithoutWaitingForFiveSeconds() {
        XCTAssertEqual(MacQuitWaitPolicy.outcome(settingsFinished: true, storeBusy: false,
            elapsed: .zero), .ready)
    }
}
#endif
