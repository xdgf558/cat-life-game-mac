#if os(macOS)
import Foundation
import Darwin

/// Keep this object alive until process exit. Never unlink the lock file: other copies
/// must keep locking the same inode, including after a crash or a UI-fixture reset.
final class MacSaveDirectoryLock {
    enum Failure: Error, Equatable {
        case alreadyInUse
        case unavailable(Int32)
    }
    static let fileName = ".cat-life-directory.lock"
    let directory: URL
    private let descriptor: Int32

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let file = self.directory.appendingPathComponent(Self.fileName)
        let descriptor = Darwin.open(file.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw Failure.unavailable(errno) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            _ = Darwin.close(descriptor)
            throw code == EWOULDBLOCK || code == EAGAIN ? Failure.alreadyInUse : Failure.unavailable(code)
        }
        self.descriptor = descriptor
    }

    #if DEBUG
    /// Only called once by a reset-enabled UI-test store, after this directory is locked.
    static func clearUITestFiles(in directory: URL) throws {
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where file.lastPathComponent != fileName {
            try FileManager.default.removeItem(at: file)
        }
    }
    #endif

    deinit {
        _ = flock(descriptor, LOCK_UN)
        _ = Darwin.close(descriptor)
    }
}
#endif
