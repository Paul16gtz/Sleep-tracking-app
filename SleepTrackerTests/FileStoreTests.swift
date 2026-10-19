import XCTest
@testable import SleepTracker

final class FileStoreTests: XCTestCase {
    /// XCTest creates one instance per test method, so every test gets its own directory.
    private let baseDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    override func tearDown() {
        try? FileManager.default.removeItem(at: baseDirectory)
        super.tearDown()
    }

    private func makeStore() -> FileStore {
        FileStore(baseDirectory: baseDirectory)
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func testClipRelativePathFormat() throws {
        let store = makeStore()
        let sessionID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        // 1_760_917_267 s since 1970 is 2025-10-19 23:41:07 UTC.
        let clipStart = Date(timeIntervalSince1970: 1_760_917_267)

        let path = store.makeClipRelativePath(sessionID: sessionID, clipStart: clipStart, type: .speech)

        XCTAssertEqual(path, "Clips/11111111-2222-3333-4444-555555555555/20251019-234107-speech.m4a")
    }

    func testClipURLAppendsRelativePath() {
        let store = makeStore()

        let url = store.clipURL(relativePath: "Clips/a/b.m4a")

        XCTAssertTrue(url.path.hasSuffix("/Clips/a/b.m4a"), url.path)
    }

    func testPrepareCreatesDirectories() throws {
        let store = makeStore()

        try store.prepareDirectories()

        XCTAssertTrue(directoryExists(store.clipsDirectory))
        XCTAssertTrue(directoryExists(store.storeDirectory))
    }

    func testDeleteClipsForSessionRemovesDirectoryAndToleratesMissing() throws {
        let store = makeStore()
        let sessionID = UUID()
        let directory = try store.clipDirectory(for: sessionID)
        try Data(repeating: 7, count: 4).write(to: directory.appendingPathComponent("clip.m4a"))
        XCTAssertTrue(directoryExists(directory))

        try store.deleteClips(for: sessionID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertNoThrow(try store.deleteClips(for: sessionID))
    }

    func testClipsTotalSizeSumsFiles() throws {
        let store = makeStore()
        let first = try store.clipDirectory(for: UUID())
        let second = try store.clipDirectory(for: UUID())
        try Data(repeating: 1, count: 10).write(to: first.appendingPathComponent("a.m4a"))
        try Data(repeating: 2, count: 20).write(to: second.appendingPathComponent("b.m4a"))

        XCTAssertEqual(store.clipsTotalSize(), 30)
    }

    func testDirectoryLayout() {
        let store = makeStore()

        XCTAssertEqual(store.clipsDirectory.lastPathComponent, "Clips")
        XCTAssertEqual(store.storeDirectory.lastPathComponent, "Store")
        XCTAssertEqual(store.storeURL.lastPathComponent, "SleepTracker.store")
        XCTAssertEqual(store.storeURL.deletingLastPathComponent().lastPathComponent, "Store")
    }

    func testDeleteClipRemovesFileAndToleratesMissing() throws {
        let store = makeStore()
        let sessionID = UUID()
        _ = try store.clipDirectory(for: sessionID)
        let relativePath = store.makeClipRelativePath(sessionID: sessionID, clipStart: Date(), type: .cough)
        let url = store.clipURL(relativePath: relativePath)
        try Data(repeating: 3, count: 8).write(to: url)

        try store.deleteClip(relativePath: relativePath)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNoThrow(try store.deleteClip(relativePath: relativePath))
    }

    func testDeleteAllClipsLeavesEmptyClipsDirectory() throws {
        let store = makeStore()
        let directory = try store.clipDirectory(for: UUID())
        try Data(repeating: 4, count: 12).write(to: directory.appendingPathComponent("c.m4a"))

        try store.deleteAllClips()

        XCTAssertTrue(directoryExists(store.clipsDirectory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertEqual(store.clipsTotalSize(), 0)
    }
}
