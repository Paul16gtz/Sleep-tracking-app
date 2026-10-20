import SwiftUI

/// Tab "Einstellungen": the recording, detection, clip and motion parameters, the storage
/// used by clips with the delete actions, the reset to the defaults and the entry to the
/// debug area. Every control writes through `settingsStore.settings`, whose `didSet` saves
/// the change. A running night keeps the settings snapshot it started with, so changes
/// apply from the next recording.
struct SettingsView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var sessionController: SleepSessionController
    @EnvironmentObject private var clipPlayer: ClipPlayer

    /// Total size of all clip files in bytes; nil until it is read when the view appears.
    @State private var clipsSize: Int64? = nil
    /// `true` while a delete action runs: shows the progress row and disables both delete buttons.
    @State private var isDeleting = false
    @State private var isConfirmingClipDeletion = false
    @State private var isConfirmingDataDeletion = false
    /// Message for the delete error alert (German); nil means no error.
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                recordingSection
                detectionSection
                clipsSection
                motionSection
                storageSection
                moreSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Einstellungen")
            .onAppear {
                refreshClipsSize()
            }
            .alert("Fehler", isPresented: errorBinding) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var recordingSection: some View {
        Section("Aufnahme") {
            Stepper(
                "Einschlafverzögerung: \(Formatters.minutes(settings.fallAsleepDelay))",
                value: minutesBinding(\.fallAsleepDelay),
                in: 0...60,
                step: 5
            )
            .listRowBackground(Theme.card)
        }
    }

    private var detectionSection: some View {
        Section {
            Group {
                ForEach(SoundEventType.allCases) { type in
                    thresholdRow(for: type)
                }
                Stepper(
                    "Mindestfenster: \(settings.minConsecutiveWindows)",
                    value: binding(\.minConsecutiveWindows),
                    in: 1...5
                )
                Stepper(
                    "Ende-Lücke: \(SettingsView.wholeNumberText(settings.eventEndGap)) s",
                    value: binding(\.eventEndGap),
                    in: 2...15,
                    step: 1
                )
                Stepper(
                    "Zusammenführen bis: \(SettingsView.wholeNumberText(settings.mergeGap)) s",
                    value: binding(\.mergeGap),
                    in: 0...60,
                    step: 1
                )
                Stepper(
                    "Max. Ereignisdauer: \(Formatters.minutes(settings.maxEventDuration))",
                    value: minutesBinding(\.maxEventDuration),
                    in: 1...30,
                    step: 1
                )
            }
            .listRowBackground(Theme.card)
        } header: {
            Text("Erkennung")
        } footer: {
            Text("Änderungen gelten ab der nächsten Aufnahme.")
        }
    }

    private var clipsSection: some View {
        Section("Clips") {
            Group {
                Stepper(
                    "Sprech-Clips pro Nacht: \(settings.speechClipLimitPerNight)",
                    value: binding(\.speechClipLimitPerNight),
                    in: 0...200,
                    step: 10
                )
                Stepper(
                    "Schnarch-Clips: Abstand \(Formatters.minutes(settings.snoringClipMinInterval))",
                    value: minutesBinding(\.snoringClipMinInterval),
                    in: 1...60,
                    step: 1
                )
                Stepper(
                    "Schnarch-Clips pro Nacht: \(settings.snoringClipLimitPerNight)",
                    value: binding(\.snoringClipLimitPerNight),
                    in: 0...100,
                    step: 5
                )
            }
            .listRowBackground(Theme.card)
        }
    }

    private var motionSection: some View {
        Section {
            Stepper(
                "Unruhe-Faktor: \(restlessFactorText)",
                value: binding(\.restlessFactor),
                in: 1.5...10,
                step: 0.5
            )
            .listRowBackground(Theme.card)
        } header: {
            Text("Bewegung")
        } footer: {
            Text("Eine Epoche gilt als unruhig, wenn ihre Bewegung über der Ruhebasislinie × Faktor liegt.")
        }
    }

    private var storageSection: some View {
        Section {
            Group {
                Text("Clips belegen \(clipsSizeText)")
                if isDeleting {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Lösche …")
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Clips aller Nächte löschen", role: .destructive) {
                    isConfirmingClipDeletion = true
                }
                .disabled(isDeleteDisabled)
                .confirmationDialog(
                    "Clips aller Nächte löschen?",
                    isPresented: $isConfirmingClipDeletion,
                    titleVisibility: .visible
                ) {
                    Button("Clips löschen", role: .destructive) {
                        startDeletion(.clips)
                    }
                    Button("Abbrechen", role: .cancel) { }
                } message: {
                    Text("Die Ereignisse bleiben erhalten, ihre Clips lassen sich danach nicht mehr abspielen.")
                }
                Button("Alle Daten löschen", role: .destructive) {
                    isConfirmingDataDeletion = true
                }
                .disabled(isDeleteDisabled)
                .confirmationDialog(
                    "Wirklich alle Nächte, Ereignisse und Clips löschen?",
                    isPresented: $isConfirmingDataDeletion,
                    titleVisibility: .visible
                ) {
                    Button("Alle Daten löschen", role: .destructive) {
                        startDeletion(.allData)
                    }
                    Button("Abbrechen", role: .cancel) { }
                } message: {
                    Text("Das lässt sich nicht rückgängig machen.")
                }
            }
            .listRowBackground(Theme.card)
        } header: {
            Text("Speicher")
        } footer: {
            if sessionController.isRunning {
                Text("Während einer Aufnahme lässt sich nichts löschen.")
            }
        }
    }

    private var moreSection: some View {
        Section("Weitere") {
            Group {
                Button("Auf Standardwerte zurücksetzen") {
                    settingsStore.resetToDefaults()
                }
                NavigationLink("Debug") {
                    DebugView()
                }
            }
            .listRowBackground(Theme.card)
        }
    }

    /// Name and threshold of one category above its slider. The slider carries the name and
    /// the percent value for VoiceOver, so the text line above it is hidden from it.
    private func thresholdRow(for type: SoundEventType) -> some View {
        let percentText = Formatters.percent(settings.threshold(for: type) * 100)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(type.germanName)
                Spacer()
                Text(percentText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityHidden(true)
            Slider(value: thresholdBinding(for: type), in: 0.3...0.95, step: 0.05)
                .accessibilityLabel(type.germanName)
                .accessibilityValue(percentText)
        }
    }

    // MARK: - Values

    private var settings: AppSettings {
        settingsStore.settings
    }

    /// "3.0"; one decimal, as the factor moves in steps of 0.5.
    private var restlessFactorText: String {
        String(format: "%.1f", settings.restlessFactor)
    }

    /// "12,3 MB"; "…" until the size has been read.
    private var clipsSizeText: String {
        guard let size = clipsSize else {
            return "…"
        }
        return SettingsView.byteCountFormatter.string(fromByteCount: size)
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        // A number also for an empty clips folder, not the word "Zero".
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    /// Whole number as text ("4"); unlike `Int(_:)`, `String(format:)` cannot trap on a non-finite value.
    private static func wholeNumberText(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    // MARK: - Bindings

    /// Each binding assigns through `settingsStore.settings`, so the store saves every change.
    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        let store = settingsStore
        return Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { store.settings[keyPath: keyPath] = $0 }
        )
    }

    /// A setting stored in seconds, edited in minutes.
    private func minutesBinding(_ keyPath: WritableKeyPath<AppSettings, TimeInterval>) -> Binding<Double> {
        let store = settingsStore
        return Binding(
            get: { store.settings[keyPath: keyPath] / 60 },
            set: { store.settings[keyPath: keyPath] = $0 * 60 }
        )
    }

    private func thresholdBinding(for type: SoundEventType) -> Binding<Double> {
        let store = settingsStore
        return Binding(
            get: { store.settings.threshold(for: type) },
            set: { store.settings.setThreshold($0, for: type) }
        )
    }

    /// Presents the alert while there is a message; dismissing clears it.
    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    // MARK: - Storage

    private enum Deletion {
        /// Every clip file; the nights and their events stay.
        case clips
        /// Every night with its events, epochs and clips.
        case allData

        /// Start of the German error message.
        var failureText: String {
            switch self {
            case .clips: return "Die Clips konnten nicht gelöscht werden"
            case .allData: return "Die Daten konnten nicht gelöscht werden"
            }
        }
    }

    /// Nothing is deleted while a night records into the store and the clips folder.
    private var isDeleteDisabled: Bool {
        sessionController.isRunning || isDeleting
    }

    private func refreshClipsSize() {
        clipsSize = dependencies.fileStore.clipsTotalSize()
    }

    /// Runs a confirmed delete action. Playback stops first, so no clip is open while its file
    /// goes. The work blocks the main actor, so the task yields once before it: the run loop
    /// then draws the progress row first. Afterwards the clip size is read again.
    private func startDeletion(_ deletion: Deletion) {
        guard !isDeleteDisabled else {
            return
        }
        isDeleting = true
        clipPlayer.stop()
        Task { @MainActor in
            await Task.yield()
            // A night started in the meantime keeps its data.
            if !sessionController.isRunning {
                perform(deletion)
            }
            isDeleting = false
            refreshClipsSize()
        }
    }

    private func perform(_ deletion: Deletion) {
        do {
            switch deletion {
            case .clips:
                try deleteClipsOfAllNights()
            case .allData:
                try dependencies.repository.deleteAllData()
            }
        } catch {
            errorMessage = "\(deletion.failureText): \(error.localizedDescription)"
        }
    }

    /// Clears the clip reference of every event and saves, then removes all clip files, so no
    /// event offers a clip whose file is gone. If removing the files fails after the save, only
    /// unreferenced files are left, and the next attempt removes them.
    private func deleteClipsOfAllNights() throws {
        let repository = dependencies.repository
        for session in try repository.fetchSessions() {
            for event in session.events where event.clipRelativePath != nil {
                event.clipRelativePath = nil
            }
        }
        try repository.save()
        try dependencies.fileStore.deleteAllClips()
    }
}
