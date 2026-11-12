#if os(macOS)
import AppKit
import SwiftUI

@main
struct CatLifeMacApp: App {
    @NSApplicationDelegateAdaptor(MacApplicationDelegate.self) private var delegate
    var body: some Scene {
        Window("打工养猫日记", id: "main") {
            MacDesktopRoot(delegate: delegate).frame(minWidth: 1280, minHeight: 720)
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button(GameStrings.text("mac.page.settings")) { NotificationCenter.default.post(name: .macOpenSettings69, object: nil) }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
extension Notification.Name { static let macOpenSettings69 = Notification.Name("CatLifeMac.openSettings") }
@MainActor
final class MacApplicationDelegate: NSObject, NSApplicationDelegate {
    var requestQuit: (() -> NSApplication.TerminateReply)?
    private var saveDirectoryLock: MacSaveDirectoryLock?
    private var rejectedSaveAccess = false

    /// Root calls this before reading or resetting any repository files.
    func prepareSaveAccess(directory: URL?) -> Bool {
        guard !NativeSaveLocation.isAppUnitTesting else { return false }
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: {
               $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
           }) {
            // Older released copies do not take the directory lock yet.
            rejectSaveAccess(alreadyInUse: true)
            return false
        }
        if let saveDirectoryLock {
            if directory?.standardizedFileURL.resolvingSymlinksInPath() == saveDirectoryLock.directory { return true }
            rejectSaveAccess(alreadyInUse: false)
            return false
        }
        guard let directory else { rejectSaveAccess(alreadyInUse: false); return false }
        do {
            saveDirectoryLock = try MacSaveDirectoryLock(directory: directory)
            return true
        } catch MacSaveDirectoryLock.Failure.alreadyInUse {
            rejectSaveAccess(alreadyInUse: true)
        } catch {
            rejectSaveAccess(alreadyInUse: false)
        }
        return false
    }

    private func rejectSaveAccess(alreadyInUse: Bool) {
        rejectedSaveAccess = true
        let alert = NSAlert()
        alert.messageText = GameStrings.text(alreadyInUse ? "mac.save.lockedTitle" : "mac.save.accessTitle")
        alert.informativeText = GameStrings.text(alreadyInUse ? "mac.save.lockedDetail" : "mac.save.accessDetail")
        alert.addButton(withTitle: GameStrings.text("common.done"))
        alert.runModal()
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A rejected copy must never enter the normal quit/save workflow.
        rejectedSaveAccess ? .terminateNow : requestQuit?() ?? .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif
