import Combine
import Foundation
import SwiftData

/// Builds the app's long-lived objects once at launch and owns them. Views reach
/// them as environment objects.
@MainActor
final class AppDependencies: ObservableObject {
    /// Files SQLite keeps next to the store file, as suffixes of its name.
    private static let storeSidecarSuffixes = ["-wal", "-shm"]

    let fileStore: FileStore
    let modelContainer: ModelContainer
    let repository: SessionRepository
    let settingsStore: SettingsStore
    let sessionController: SleepSessionController
    let clipPlayer: ClipPlayer

    /// Throws when the directories cannot be created or the store cannot be opened.
    init() throws {
        let fileStore = try FileStore.makeDefault()
        try fileStore.prepareDirectories()

        let configuration = ModelConfiguration(
            "SleepTracker",
            schema: SessionRepository.schema,
            url: fileStore.storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let modelContainer = try ModelContainer(for: SessionRepository.schema, configurations: [configuration])
        AppDependencies.protectStoreFiles(of: fileStore)

        let repository = SessionRepository(context: modelContainer.mainContext, fileStore: fileStore)
        // Spec B12: no recorder exists yet, so every session still marked running was cut off.
        _ = try? repository.markStaleRunningSessions()

        let settingsStore = SettingsStore()
        let sessionController = SleepSessionController(
            repository: repository,
            fileStore: fileStore,
            settingsStore: settingsStore,
            sourceFactory: { MicrophoneAudioSource(callbackQueue: $0) },
            fileSourceFactory: { FileAudioSource(fileURL: $0, callbackQueue: $1) },
            classifierFactoryProvider: { SoundClassifierService.makeFactory(mapping: $0) },
            knownLabelsProvider: { try SoundClassifierService.knownLabels() },
            motionSourceFactory: { CoreMotionSource() }
        )
        let clipPlayer = ClipPlayer(fileStore: fileStore)

        self.fileStore = fileStore
        self.modelContainer = modelContainer
        self.repository = repository
        self.settingsStore = settingsStore
        self.sessionController = sessionController
        self.clipPlayer = clipPlayer
    }

    /// Applies the protection class to the store file and to its sidecar files that
    /// exist (spec B10). Best effort, as in `FileStore.prepareDirectories()`.
    private static func protectStoreFiles(of fileStore: FileStore) {
        let storeURL = fileStore.storeURL
        try? fileStore.applyProtection(to: storeURL)
        for suffix in storeSidecarSuffixes {
            let sidecarURL = fileStore.storeDirectory.appendingPathComponent(
                storeURL.lastPathComponent + suffix,
                isDirectory: false
            )
            if FileManager.default.fileExists(atPath: sidecarURL.path) {
                try? fileStore.applyProtection(to: sidecarURL)
            }
        }
    }
}
