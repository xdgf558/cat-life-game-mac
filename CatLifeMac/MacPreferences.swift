#if os(macOS)
import Foundation
import Observation

enum MacWindowMode: String, CaseIterable, Codable, Sendable {
    case windowed, borderless, fullscreen
    var titleKey: String { "mac.settings.window." + rawValue }
}

/// Desktop presentation preferences stay separate from earned game progress.
@MainActor
@Observable
final class MacPreferences {
    static let storageKey = "catlife.mac.preferences.v1"
    @ObservationIgnored private let defaults: UserDefaults
    private var state: State { didSet { persist() } }
    var frameLimit: Int { get { state.frameLimit } set { if [30, 60, 120].contains(newValue) { state.frameLimit = newValue } } }
    var interfaceScale: Double { get { state.interfaceScale } set { if [1.0, 1.25, 1.5].contains(newValue) { state.interfaceScale = newValue } } }
    var windowMode: MacWindowMode { get { state.windowMode } set { state.windowMode = newValue } }
    var wheelReversed: Bool { get { state.wheelReversed } set { state.wheelReversed = newValue } }
    var contextMenus: Bool { get { state.contextMenus } set { state.contextMenus = newValue } }
    var hoverHints: Bool { get { state.hoverHints } set { state.hoverHints = newValue } }
    var alwaysOnTop: Bool { get { state.alwaysOnTop } set { state.alwaysOnTop = newValue } }
    var followDaylight: Bool { get { state.followDaylight } set { state.followDaylight = newValue } }
    var notificationsEnabled: Bool { get { state.notificationsEnabled } set { state.notificationsEnabled = newValue } }
    var reduceMotion: Bool { get { state.reduceMotion } set { state.reduceMotion = newValue } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }
    func binding(for command: MacCommand) -> MacKeyBinding { state.bindings[command.rawValue] ?? command.defaultBinding }
    func rebind(_ command: MacCommand, to binding: MacKeyBinding) -> MacBindingConflict? {
        if let conflict = Self.conflict(for: command, binding: binding, bindings: bindings) { return conflict }
        state.bindings[command.rawValue] = binding
        return nil
    }
    var bindings: [MacCommand: MacKeyBinding] {
        Dictionary(uniqueKeysWithValues: MacCommand.allCases.map { ($0, binding(for: $0)) })
    }
    nonisolated static func conflict(for command: MacCommand, binding: MacKeyBinding,
                         bindings: [MacCommand: MacKeyBinding]) -> MacBindingConflict? {
        guard binding.isValid else { return .unsupported }
        if binding.isReserved && binding != command.defaultBinding { return .reserved }
        if let duplicate = MacCommand.allCases.first(where: {
            $0 != command && $0.scope.overlaps(command.scope) && bindings[$0] == binding
        }) { return .duplicate(duplicate) }
        return nil
    }
    func restoreShortcuts() { state.bindings = [:] }
    func restoreDisplay() {
        state.frameLimit = 60; state.interfaceScale = 1; state.windowMode = .windowed
        state.alwaysOnTop = false; state.followDaylight = true; state.reduceMotion = false
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.storageKey) }
    }
    private struct State: Codable {
        var frameLimit = 60
        var interfaceScale = 1.0
        var windowMode = MacWindowMode.windowed
        var wheelReversed = false
        var contextMenus = true
        var hoverHints = true
        var alwaysOnTop = false
        var followDaylight = true
        var notificationsEnabled = false
        var reduceMotion = false
        var bindings: [String: MacKeyBinding] = [:]
        init() {}
        private enum CodingKeys: String, CodingKey {
            case frameLimit, interfaceScale, windowMode, wheelReversed, contextMenus, hoverHints
            case alwaysOnTop, followDaylight, notificationsEnabled, reduceMotion, bindings
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let limit = (try? values.decode(Int.self, forKey: .frameLimit)) ?? 60
            frameLimit = [30, 60, 120].contains(limit) ? limit : 60
            let scale = (try? values.decode(Double.self, forKey: .interfaceScale)) ?? 1
            interfaceScale = [1, 1.25, 1.5].contains(scale) ? scale : 1
            windowMode = (try? values.decode(MacWindowMode.self, forKey: .windowMode)) ?? .windowed
            wheelReversed = (try? values.decode(Bool.self, forKey: .wheelReversed)) ?? false
            contextMenus = (try? values.decode(Bool.self, forKey: .contextMenus)) ?? true
            hoverHints = (try? values.decode(Bool.self, forKey: .hoverHints)) ?? true
            alwaysOnTop = (try? values.decode(Bool.self, forKey: .alwaysOnTop)) ?? false
            followDaylight = (try? values.decode(Bool.self, forKey: .followDaylight)) ?? true
            notificationsEnabled = (try? values.decode(Bool.self, forKey: .notificationsEnabled)) ?? false
            reduceMotion = (try? values.decode(Bool.self, forKey: .reduceMotion)) ?? false
            let decoded = (try? values.decode([String: MacKeyBinding].self, forKey: .bindings)) ?? [:]
            bindings = decoded.filter { entry in
                guard let command = MacCommand(rawValue: entry.key) else { return false }
                return entry.value.isValid && (!entry.value.isReserved || entry.value == command.defaultBinding)
            }
            // Recheck fallbacks too: discarding one invalid override can expose another collision.
            for _ in MacCommand.allCases {
                let proposed = Dictionary(uniqueKeysWithValues: MacCommand.allCases.map {
                    ($0, bindings[$0.rawValue] ?? $0.defaultBinding)
                })
                let rejected = MacCommand.allCases.filter { command in
                    guard let candidate = bindings[command.rawValue] else { return false }
                    return MacPreferences.conflict(for: command, binding: candidate, bindings: proposed) != nil
                }
                if rejected.isEmpty { break }
                rejected.forEach { bindings.removeValue(forKey: $0.rawValue) }
            }
        }
    }
}
/// Keep a readable desktop canvas; larger scales can scroll instead of hiding controls.
struct MacInterfaceLayout: Equatable {
    let canvasSize: CGSize
    let displayedSize: CGSize
    init(viewport: CGSize, scale: Double) {
        let factor = [1.0, 1.25, 1.5].contains(scale) ? scale : 1
        let width = viewport.width.isFinite ? max(0, viewport.width) : 0
        let height = viewport.height.isFinite ? max(0, viewport.height) : 0
        canvasSize = CGSize(width: max(1280, width / factor), height: max(720, height / factor))
        displayedSize = CGSize(width: canvasSize.width * factor, height: canvasSize.height * factor)
    }
}

struct MacWorkNotificationState: Equatable {
    let generation: UUID
    let activeWorkID: String?
    let completedWorkID: String?
    var isRestoring = false
}

struct MacWorkNotificationTracker {
    private var previous: MacWorkNotificationState?
    mutating func reset(_ state: MacWorkNotificationState) { previous = state }
    mutating func observe(_ state: MacWorkNotificationState) -> String? {
        defer { previous = state }
        guard let previous, !previous.isRestoring, !state.isRestoring,
              previous.generation == state.generation, let completed = state.completedWorkID,
              previous.activeWorkID == completed, previous.completedWorkID != completed else { return nil }
        return completed
    }
}
#endif
