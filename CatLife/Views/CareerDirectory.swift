import Foundation
import CatGameCore

/// Presentation-only filtering and bounded pages; no job choice or save mutation.
enum CareerDirectory {
    enum Filter: String, CaseIterable { case all, available, locked }
    static let pageSize = 4

    static func matching(_ jobs: [WorkJob], level: Int, query: String, filter: Filter,
                         locale: Locale, name: (WorkJob) -> String) -> [WorkJob] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return jobs.filter { job in
            let unlocked = level >= job.unlockLevel
            let included = filter == .all || (filter == .available ? unlocked : !unlocked)
            return included && (query.isEmpty || name(job).range(of: query,
                options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil)
        }
    }

    static func pageCount(for count: Int) -> Int {
        count > 0 ? (count - 1) / pageSize + 1 : 1
    }

    static func clampedPage(_ page: Int, count: Int) -> Int {
        min(max(0, page), pageCount(for: count) - 1)
    }

    static func pageRange(_ page: Int, count: Int) -> Range<Int> {
        let count = max(0, count)
        let lower = clampedPage(page, count: count) * pageSize
        return lower..<(lower + min(pageSize, count - lower))
    }
}
