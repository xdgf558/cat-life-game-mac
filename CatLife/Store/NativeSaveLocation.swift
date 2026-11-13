import Foundation

/// One location policy is shared by the repository, local diagnostics, and the title screen.
enum NativeSaveLocation {
    #if DEBUG
    private static let unitTestFolder = "CatLifeMac-UnitTests-" + UUID().uuidString
    #endif
    static var isAppUnitTesting: Bool {
        #if DEBUG
        let process = ProcessInfo.processInfo
        let hasTestEnvironment = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"].contains { process.environment[$0] != nil }
        let hasTestRuntime = NSClassFromString("XCTestCase") != nil || NSClassFromString("XCTest.XCTestCase") != nil
        return !process.arguments.contains("--ui-testing") && (hasTestEnvironment || hasTestRuntime)
        #else
        return false
        #endif
    }

    static var currentDirectory: URL {
        #if os(macOS)
        let mac = true
        #else
        let mac = false
        #endif
        #if DEBUG
        let debug = true
        let uiTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        let debug = false
        let uiTesting = false
        #endif
        let unitTesting = mac && isAppUnitTesting
        let base = unitTesting ? FileManager.default.temporaryDirectory
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory(in: base, isMac: mac, isDebug: debug,
                         isUITesting: uiTesting,
                         isAppUnitTesting: unitTesting)
    }

    /// An injected base keeps location-policy tests away from any player's Application Support.
    static func directory(in base: URL, isMac: Bool, isDebug: Bool,
                          isUITesting: Bool, isAppUnitTesting: Bool = false) -> URL {
        #if DEBUG
        // isAppUnitTesting is always false in Release, so the build mode does not need to gate it here.
        if isMac && isAppUnitTesting {
            return base.appendingPathComponent(unitTestFolder, isDirectory: true)
        }
        #endif
        let folder: String
        if isMac {
            if isDebug && isUITesting { folder = "CatLifeMac-UITests" }
            else { folder = isDebug ? "CatLifeMac-Development" : "CatLifeMac" }
        } else {
            folder = isDebug && isUITesting ? "CatLife-UITests" : "CatLife"
        }
        return base.appendingPathComponent(folder, isDirectory: true)
    }
}
