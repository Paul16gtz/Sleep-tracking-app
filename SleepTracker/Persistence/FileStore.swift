import Foundation

/// Owns the on-disk layout below Application Support (clips and the SwiftData store)
/// and applies the file protection class to it.
///
/// Layout: `<base>/Clips/<session uuid>/<yyyyMMdd-HHmmss>-<type>.m4a` and `<base>/Store/SleepTracker.store`.
/// Clip paths are stored relative to `baseDirectory`, so they stay valid when the container path changes.
final class FileStore {
    static let protectionType: FileProtectionType = .completeUntilFirstUserAuthentication

    private static let clipsFolderName = "Clips"
    private static let storeFolderName = "Store"
    private static let storeFileName = "SleepTracker.store"
    private static let clipFileExtension = "m4a"

    /// Clip file names use UTC so they do not depend on the device time zone.
    private static let clipTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    /// `.../Application Support/SleepTracker` for the app; a temporary directory in tests.
    let baseDirectory: URL

    var clipsDirectory: URL {
        baseDirectory.appendingPathComponent(FileStore.clipsFolderName, isDirectory: true)
    }

    var storeDirectory: URL {
        baseDirectory.appendingPathComponent(FileStore.storeFolderName, isDirectory: true)
    }

    var storeURL: URL {
        storeDirectory.appendingPathComponent(FileStore.storeFileName, isDirectory: false)
    }

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    static func makeDefault() throws -> FileStore {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return FileStore(baseDirectory: applicationSupport.appendingPathComponent("SleepTracker", isDirectory: true))
    }

    /// Creates the base, clips and store directories. Failing to create a directory throws;
    /// failing to set the protection attribute does not, because iOS already applies
    /// the same protection class to app files by default.
    func prepareDirectories() throws {
        for directory in [baseDirectory, clipsDirectory, storeDirectory] {
            try createDirectory(at: directory)
            try? applyProtection(to: directory)
        }
    }

    /// Sets `FileStore.protectionType` on an existing file or directory.
    func applyProtection(to url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileStore.protectionType],
            ofItemAtPath: url.path
        )
    }

    /// Returns the clip folder of a session, creating it if needed.
    /// The protection attribute is applied best effort, as in `prepareDirectories()`.
    func clipDirectory(for sessionID: UUID) throws -> URL {
        let directory = sessionClipsDirectory(for: sessionID)
        try createDirectory(at: directory)
        try? applyProtection(to: directory)
        return directory
    }

    /// `Clips/<uuidString>/<yyyyMMdd-HHmmss>-<type.rawValue>.m4a`, time in UTC.
    func makeClipRelativePath(sessionID: UUID, clipStart: Date, type: SoundEventType) -> String {
        let timestamp = FileStore.clipTimestampFormatter.string(from: clipStart)
        let fileName = "\(timestamp)-\(type.rawValue).\(FileStore.clipFileExtension)"
        return "\(FileStore.clipsFolderName)/\(sessionID.uuidString)/\(fileName)"
    }

    func clipURL(relativePath: String) -> URL {
        baseDirectory.appendingPathComponent(relativePath)
    }

    /// Removes the clip folder of a session. A missing folder is not an error.
    func deleteClips(for sessionID: UUID) throws {
        try removeItemIfPresent(at: sessionClipsDirectory(for: sessionID))
    }

    /// Removes a single clip file. A missing file is not an error.
    func deleteClip(relativePath: String) throws {
        try removeItemIfPresent(at: clipURL(relativePath: relativePath))
    }

    /// Removes every clip and leaves an empty, protected clips directory behind.
    func deleteAllClips() throws {
        try removeItemIfPresent(at: clipsDirectory)
        try createDirectory(at: clipsDirectory)
        try? applyProtection(to: clipsDirectory)
    }

    /// Sum of the sizes of all regular files below the clips directory, in bytes.
    func clipsTotalSize() -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: clipsDirectory,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: nil
        ) else {
            return 0
        }
        let keySet = Set(keys)
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keySet),
                  values.isRegularFile == true,
                  let size = values.fileSize else {
                continue
            }
            total += Int64(size)
        }
        return total
    }

    // MARK: - Private

    private func sessionClipsDirectory(for sessionID: UUID) -> URL {
        clipsDirectory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    private func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    private func removeItemIfPresent(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }
}
