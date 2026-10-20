import SwiftUI

/// Tab "Heute Nacht": the start view while idle, the dimmed night screen while a
/// session runs. Errors of the controller are shown in one alert for both states.
struct TonightView: View {
    @EnvironmentObject private var controller: SleepSessionController
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var showHints = false

    var body: some View {
        Group {
            if controller.isRunning {
                NightScreenView()
            } else {
                startView
            }
        }
        .sheet(isPresented: $showHints) {
            StartHintsSheet(onStart: { startNight() })
                .environmentObject(controller)
        }
        .alert("Fehler", isPresented: errorBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(controller.errorMessage ?? "")
        }
    }

    private var startView: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()
            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    Text("Schlafprotokoll")
                        .font(.largeTitle.bold())
                    Text("Bereit für die Nacht")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                startButton
                Text("Einschlafverzögerung: \(Formatters.minutes(settingsStore.settings.fallAsleepDelay))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private var startButton: some View {
        Button {
            showHints = true
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 64))
                    .accessibilityHidden(true)
                Text("Schlaf starten")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Theme.background)
            .frame(width: 200, height: 200)
            .background(Circle().fill(Theme.accent))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    /// Presents the alert while the controller has a message; dismissing clears it.
    private var errorBinding: Binding<Bool> {
        Binding(
            get: { controller.errorMessage != nil },
            set: { if !$0 { controller.errorMessage = nil } }
        )
    }

    /// Starts a night; a failure is shown in the error alert.
    private func startNight() {
        let sessionController = controller
        Task { @MainActor in
            do {
                try await sessionController.start(mode: .night)
            } catch {
                sessionController.errorMessage = error.localizedDescription
            }
        }
    }
}
