import Foundation

struct AppVersion: Sendable {
    let version: String
    let build: String
    static let current = AppVersion(
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
        build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
    var display: String { "\(version) (\(build))" }
    var buildNumber: Int { Int(build) ?? 0 }
    @MainActor var localizedDisplay: String { GameStrings.format("settings.versionFormat", version, build) }
}

struct AppRelease: Identifiable, Sendable {
    let build: Int
    let version: String
    let date: String
    var id: Int { build }

    // Keep release history as data. Only the latest three entries for this
    // installed binary are rendered; older entries have no hidden UI elements.
    private static let history: [AppRelease] = [
        .init(build: 69, version: "0.24.0", date: "2026-11-12"),
        .init(build: 68, version: "0.23.0", date: "2026-11-11"),
        .init(build: 67, version: "0.22.0", date: "2026-11-10"),
        .init(build: 66, version: "0.21.1", date: "2026-11-10"),
        .init(build: 65, version: "0.21.0", date: "2026-11-10"),
        .init(build: 64, version: "0.20.1", date: "2026-11-10"),
        .init(build: 62, version: "0.20.0", date: "2026-11-10"),
        .init(build: 61, version: "0.19.1", date: "2026-11-09"),
        .init(build: 60, version: "0.19.0", date: "2026-11-09"),
        .init(build: 59, version: "0.18.0", date: "2026-11-08"),
        .init(build: 58, version: "0.17.0", date: "2026-11-08"),
        .init(build: 57, version: "0.16.0", date: "2026-11-07"),
        .init(build: 56, version: "0.15.2", date: "2026-11-07"),
        .init(build: 55, version: "0.15.1", date: "2026-11-07"),
        .init(build: 54, version: "0.15.0", date: "2026-11-07"),
        .init(build: 53, version: "0.14.1", date: "2026-11-07"),
        .init(build: 49, version: "0.13.3", date: "2026-11-06"),
        .init(build: 44, version: "0.12.1", date: "2026-11-05"),
        .init(build: 43, version: "0.12.0", date: "2026-11-04"),
        .init(build: 42, version: "0.11.2", date: "2026-11-04"),
        .init(build: 41, version: "0.11.1", date: "2026-11-04"),
        .init(build: 40, version: "0.11.0", date: "2026-11-04"),
        .init(build: 39, version: "0.10.1", date: "2026-11-04"),
        .init(build: 38, version: "0.10.0", date: "2026-11-04"),
        .init(build: 37, version: "0.9.2", date: "2026-11-04"),
        .init(build: 36, version: "0.9.1", date: "2026-11-04"),
        .init(build: 35, version: "0.9.0", date: "2026-11-04"),
        .init(build: 34, version: "0.8.1", date: "2026-11-03"),
        .init(build: 33, version: "0.8.0", date: "2026-11-03"),
        .init(build: 32, version: "0.7.1", date: "2026-11-03"),
        .init(build: 31, version: "0.7.0", date: "2026-11-03"),
        .init(build: 30, version: "0.6.2", date: "2026-11-03"),
        .init(build: 29, version: "0.6.1", date: "2026-11-03"),
        .init(build: 28, version: "0.6.0", date: "2026-11-03"),
        .init(build: 27, version: "0.5.4", date: "2026-11-03"),
        .init(build: 26, version: "0.5.3", date: "2026-11-02"),
        .init(build: 25, version: "0.5.2", date: "2026-11-02"),
        .init(build: 24, version: "0.5.1", date: "2026-11-02"),
        .init(build: 23, version: "0.5.0", date: "2026-11-02"),
        .init(build: 22, version: "0.4.3", date: "2026-11-02"),
        .init(build: 21, version: "0.4.2", date: "2026-11-02"),
        .init(build: 20, version: "0.4.1", date: "2026-11-02"),
        .init(build: 19, version: "0.4.0", date: "2026-11-02"),
        .init(build: 18, version: "0.3.0", date: "2026-11-02"),
        .init(build: 17, version: "0.2.0", date: "2026-11-01"),
        .init(build: 16, version: "0.1.3", date: "2026-11-01"),
        .init(build: 15, version: "0.1.2", date: "2026-11-01"),
        .init(build: 14, version: "0.1.1", date: "2026-11-01"),
        .init(build: 13, version: "0.1.0", date: "2026-11-01"),
        .init(build: 12, version: "0.1.0", date: "2026-11-01"),
        .init(build: 11, version: "0.1.0", date: "2026-11-01"),
        .init(build: 10, version: "0.1.0", date: "2026-10-31")
    ]
    static var recent: [AppRelease] {
        Array(history.filter { $0.build <= AppVersion.current.buildNumber }
            .sorted { $0.build > $1.build }.prefix(3))
    }

    @MainActor var localizedDate: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let value = parser.date(from: date) else { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: GameLocalization.shared.language.rawValue)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        return formatter.string(from: value)
    }
}
