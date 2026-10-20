import SwiftData
import SwiftUI

/// Tab "Nächte": every recorded night, newest first. Tapping a night opens its detail;
/// swiping deletes it together with its clips. The running night cannot be deleted.
struct NightsListView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Query(sort: \SleepSession.startDate, order: .reverse) private var sessions: [SleepSession]

    /// Message for the delete error alert (German); nil means no error.
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Nächte",
                        systemImage: "moon.zzz",
                        description: Text("Starte heute Nacht die erste Aufnahme.")
                    )
                } else {
                    sessionList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle("Nächte")
            .alert("Fehler", isPresented: errorBinding) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var sessionList: some View {
        List {
            ForEach(sessions) { session in
                NavigationLink {
                    NightDetailView(session: session)
                } label: {
                    NightRowView(session: session)
                }
                .listRowBackground(Theme.card)
                // The controller still records into the running session.
                .deleteDisabled(session.status == .running)
            }
            .onDelete(perform: delete)
        }
        .scrollContentBackground(.hidden)
    }

    /// Presents the alert while there is a message; dismissing clears it.
    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    /// Deletes the swiped nights through the repository, which removes their clips too.
    /// The sessions are looked up before the first delete changes the query result.
    private func delete(at offsets: IndexSet) {
        let targets = offsets.map { sessions[$0] }
        for session in targets where session.status != .running {
            do {
                try dependencies.repository.deleteSession(session)
            } catch {
                errorMessage = "Die Nacht konnte nicht gelöscht werden: \(error.localizedDescription)"
                return
            }
        }
    }
}
