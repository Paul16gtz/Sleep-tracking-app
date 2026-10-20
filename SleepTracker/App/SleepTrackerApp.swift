import SwiftData
import SwiftUI

@main
struct SleepTrackerApp: App {
    @State private var dependencies: AppDependencies?
    @State private var startupError: String?

    init() {
        do {
            let created = try AppDependencies()
            _dependencies = State(initialValue: created)
            _startupError = State(initialValue: nil)
        } catch {
            _dependencies = State(initialValue: nil)
            _startupError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let deps = dependencies {
                RootTabView()
                    .environmentObject(deps)
                    .environmentObject(deps.sessionController)
                    .environmentObject(deps.settingsStore)
                    .environmentObject(deps.clipPlayer)
                    .modelContainer(deps.modelContainer)
                    .preferredColorScheme(.dark)
            } else {
                Text(startupErrorText)
                    .multilineTextAlignment(.center)
                    .padding()
                    .preferredColorScheme(.dark)
            }
        }
    }

    /// Shown instead of the app when the store could not be opened.
    private var startupErrorText: String {
        "Die App konnte den Speicher nicht öffnen: \(startupError ?? "Unbekannter Fehler.")"
    }
}
