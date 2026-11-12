#if os(macOS)
import XCTest
import CatGameCore
@testable import CatLifeMac

@MainActor
final class MacCatUrgencyTrackerTests: XCTestCase {
    private let generation = UUID()
    private func state(hungry: Bool = false, ill: Bool = false,
                       restoring: Bool = false, generation: UUID? = nil) -> MacCatUrgencyState {
        .init(generation: generation ?? self.generation,
              cats: [.init(id: "cat", hungry: hungry, ill: ill)], isRestoring: restoring)
    }
    func testHungerUsesTheExistingRoomNeedBoundary() {
        var cat = GameSnapshot.fresh(now: Date()).cats[0]
        cat.satiety = 50
        XCTAssertFalse(MacCatUrgencySample(cat: cat).hungry)
        cat.satiety = 49
        XCTAssertTrue(MacCatUrgencySample(cat: cat).hungry)
    }
    func testFirstLoadAndImportedHistoryNeverNotify() {
        var tracker = MacCatUrgencyTracker()
        XCTAssertTrue(tracker.observe(state(hungry: true), isInBackground: true, notificationsEnabled: true).isEmpty)
        tracker.reset(state())
        XCTAssertTrue(tracker.observe(state(ill: true, generation: UUID()), isInBackground: true, notificationsEnabled: true).isEmpty)
        tracker.reset(state(restoring: true))
        XCTAssertTrue(tracker.observe(state(hungry: true), isInBackground: true, notificationsEnabled: true).isEmpty)
    }
    func testUrgencyTransitionNotifiesOnceUntilTheCatRecovers() {
        var tracker = MacCatUrgencyTracker()
        tracker.reset(state())
        let expected = [MacCatUrgencyNotice(catID: "cat", kind: .hunger)]
        XCTAssertEqual(tracker.observe(state(hungry: true), isInBackground: true, notificationsEnabled: true), expected)
        XCTAssertTrue(tracker.observe(state(hungry: true), isInBackground: true, notificationsEnabled: true).isEmpty)
        XCTAssertTrue(tracker.observe(state(), isInBackground: true, notificationsEnabled: true).isEmpty)
        XCTAssertEqual(tracker.observe(state(hungry: true), isInBackground: true, notificationsEnabled: true), expected)
    }
    func testForegroundAndDisabledNotificationsConsumeTheTransitionWithoutBackfill() {
        for inBackground in [false, true] {
            var tracker = MacCatUrgencyTracker()
            tracker.reset(state())
            XCTAssertTrue(tracker.observe(state(hungry: true), isInBackground: inBackground, notificationsEnabled: !inBackground).isEmpty)
            XCTAssertTrue(tracker.observe(state(hungry: true), isInBackground: true, notificationsEnabled: true).isEmpty)
        }
    }
    func testIllnessTakesPriorityWhenBothNeedsBecomeUrgentAndHungerIsNotReplayedAfterTreatment() {
        var tracker = MacCatUrgencyTracker()
        tracker.reset(state())
        XCTAssertEqual(tracker.observe(state(hungry: true, ill: true), isInBackground: true, notificationsEnabled: true),
                       [.init(catID: "cat", kind: .illness)])
        XCTAssertTrue(tracker.observe(state(hungry: true), isInBackground: true, notificationsEnabled: true).isEmpty)
        XCTAssertEqual(tracker.observe(state(hungry: true, ill: true), isInBackground: true, notificationsEnabled: true),
                       [.init(catID: "cat", kind: .illness)])
    }
    func testNewCatStartsWithABaselineAndExistingCatsRemainIndependent() {
        var tracker = MacCatUrgencyTracker()
        tracker.reset(state())
        let both = MacCatUrgencyState(generation: generation,
            cats: [.init(id: "cat", hungry: true, ill: false), .init(id: "new", hungry: true, ill: true)])
        XCTAssertEqual(tracker.observe(both, isInBackground: true, notificationsEnabled: true),
                       [.init(catID: "cat", kind: .hunger)])
        XCTAssertTrue(tracker.observe(both, isInBackground: true, notificationsEnabled: true).isEmpty)
    }
}
#endif
