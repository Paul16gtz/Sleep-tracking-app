import SwiftUI

/// Debug area (spec A9), reached from the settings: the live top 5 of the classifier, the
/// live motion values, the entry to the test mode and the classifier's label set with the
/// labels the app maps to its categories. The long label list comes last, so the live
/// values are visible without scrolling.
struct DebugView: View {
    @EnvironmentObject private var sessionController: SleepSessionController

    /// The classifier's label set, loaded when the view appears.
    private enum LabelsState {
        case loading
        case loaded([String], LabelMapping)
        /// Carries the error message.
        case failed(String)
    }

    @State private var labelsState: LabelsState = .loading

    var body: some View {
        Form {
            liveClassificationSection
            motionSection
            testModeSection
            labelsSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Debug")
        // The labels are read wherever the task runs; `MainActor.run` sets the state on
        // the main actor whichever isolation the `task` closure gets.
        .task {
            let result = Result { try SoundClassifierService.knownLabels() }
            await MainActor.run { applyLabels(result) }
        }
    }

    // MARK: - Sections

    private var liveClassificationSection: some View {
        Section {
            Group {
                if !sessionController.isRunning {
                    notRunningRow
                } else if sessionController.topLabels.isEmpty {
                    Text("Noch kein Ergebnis")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(sessionController.topLabels.prefix(5)), id: \.label) { ranked in
                        HStack {
                            labelText(ranked.label)
                            Spacer()
                            Text(Formatters.percent(ranked.confidence * 100))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .listRowBackground(Theme.card)
        } header: {
            Text("Live-Klassifikation")
        } footer: {
            if sessionController.isRunning {
                Text("Die fünf wahrscheinlichsten Labels des letzten Analysefensters, höchstens zweimal pro Sekunde aktualisiert.")
            }
        }
    }

    private var motionSection: some View {
        Section("Bewegung") {
            Group {
                if !sessionController.isRunning {
                    notRunningRow
                } else {
                    LabeledContent("Erfassung", value: sessionController.isMotionActive ? "aktiv" : "nicht aktiv")
                    LabeledContent("Beschleunigung", value: DebugView.decimalText(sessionController.liveMotionMagnitude) + " g")
                    LabeledContent("Ruhewert", value: baselineText)
                }
            }
            .listRowBackground(Theme.card)
        }
    }

    private var testModeSection: some View {
        Section("Testmodus") {
            NavigationLink("Testmodus") {
                TestModeView()
            }
            .listRowBackground(Theme.card)
        }
    }

    private var labelsSection: some View {
        Section {
            Group {
                switch labelsState {
                case .loading:
                    ProgressView()
                case .loaded(let labels, let mapping):
                    ForEach(labels, id: \.self) { label in
                        labelRow(label, mapping: mapping)
                    }
                case .failed(let message):
                    Text("Klassifikator nicht verfügbar: \(message)")
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Theme.card)
        } header: {
            Text(labelsHeader)
        } footer: {
            if case .loaded = labelsState {
                Text("Markierte Labels zählen für die Kategorie daneben.")
            }
        }
    }

    // MARK: - Rows

    private var notRunningRow: some View {
        Text("Nur während einer laufenden Aufnahme")
            .foregroundStyle(.secondary)
    }

    /// The label, followed by the category it counts for, if any.
    private func labelRow(_ label: String, mapping: LabelMapping) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let type = mapping.type(for: label) {
                categoryLabel(type)
            }
        }
    }

    /// A live label with the icon of its category when the app maps it.
    private func labelText(_ label: String) -> some View {
        HStack(spacing: 6) {
            if let type = mappedType(for: label) {
                Image(systemName: type.symbolName)
                    .foregroundStyle(Theme.color(for: type))
                    .accessibilityLabel(type.germanName)
            }
            Text(label)
        }
    }

    private func categoryLabel(_ type: SoundEventType) -> some View {
        Label {
            Text(type.germanName)
        } icon: {
            Image(systemName: type.symbolName)
        }
        .font(.subheadline)
        .foregroundStyle(Theme.color(for: type))
    }

    // MARK: - Values

    /// "Verfügbare Labels (303)" once loaded.
    private var labelsHeader: String {
        if case .loaded(let labels, _) = labelsState {
            return "Verfügbare Labels (\(labels.count))"
        }
        return "Verfügbare Labels"
    }

    /// The resting level once calibrated; while calibrating "Kalibrierung läuft", without motion "–".
    private var baselineText: String {
        if let baseline = sessionController.motionBaseline {
            return DebugView.decimalText(baseline)
        }
        return sessionController.isMotionActive ? "Kalibrierung läuft" : "–"
    }

    /// The category of a classifier label, once the label set is loaded.
    private func mappedType(for label: String) -> SoundEventType? {
        guard case .loaded(_, let mapping) = labelsState else {
            return nil
        }
        return mapping.type(for: label)
    }

    /// Three decimals ("1.002"); `String(format:)` cannot trap on a non-finite value.
    private static func decimalText(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func applyLabels(_ result: Result<[String], Error>) {
        switch result {
        case .success(let labels):
            labelsState = .loaded(labels.sorted(), LabelMapping(knownLabels: labels))
        case .failure(let error):
            labelsState = .failed(error.localizedDescription)
        }
    }
}
