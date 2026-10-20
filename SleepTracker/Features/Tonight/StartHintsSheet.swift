import SwiftUI

/// Hints shown before a night starts: power (only when not charging), placement of the
/// iPhone, the fall-asleep delay and other apps' audio. Starting is always possible.
struct StartHintsSheet: View {
    /// Called once when the user taps "Jetzt starten"; the sheet dismisses itself.
    let onStart: () -> Void

    @EnvironmentObject private var controller: SleepSessionController
    @Environment(\.dismiss) private var dismiss

    /// Prevents a second start while the sheet is being dismissed.
    @State private var hasStarted = false

    var body: some View {
        NavigationStack {
            List {
                if !controller.isCharging {
                    HintRow(
                        symbolName: "battery.25",
                        text: "Das iPhone lädt nicht. Schließe es ans Ladekabel an, damit die Aufnahme die ganze Nacht läuft.",
                        tint: .yellow
                    )
                    .listRowBackground(Color.yellow.opacity(0.15))
                }
                HintRow(
                    symbolName: "iphone.gen3.radiowaves.left.and.right",
                    text: "Lege das iPhone mit dem Display nach unten auf die Matratze, in Kopfnähe.",
                    tint: Theme.accent
                )
                .listRowBackground(Theme.card)
                HintRow(
                    symbolName: "hourglass",
                    text: "Während der Einschlafverzögerung werden noch keine Ereignisse gezählt.",
                    tint: Theme.accent
                )
                .listRowBackground(Theme.card)
                // The recording session cannot mix with other apps' playback (spec B1).
                HintRow(
                    symbolName: "speaker.slash",
                    text: "Keine Musik oder Einschlafgeräusche aus anderen Apps abspielen – sie unterbrechen die Aufnahme.",
                    tint: Theme.accent
                )
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Hinweise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                startButton
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var startButton: some View {
        Button {
            hasStarted = true
            onStart()
            dismiss()
        } label: {
            Text("Jetzt starten")
                .font(.headline)
                .foregroundStyle(Theme.background)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Theme.accent)
        .disabled(hasStarted)
        .padding()
        .background(Theme.background)
    }
}

/// One hint: a tinted SF Symbol and its text.
private struct HintRow: View {
    let symbolName: String
    let text: String
    let tint: Color

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbolName)
                .foregroundStyle(tint)
        }
        .padding(.vertical, 4)
    }
}
