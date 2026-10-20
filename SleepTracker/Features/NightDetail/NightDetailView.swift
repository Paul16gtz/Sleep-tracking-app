import SwiftData
import SwiftUI

/// Detail of one night (phase 1): the summary and the chronological event list with
/// clip playback and single-event delete. Both sections are rows of a `List`, so the
/// event rows can offer swipe actions.
struct NightDetailView: View {
    let session: SleepSession

    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var clipPlayer: ClipPlayer

    /// Message for a failed event delete (German); nil means no error.
    @State private var deleteErrorMessage: String? = nil

    var body: some View {
        let stats = session.statistics()
        let events = NightDetailView.chronological(session.events)
        List {
            summarySection(stats)
            eventsSection(events)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(Formatters.nightDate(session.startDate))
        .navigationBarTitleDisplayMode(.inline)
        // Leaving the night (back or another tab) ends playback, so a clip never keeps
        // playing into a night started meanwhile (spec B1).
        .onDisappear {
            clipPlayer.stop()
        }
        .alert("Fehler", isPresented: alertBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func summarySection(_ stats: NightStatistics) -> some View {
        Section("Zusammenfassung") {
            Group {
                LabeledContent("Gesamtdauer", value: Formatters.duration(stats.duration))
                LabeledContent(
                    "Schnarchzeit",
                    value: "\(Formatters.minutes(stats.snoringDuration)) (\(Formatters.percent(stats.snoringPercentage)))"
                )
                LabeledContent("Sprech-Ereignisse", value: String(stats.speechCount))
                if stats.coughCount > 0 {
                    LabeledContent("Husten", value: String(stats.coughCount))
                }
                LabeledContent("Unruhe-Index", value: NightDetailView.restlessnessText(stats))
                LabeledContent("Unterbrechungen", value: String(stats.interruptionCount))
            }
            .listRowBackground(Theme.card)
        }
    }

    private func eventsSection(_ events: [SoundEvent]) -> some View {
        Section("Ereignisse") {
            if events.isEmpty {
                Text("Keine Ereignisse")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Theme.card)
            } else {
                ForEach(events) { event in
                    EventRowView(event: event, onDelete: { delete(event) })
                        .listRowBackground(Theme.card)
                }
            }
        }
    }

    /// A delete error first, then a playback error of the shared clip player.
    private var alertMessage: String? {
        deleteErrorMessage ?? clipPlayer.errorMessage
    }

    /// Presents the alert while there is a message; dismissing clears the shown one.
    private var alertBinding: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { isPresented in
                guard !isPresented else {
                    return
                }
                if deleteErrorMessage != nil {
                    deleteErrorMessage = nil
                } else {
                    clipPlayer.errorMessage = nil
                }
            }
        )
    }

    /// Deletes the event through the repository, which removes its clip file too. A
    /// loaded clip of the event (playing or paused) is stopped first.
    private func delete(_ event: SoundEvent) {
        if let path = event.clipRelativePath, clipPlayer.playingPath == path {
            clipPlayer.stop()
        }
        do {
            try dependencies.repository.deleteEvent(event)
        } catch {
            deleteErrorMessage = "Das Ereignis konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }

    /// `session.events` is unordered. Events that start together (two types detected in
    /// the same window) are ordered by type, so rows keep their order between updates.
    private static func chronological(_ events: [SoundEvent]) -> [SoundEvent] {
        events.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate {
                return lhs.startDate < rhs.startDate
            }
            return lhs.typeRaw < rhs.typeRaw
        }
    }

    /// Phase 1 records no motion, so no epoch is marked restless and the index shows "–";
    /// otherwise "12 % unruhig, 4 Phasen".
    private static func restlessnessText(_ stats: NightStatistics) -> String {
        guard stats.restlessEpochCount > 0 else {
            return "–"
        }
        let phases = stats.restlessPhaseCount == 1 ? "1 Phase" : "\(stats.restlessPhaseCount) Phasen"
        return "\(Formatters.percent(stats.restlessPercentage)) unruhig, \(phases)"
    }
}
