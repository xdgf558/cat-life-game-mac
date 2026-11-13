#if os(macOS)
import AppKit
import SwiftUI

struct MacKeyModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int
    static let command = Self(rawValue: 1)
    static let shift = Self(rawValue: 2)
    static let option = Self(rawValue: 4)
    static let control = Self(rawValue: 8)
    static let allowed: Self = [.command, .shift, .option, .control]
}

struct MacKeyBinding: Codable, Hashable, Sendable {
    let key: String
    var modifiers: MacKeyModifiers = []
    var isValid: Bool {
        modifiers.subtracting(.allowed).isEmpty && !key.isEmpty
            && (key.count == 1 || ["left", "right", "up", "down", "return", "escape", "delete", "tab", "space"].contains(key))
    }
    var isReserved: Bool {
        ((modifiers.isEmpty || modifiers == .shift) && ["tab", "space", "return"].contains(key))
            || modifiers.contains(.command) && ["q", "w", "h", "m", ","].contains(key)
            || modifiers == [.command, .control] && key == "f"
    }
    var label: String {
        let keyName = ["left": "←", "right": "→", "up": "↑", "down": "↓", "return": "↩",
                       "escape": "Esc", "delete": "⌫", "tab": "Tab", "space": "Space"][key] ?? key.uppercased()
        return (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.option) ? "⌥" : "")
            + (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "") + keyName
    }
    init(key: String, modifiers: MacKeyModifiers = []) { self.key = key; self.modifiers = modifiers }
    init?(event: NSEvent) {
        var flags: MacKeyModifiers = []
        if event.modifierFlags.contains(.command) { flags.insert(.command) }
        if event.modifierFlags.contains(.shift) { flags.insert(.shift) }
        if event.modifierFlags.contains(.option) { flags.insert(.option) }
        if event.modifierFlags.contains(.control) { flags.insert(.control) }
        let names: [UInt16: String] = [123: "left", 124: "right", 125: "down", 126: "up", 36: "return", 76: "return",
                                      53: "escape", 51: "delete", 117: "delete", 48: "tab", 49: "space"]
        guard var key = names[event.keyCode] ?? event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return nil }
        if key == "?" { key = "/"; flags.insert(.shift) }
        self.init(key: key, modifiers: flags)
        if !isValid { return nil }
    }
}

enum MacBindingConflict: Equatable { case reserved, unsupported, duplicate(MacCommand) }

struct MacShortcutScope: OptionSet, Sendable {
    let rawValue: Int
    static let home = Self(rawValue: 1)
    static let arrangement = Self(rawValue: 2)
    static let list = Self(rawValue: 4)
    static let shop = Self(rawValue: 8)
    static let town = Self(rawValue: 16)
    static let global = Self(rawValue: 31)
    func overlaps(_ other: Self) -> Bool { !intersection(other).isEmpty }
}

enum MacCommand: String, CaseIterable, Codable, Sendable {
    case home, work, shop, town, cats, settings, help, escape, fullscreen
    case feed, clean, play, nextCat, viewLeft, viewRight, focusCat, catProfile, decorate
    case rotateLeft, rotateRight, nudgeLeft, nudgeRight, nudgeUp, nudgeDown, grid, putAway, confirm, undo, redo, save
    case listUp, listDown, previousPage, nextPage, search, returnHome
    var titleKey: String { "mac.command." + rawValue }
    var scope: MacShortcutScope {
        switch self {
        case .home, .work, .shop, .town, .cats, .settings, .help, .escape, .fullscreen: .global
        case .feed, .clean, .play, .nextCat, .catProfile: .home
        case .viewLeft, .viewRight, .focusCat, .decorate: [.home, .arrangement]
        case .rotateLeft, .rotateRight, .nudgeLeft, .nudgeRight, .nudgeUp, .nudgeDown, .grid, .putAway, .undo, .redo, .save: .arrangement
        case .previousPage, .nextPage: .shop
        case .search: [.shop, .arrangement]
        case .listUp, .listDown: [.list, .shop]
        case .confirm: [.list, .shop, .arrangement, .town]
        case .returnHome: .town
        }
    }
    var acceptsKeyRepeat: Bool {
        switch self {
        case .nudgeLeft, .nudgeRight, .nudgeUp, .nudgeDown, .listUp, .listDown: true
        default: false
        }
    }
    var defaultBinding: MacKeyBinding {
        switch self {
        case .home: .init(key: "1")
        case .work: .init(key: "2")
        case .shop: .init(key: "3")
        case .town: .init(key: "4")
        case .cats: .init(key: "5")
        case .settings: .init(key: ",", modifiers: .command)
        case .help: .init(key: "/", modifiers: .shift)
        case .escape: .init(key: "escape")
        case .fullscreen: .init(key: "f", modifiers: [.command, .control])
        case .feed: .init(key: "f")
        case .clean: .init(key: "c")
        case .play: .init(key: "p")
        case .nextCat: .init(key: "tab", modifiers: .option)
        case .viewLeft: .init(key: "q")
        case .viewRight: .init(key: "e")
        case .focusCat: .init(key: "space", modifiers: .option)
        case .catProfile: .init(key: "i")
        case .decorate: .init(key: "b")
        case .rotateLeft: .init(key: "r", modifiers: .shift)
        case .rotateRight: .init(key: "r")
        case .nudgeLeft: .init(key: "left")
        case .nudgeRight: .init(key: "right")
        case .nudgeUp: .init(key: "up")
        case .nudgeDown: .init(key: "down")
        case .grid: .init(key: "g")
        case .putAway: .init(key: "delete")
        case .confirm: .init(key: "return", modifiers: .command)
        case .undo: .init(key: "z", modifiers: .command)
        case .redo: .init(key: "z", modifiers: [.command, .shift])
        case .save: .init(key: "s", modifiers: .command)
        case .listUp: .init(key: "up", modifiers: .option)
        case .listDown: .init(key: "down", modifiers: .option)
        case .previousPage: .init(key: "[")
        case .nextPage: .init(key: "]")
        case .search: .init(key: "f", modifiers: .command)
        case .returnHome: .init(key: "h")
        }
    }
}

@MainActor
final class MacKeyboardRouter {
    private let preferences: MacPreferences
    private var monitor: Any?
    var handler: (MacCommand) -> Bool
    init(preferences: MacPreferences, handler: @escaping (MacCommand) -> Bool) {
        self.preferences = preferences; self.handler = handler
    }
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated { self.route(event) == nil }
            return consumed ? nil : event
        }
    }
    func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    private func route(_ event: NSEvent) -> NSEvent? {
        guard let window = event.window, window.isKeyWindow, window.attachedSheet == nil, window.sheetParent == nil else { return event }
        if let capture = window.firstResponder as? MacShortcutCaptureButton, capture.recording {
            capture.keyDown(with: event)
            return nil
        }
        guard !(window.firstResponder is NSTextView), !(window.firstResponder is NSTextField),
              let pressed = MacKeyBinding(event: event) else { return event }
        let nativeNavigation = Self.yieldsToNativeNavigation(pressed, canvasFocused: window.firstResponder is MacRoomSKView,
                                                              controlFocused: window.firstResponder is NSControl)
        return dispatch(pressed, isRepeat: event.isARepeat, nativeNavigation: nativeNavigation) ? nil : event
    }
    static func yieldsToNativeNavigation(_ binding: MacKeyBinding, canvasFocused: Bool, controlFocused: Bool) -> Bool {
        if (binding.modifiers.isEmpty || binding.modifiers == .shift), binding.key == "tab" { return true }
        guard binding.modifiers.isEmpty else { return false }
        if ["space", "left", "right", "up", "down"].contains(binding.key) { return !canvasFocused }
        return binding.key == "return" && controlFocused
    }
    @discardableResult
    func dispatch(_ pressed: MacKeyBinding, isRepeat: Bool, nativeNavigation: Bool = false) -> Bool {
        let matches = MacCommand.allCases.filter { preferences.binding(for: $0) == pressed }
        // Repeats must not fall through and repeatedly activate a focused native button.
        if isRepeat, ["return", "space"].contains(pressed.key) { return true }
        if isRepeat, !matches.isEmpty, matches.allSatisfy({ !$0.acceptsKeyRepeat }) { return true }
        guard !nativeNavigation else { return false }
        for command in matches where !isRepeat || command.acceptsKeyRepeat {
            if handler(command) { return true }
        }
        return isRepeat && !matches.isEmpty
    }
}

/// The key editor owns focus, so the app router cannot execute a key being recorded.
struct MacShortcutRecorder: NSViewRepresentable {
    var label: String
    var onRecord: (MacKeyBinding) -> Void
    func makeNSView(context: Context) -> MacShortcutCaptureButton {
        let button = MacShortcutCaptureButton()
        button.bezelStyle = .rounded
        button.title = label
        button.defaultTitle = label
        button.onRecord = onRecord
        button.target = button; button.action = #selector(MacShortcutCaptureButton.beginRecording)
        return button
    }
    func updateNSView(_ button: MacShortcutCaptureButton, context: Context) {
        button.defaultTitle = label
        if !button.recording { button.title = label }
        button.onRecord = onRecord
    }
}

final class MacShortcutCaptureButton: NSButton {
    var onRecord: ((MacKeyBinding) -> Void)?
    var recording = false
    var defaultTitle = ""
    override var acceptsFirstResponder: Bool { true }
    @objc func beginRecording() { recording = true; title = "…"; window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        guard let binding = MacKeyBinding(event: event) else { NSSound.beep(); return }
        recording = false
        title = defaultTitle
        if binding.key != "escape" { onRecord?(binding) }
        window?.makeFirstResponder(nil)
    }
}
#endif

#if os(macOS)
struct MacShortcutsHelpView: View {
    let preferences: MacPreferences
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(GameStrings.text("mac.shortcuts.title")).font(.system(size: 25, weight: .heavy, design: .rounded))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 30, height: 30) }
                    .accessibilityLabel(GameStrings.text("mac.shortcuts.close"))
            }
            ScrollView {
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], alignment: .leading, spacing: 10) {
                    ForEach(MacCommand.allCases, id: \.self) { command in
                        HStack(spacing: 12) {
                            Text(GameStrings.text(command.titleKey)).frame(maxWidth: .infinity, alignment: .leading)
                            Text(preferences.binding(for: command).label)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(10).background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(24).frame(width: 760, height: 600).background(RoomTheme.paper)
        .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(RoomTheme.ink)
        .accessibilityIdentifier("macShortcutsHelp")
    }
}
#endif
