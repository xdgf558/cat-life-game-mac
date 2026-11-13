#if os(macOS)
import Foundation
import XCTest
import CatGameCore
@testable import CatLifeMac

@MainActor
final class MacSaveIsolationTests: XCTestCase {
    func testBuildModesChooseSeparateFoldersWithoutAccessingApplicationSupport() {
        let base = URL(fileURLWithPath: "/uncreated-save-location-test-root", isDirectory: true)
        XCTAssertEqual(NativeSaveLocation.directory(in: base, isMac: true, isDebug: true, isUITesting: false).lastPathComponent, "CatLifeMac-Development")
        XCTAssertEqual(NativeSaveLocation.directory(in: base, isMac: true, isDebug: true, isUITesting: true).lastPathComponent, "CatLifeMac-UITests")
        XCTAssertEqual(NativeSaveLocation.directory(in: base, isMac: true, isDebug: false, isUITesting: false).lastPathComponent, "CatLifeMac")
        XCTAssertEqual(NativeSaveLocation.directory(in: base, isMac: true, isDebug: false, isUITesting: true).lastPathComponent, "CatLifeMac")
        let unit = NativeSaveLocation.directory(in: base, isMac: true, isDebug: true, isUITesting: false, isAppUnitTesting: true)
        XCTAssertTrue(unit.lastPathComponent.hasPrefix("CatLifeMac-UnitTests-"))
        XCTAssertEqual(unit.deletingLastPathComponent(), base)
        let releaseUnit = NativeSaveLocation.directory(in: base, isMac: true, isDebug: false, isUITesting: false, isAppUnitTesting: true)
        XCTAssertTrue(releaseUnit.lastPathComponent.hasPrefix("CatLifeMac-UnitTests-"))
        XCTAssertEqual(NativeSaveLocation.directory(in: base, isMac: false, isDebug: true, isUITesting: false).lastPathComponent, "CatLife")
        XCTAssertEqual(NativeSaveLocation.directory(in: base, isMac: false, isDebug: true, isUITesting: true).lastPathComponent, "CatLife-UITests")
    }

    func testStoreSummaryAndStudyLogUseTheInjectedRepositoryDirectory() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GameStore(directory: directory)
        XCTAssertEqual(store.saveDirectory, directory)
        XCTAssertFalse(store.hasSavedProgress)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path), "Creating a store must not touch files before the process lock is acquired.")
        try await store.habitStudyLog.append(.init(event: "test", catID: "cat_001", sessionID: nil, detail: nil, control: nil, duration: nil))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("HabitStudy/observations.json").path))
        XCTAssertFalse(store.hasSavedProgress, "A diagnostic log is not a game save.")
        let repository = FileSaveRepository(directory: directory)
        try await repository.save(.fresh(now: Date()))
        XCTAssertTrue(store.hasSavedProgress)
        try FileManager.default.moveItem(at: repository.saveURL, to: repository.backupURL)
        XCTAssertTrue(store.hasSavedProgress, "A recoverable backup must also enable the title's existing-progress summary.")
    }

    func testAnotherOpenDescriptorCannotLockOrChangeTheSameSave() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var owner: MacSaveDirectoryLock? = try MacSaveDirectoryLock(directory: directory)
        XCTAssertNotNil(owner)
        let save = directory.appendingPathComponent("cat-life-native-v1.json")
        let original = Data("saved-progress-sentinel".utf8)
        try original.write(to: save)
        XCTAssertThrowsError(try MacSaveDirectoryLock(directory: directory)) { error in
            XCTAssertEqual(error as? MacSaveDirectoryLock.Failure, .alreadyInUse)
        }
        XCTAssertEqual(try Data(contentsOf: save), original)
        owner = nil
        let reopened = try MacSaveDirectoryLock(directory: directory)
        withExtendedLifetime(reopened) { XCTAssertEqual(reopened.directory, directory.standardizedFileURL.resolvingSymlinksInPath()) }
    }

    #if DEBUG
    func testUITestResetPreservesTheHeldLockInode() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = try MacSaveDirectoryLock(directory: directory)
        let lock = directory.appendingPathComponent(MacSaveDirectoryLock.fileName)
        let before = try FileManager.default.attributesOfItem(atPath: lock.path)[.systemFileNumber] as? NSNumber
        let save = directory.appendingPathComponent("cat-life-native-v1.json")
        try Data("fixture".utf8).write(to: save)
        try MacSaveDirectoryLock.clearUITestFiles(in: directory)
        let after = try FileManager.default.attributesOfItem(atPath: lock.path)[.systemFileNumber] as? NSNumber
        XCTAssertNotNil(before)
        XCTAssertEqual(after, before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: save.path))
        XCTAssertThrowsError(try MacSaveDirectoryLock(directory: directory)) { error in
            XCTAssertEqual(error as? MacSaveDirectoryLock.Failure, .alreadyInUse)
        }
        withExtendedLifetime(owner) {}
    }

    #endif

    func testASymlinkAtTheLockPathCannotBeOpenedAsAnotherFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sentinel = directory.appendingPathComponent("sentinel.json")
        let original = Data("must-stay-unchanged".utf8)
        try original.write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent(MacSaveDirectoryLock.fileName), withDestinationURL: sentinel)
        XCTAssertThrowsError(try MacSaveDirectoryLock(directory: directory))
        XCTAssertEqual(try Data(contentsOf: sentinel), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("cat-life-native-v1.json").path))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MacSaveIsolationTests-" + UUID().uuidString, isDirectory: true)
    }
}
#endif
