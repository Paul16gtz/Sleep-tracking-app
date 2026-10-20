import SwiftUI
import UniformTypeIdentifiers

/// Test mode (spec B8): runs an audio file from "Dateien" through the same pipeline as a
/// night and stores the result as a test session. The chosen file is copied into the
/// temporary directory first, so the analysis does not depend on the security-scoped
/// access to the original; the copy is removed when the run ends.
struct TestModeView: View {
    /// Prefix of the temporary copies, so leftovers of earlier runs can be found.
    private static let copyPrefix = "testmode-"

    @EnvironmentObject private var sessionController: SleepSessionController
    @EnvironmentObject private var clipPlayer: ClipPlayer

    @State private var isImporterPresented = false
    /// `true` once a test run started from this screen; shows the saved hint after it.
    @State private var didRun = false
    /// The temporary copy the current run reads; nil when there is none.
    @State private var copiedFileURL: URL? = nil
    /// Message for the error alert (German); nil means no error.
    @State private var errorMessage: String? = nil

    var body: some View {
        Form {
            explanationSection
            chooseSection
            if isTestRunning {
                progressSection
            } else if didRun {
                resultSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Testmodus")
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        // A finished or cancelled run no longer reads its copy.
        .onChange(of: sessionController.isRunning) { _, isRunning in
            if !isRunning {
                removeCopiedFile()
            }
        }
        .alert("Fehler", isPresented: errorBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var explanationSection: some View {
        Section {
            Group {
                Text("Der Testmodus schickt eine Audiodatei durch dieselbe Erkennung wie eine Nacht: Geräuschklassifikation, Ereignisse, Clips und Lautstärke. Die Datei wird schneller als in Echtzeit analysiert, ohne Einschlafverzögerung und ohne Bewegungserfassung. Das Mikrofon wird nicht verwendet.")
                Text("Das Ergebnis wird als Test-Session gespeichert und erscheint unter „Nächte“ mit dem Hinweis „Test“.")
            }
            .listRowBackground(Theme.card)
        }
    }

    private var chooseSection: some View {
        Section {
            Button("Audiodatei wählen") {
                isImporterPresented = true
            }
            .disabled(sessionController.isRunning)
            .listRowBackground(Theme.card)
        } footer: {
            if sessionController.isRunning && !sessionController.isTestRun {
                Text("Während einer Aufnahme ist der Testmodus nicht verfügbar.")
            }
        }
    }

    private var progressSection: some View {
        Section("Analyse") {
            Group {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Analyse läuft …")
                }
                ForEach(SoundEventType.allCases) { type in
                    LabeledContent {
                        Text("\(sessionController.eventCounts[type] ?? 0)")
                            .monospacedDigit()
                    } label: {
                        Label {
                            Text(type.germanName)
                        } icon: {
                            Image(systemName: type.symbolName)
                                .foregroundStyle(Theme.color(for: type))
                        }
                    }
                }
                controllerMessageRow
                Button("Abbrechen") {
                    sessionController.stop()
                }
            }
            .listRowBackground(Theme.card)
        }
    }

    private var resultSection: some View {
        Section {
            Group {
                Text("Test-Session gespeichert. Sie erscheint unter Nächte mit dem Hinweis Test.")
                controllerMessageRow
            }
            .listRowBackground(Theme.card)
        }
    }

    /// A message of the running or the last session (for example a read error of the
    /// file), which the alert of the tab "Heute Nacht" also shows.
    @ViewBuilder
    private var controllerMessageRow: some View {
        if let message = sessionController.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Values

    private var isTestRunning: Bool {
        sessionController.isRunning && sessionController.isTestRun
    }

    /// Presents the alert while there is a message; dismissing clears it.
    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    // MARK: - Import and start

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                return
            }
            let copy: URL
            do {
                copy = try TestModeView.makeWorkingCopy(of: url)
            } catch {
                errorMessage = "Die Datei konnte nicht übernommen werden: \(error.localizedDescription)"
                return
            }
            startTest(reading: copy)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    /// Starts the run on the copy; a failed start removes it again. A loaded clip is
    /// stopped first, as before a night.
    private func startTest(reading copy: URL) {
        copiedFileURL = copy
        didRun = false
        let controller = sessionController
        let player = clipPlayer
        Task { @MainActor in
            player.stop()
            do {
                try await controller.start(mode: .test(fileURL: copy))
                didRun = true
            } catch {
                errorMessage = error.localizedDescription
                removeCopiedFile()
            }
        }
    }

    private func removeCopiedFile() {
        guard let url = copiedFileURL else {
            return
        }
        copiedFileURL = nil
        try? FileManager.default.removeItem(at: url)
    }

    /// Copies the file chosen in "Dateien" to `tmp/testmode-<uuid>.<ext>`. The
    /// security-scoped access is held only while copying. Copies left by earlier runs
    /// (for example when this screen was closed during a run) are removed first: no test
    /// runs while a file is chosen, because the button is disabled during a recording.
    private static func makeWorkingCopy(of url: URL) throws -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        removeLeftoverCopies()
        let fileExtension = url.pathExtension
        let name = TestModeView.copyPrefix + UUID().uuidString + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }

    private static func removeLeftoverCopies() {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return
        }
        for name in names where name.hasPrefix(copyPrefix) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
