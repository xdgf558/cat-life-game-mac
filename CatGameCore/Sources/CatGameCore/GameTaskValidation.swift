import Foundation

extension GameTaskState {
    var isValid: Bool {
        guard [dailyWorkCount, dailyFeedCount, dailyPlayCount, dailyCleanCount, totalCleanCount, totalFeedCount, furniturePurchaseCount]
            .allSatisfy({ (0...GameSnapshot.maximumGold).contains($0) }),
              dailyFeedCount <= totalFeedCount, dailyCleanCount <= totalCleanCount,
              Set(claimedTaskIDs).count == claimedTaskIDs.count,
              Set(dailyClaimedTaskIDs).count == dailyClaimedTaskIDs.count,
              claimedTaskIDs.allSatisfy({ id in
                  GameTaskCatalog.task(id: id).map { $0.category != .daily } ?? false
              }),
              dailyClaimedTaskIDs.allSatisfy({ id in
                  GameTaskCatalog.task(id: id)?.category == .daily
              }) else { return false }
        guard let key = dailyDayKey else {
            return dailyWorkCount == 0 && dailyFeedCount == 0 && dailyPlayCount == 0 && dailyCleanCount == 0 && dailyClaimedTaskIDs.isEmpty
        }
        let pieces = key.split(separator: "-", omittingEmptySubsequences: false)
        guard key.utf8.count == 10, pieces.count == 3,
              let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return false }
        return Self.dayKey(for: date, timeZone: calendar.timeZone) == key
    }
}
