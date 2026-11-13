#if os(macOS)
import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class MacWindowController: NSObject, NSWindowDelegate {
    let preferences: MacPreferences
    private(set) weak var window: NSWindow?
    var shouldClose: (() -> Bool)?
    private var frameAutosaveName: NSWindow.FrameAutosaveName {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return "CatLifeMacMainWindow-UITests" }
        #endif
        return "CatLifeMacMainWindow"
    }
    private var windowedFrame: NSRect?
    private var attached = false
    private var fullscreenTransition = false
    init(preferences: MacPreferences) { self.preferences = preferences; super.init() }
    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window; window.delegate = self
        window.contentMinSize = NSSize(width: 1280, height: 720)
        window.title = GameStrings.text("home.name")
        window.titlebarAppearsTransparent = true
        if !attached {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--reset-ui-test-save") { NSWindow.removeFrame(usingName: frameAutosaveName) }
            #endif
            if !window.setFrameUsingName(frameAutosaveName) {
                window.setContentSize(NSSize(width: 1440, height: 900)); window.center()
            }
            window.setFrameAutosaveName(frameAutosaveName)
            attached = true
        }
        apply()
    }
    func apply() {
        guard let window else { return }
        window.level = preferences.alwaysOnTop ? .floating : .normal
        guard !fullscreenTransition else { return }
        switch preferences.windowMode {
        case .fullscreen:
            guard !window.styleMask.contains(.fullScreen) else { return }
            restoreWindowStyle()
            window.toggleFullScreen(nil)
        case .windowed:
            if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil); return }
            restoreWindowStyle()
        case .borderless:
            if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil); return }
            if window.styleMask.contains(.titled) {
                windowedFrame = window.frame
                window.saveFrame(usingName: frameAutosaveName)
                window.setFrameAutosaveName("")
            }
            window.styleMask = [.borderless, .resizable]
            if let screen = window.screen ?? NSScreen.main { window.setFrame(screen.frame, display: true) }
            NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
        }
    }
    func setMode(_ mode: MacWindowMode) { preferences.windowMode = mode; apply() }
    func toggleFullscreen() { setMode(preferences.windowMode == .fullscreen ? .windowed : .fullscreen) }
    func setContentSize(_ size: NSSize) {
        guard let window, preferences.windowMode == .windowed else { return }
        window.setContentSize(NSSize(width: max(1280, size.width), height: max(720, size.height)))
        window.saveFrame(usingName: frameAutosaveName)
    }
    private func restoreWindowStyle() {
        guard let window else { return }
        let wasBorderless = !window.styleMask.contains(.titled)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = true
        NSApp.presentationOptions = []
        if wasBorderless {
            if let windowedFrame { window.setFrame(windowedFrame, display: true) }
            else { _ = window.setFrameUsingName(frameAutosaveName) }
            window.setFrameAutosaveName(frameAutosaveName)
        }
    }
    func windowWillClose(_ notification: Notification) { NSApp.presentationOptions = [] }
    func windowShouldClose(_ sender: NSWindow) -> Bool { shouldClose?() ?? true }
    func windowWillEnterFullScreen(_ notification: Notification) { fullscreenTransition = true }
    func windowWillExitFullScreen(_ notification: Notification) { fullscreenTransition = true }
    func windowDidExitFullScreen(_ notification: Notification) {
        fullscreenTransition = false
        if preferences.windowMode == .fullscreen { preferences.windowMode = .windowed }
        apply()
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        fullscreenTransition = false
        preferences.windowMode = .fullscreen
    }
}

struct MacWindowAttachment: NSViewRepresentable {
    let controller: MacWindowController
    func makeNSView(context: Context) -> MacWindowAttachmentView { MacWindowAttachmentView(controller: controller) }
    func updateNSView(_ view: MacWindowAttachmentView, context: Context) {
        if let window = view.window { controller.attach(window) }
    }
}
final class MacWindowAttachmentView: NSView {
    let controller: MacWindowController
    init(controller: MacWindowController) { self.controller = controller; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let window { controller.attach(window) } }
}

@MainActor
enum MacNotifications {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
    static func post(title: String, body: String, id: String, preferences: MacPreferences, isCurrent: () -> Bool = { true }) async {
        guard preferences.notificationsEnabled, !NSApp.isActive else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        guard preferences.notificationsEnabled, !NSApp.isActive, isCurrent() else { return }
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
#endif
