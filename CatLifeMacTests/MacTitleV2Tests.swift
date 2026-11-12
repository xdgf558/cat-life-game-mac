#if os(macOS)
import XCTest
@testable import CatLifeMac

@MainActor
final class MacTitleV2Tests: XCTestCase {
    func testMenuAndRoomFitTheReferenceWindowSizes() {
        for size in [CGSize(width: 1280, height: 720), CGSize(width: 1440, height: 900),
                     CGSize(width: 2560, height: 1600), CGSize(width: 2520, height: 1080)] {
            let layout = MacTitleLayoutV2(size: size)
            XCTAssertGreaterThanOrEqual(layout.menuX, 0)
            XCTAssertLessThanOrEqual(layout.menuY + layout.menuHeight, size.height - 60)
            XCTAssertLessThanOrEqual(layout.menuX + layout.menuWidth, size.width)
            XCTAssertGreaterThan(layout.room.width, 0)
            XCTAssertGreaterThan(layout.room.height, 0)
            XCTAssertLessThanOrEqual(layout.room.maxX, size.width)
            XCTAssertLessThanOrEqual(layout.room.maxY, size.height)
        }
    }
    func testLoadingPawsUseActualProgressAndClampBeforeIntegerConversion() {
        for (progress, count) in [(0.0, 0), (1.0 / 3, 2), (2.0 / 3, 4), (1.0, 5), (-1.0, 0), (1e300, 5)] {
            XCTAssertEqual(MacTitleMetricsV2.litPaws(progress: progress), count)
        }
        XCTAssertEqual(MacTitleMetricsV2.litPaws(progress: .nan), 0)
    }
    func testNightSwitchesAtNineteenAndSixInLocalCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for (hour, expected) in [(5, true), (6, false), (18, false), (19, true), (23, true)] {
            let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: hour))!
            XCTAssertEqual(MacTitleMetricsV2.isNight(at: date, calendar: calendar), expected)
        }
    }
    func testHomeDayUsesRealCalendarDaysAndCannotBecomeNegative() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let created = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 23))!
        let next = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 1))!
        XCTAssertEqual(MacTitleMetricsV2.dayNumber(createdAt: created, at: next, calendar: calendar), 12)
        XCTAssertEqual(MacTitleMetricsV2.dayNumber(createdAt: created, at: created.addingTimeInterval(-100_000), calendar: calendar), 1)
    }
}
#endif
