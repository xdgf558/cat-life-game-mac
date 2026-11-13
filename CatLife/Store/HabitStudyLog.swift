import Foundation

/// Optional local diagnostics contain internal IDs only, never names, pictures or device identifiers.
actor HabitStudyLog {
    struct Entry: Codable, Sendable {
        let date: Date
        let event: String
        let catID: String
        let sessionID: String?
        let detail: String?
        let control: String?
        let duration: Double?
        init(event: String, catID: String, sessionID: String?, detail: String?, control: String?, duration: Double?, date: Date = Date()) {
            self.date = date; self.event = event; self.catID = catID; self.sessionID = sessionID
            self.detail = detail; self.control = control; self.duration = duration
        }
    }
    private let url: URL
    private var entries: [Entry]?
    init(directory: URL? = nil) {
        #if os(macOS)
        let saveDirectory = directory ?? NativeSaveLocation.currentDirectory
        url = saveDirectory.appendingPathComponent("HabitStudy", isDirectory: true)
            .appendingPathComponent("observations.json")
        #else
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if DEBUG
        let folder = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "CatLife-UITests-HabitStudy" : "CatLife-HabitStudy"
        #else
        let folder = "CatLife-HabitStudy"
        #endif
        url = base.appendingPathComponent(folder, isDirectory: true).appendingPathComponent("observations.json")
        #endif
    }
    func append(_ entry: Entry) throws {
        try load()
        var candidate = entries ?? []
        candidate.append(entry)
        if candidate.count > 2000 { candidate.removeFirst(candidate.count - 2000) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded(candidate).write(to: url, options: .atomic)
        entries = candidate
    }
    func export() throws -> Data { try load(); return try encoded(entries ?? []) }
    func clear() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded([]).write(to: url, options: .atomic)
        entries = []
    }
    private func load() throws {
        guard entries == nil else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { entries = []; return }
        let data = try Data(contentsOf: url)
        guard data.count <= 2 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        entries = try JSONDecoder().decode([Entry].self, from: data)
    }
    private func encoded(_ entries: [Entry]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entries)
    }
}
