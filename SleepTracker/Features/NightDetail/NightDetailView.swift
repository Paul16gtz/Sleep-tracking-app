import SwiftData
import SwiftUI

/// Detail of one night: the summary, the timeline chart and the chronological event
/// list with clip playback and single-event delete. All sections are rows of a `List`,
/// so the event rows can offer swipe actions. The toolbar shares the night as a CSV file.
struct NightDetailView: View {
    let session: SleepSession

    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var clipPlayer: ClipPlayer

    /// Message for a failed event delete (German); nil means no error.
    @State private var deleteErrorMessage: String? = nil
    /// Temporary CSV file of this night for the `ShareLink`; nil until it is written or when writing failed.
    @State private var exportURL: URL? = nil

    var body: some View {
        // Checked before any other property of the session is read: "Alle Daten löschen" in
        // the settings tab can delete the night while this view is still pushed in the
        // "Nächte" tab, and reading a deleted model may trap.
        if NightDetailView.isDeleted(session) {
            deletedPlaceholder
        } else {
            nightContent
        }
    }

    @ViewBuilder
    private var nightContent: some View {
        let stats = session.statistics()
        let events = NightDetailView.chronological(session.events)
        let hasMotionData = session.hasMotionData
        List {
            summarySection(stats, hasMotionData: hasMotionData)
            timelineSection(events, showsMotion: hasMotionData)
            eventsSection(events)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(Formatters.nightDate(session.startDate))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let url = exportURL {
                    ShareLink(item: url) {
                        Label("Exportieren", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.secondary)
                }
            }
        }
        // `MainActor.run` keeps the SwiftData reads on the main actor whichever isolation
        // the `task` closure gets.
        .task {
            await MainActor.run { refreshExport() }
        }
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

    private var deletedPlaceholder: some View {
        ContentUnavailableView(
            "Nacht gelöscht",
            systemImage: "trash",
            description: Text("Diese Nacht wurde gelöscht.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    private func summarySection(_ stats: NightStatistics, hasMotionData: Bool) -> some View {
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
                LabeledContent(
                    "Unruhe-Index",
                    value: NightDetailView.restlessnessText(stats, hasMotionData: hasMotionData)
                )
                LabeledContent("Unterbrechungen", value: String(stats.interruptionCount))
            }
            .listRowBackground(Theme.card)
        }
    }

    private func timelineSection(_ events: [SoundEvent], showsMotion: Bool) -> some View {
        Section("Zeitachse") {
            NightTimelineChart(
                points: NightDetailView.timelinePoints(session.epochs),
                events: NightDetailView.timelineEvents(events),
                range: NightDetailView.timelineRange(of: session),
                showsMotion: showsMotion
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
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
            refreshExport()
        } catch {
            deleteErrorMessage = "Das Ereignis konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }

    /// Writes the CSV of the night to a temporary file and publishes its URL for the share
    /// button. A failure leaves no URL (the toolbar keeps its inactive icon), so a stale
    /// file is never offered.
    private func refreshExport() {
        guard !NightDetailView.isDeleted(session) else {
            exportURL = nil
            return
        }
        let csv = CSVExporter.makeCSV(
            events: NightDetailView.exportEvents(session.events),
            epochs: NightDetailView.exportEpochs(session.epochs)
        )
        exportURL = try? CSVExporter.writeTemporaryFile(
            csv: csv,
            fileName: CSVExporter.fileName(for: session.startDate)
        )
    }

    /// `session.events` is unordered. Events that start together (two types detected in
    /// the same window) are ordered by type, so rows keep their order between updates.
    /// Deleted events are skipped before any of their other properties is read, so no
    /// row, bar or export line is built from one.
    private static func chronological(_ events: [SoundEvent]) -> [SoundEvent] {
        events
            .filter { !isDeleted($0) }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate {
                    return lhs.startDate < rhs.startDate
                }
                return lhs.typeRaw < rhs.typeRaw
            }
    }

    /// A model deleted elsewhere: its context is gone after the save, and before the save
    /// it is marked as deleted. None of its stored properties may be read any more.
    private static func isDeleted(_ model: some PersistentModel) -> Bool {
        model.modelContext == nil || model.isDeleted
    }

    /// Export rows in chronological order (the exporter sorts again).
    private static func exportEvents(_ events: [SoundEvent]) -> [EventExportRow] {
        chronological(events).map { event in
            EventExportRow(
                type: event.type,
                start: event.startDate,
                end: event.endDate,
                maxConfidence: event.maxConfidence,
                averageConfidence: event.averageConfidence,
                clipRelativePath: event.clipRelativePath
            )
        }
    }

    /// `session.epochs` is unordered; the rows are sorted by timestamp (the exporter sorts again).
    private static func exportEpochs(_ epochs: [EpochSample]) -> [EpochExportRow] {
        epochs
            .sorted { $0.timestamp < $1.timestamp }
            .map { epoch in
                EpochExportRow(
                    timestamp: epoch.timestamp,
                    motionIntensity: epoch.motionIntensity,
                    isRestless: epoch.isRestless,
                    averageDecibels: epoch.averageDecibels,
                    peakDecibels: epoch.peakDecibels
                )
            }
    }

    /// `session.epochs` is unordered. Levels below the chart floor are drawn on it, so a
    /// silent epoch (`LevelMeter.silenceFloor`) does not squash the rest of the line.
    /// Motion intensity and the restless flag are taken over unchanged.
    private static func timelinePoints(_ epochs: [EpochSample]) -> [TimelinePoint] {
        epochs
            .sorted { $0.timestamp < $1.timestamp }
            .enumerated()
            .map { index, epoch in
                TimelinePoint(
                    id: index,
                    time: epoch.timestamp,
                    decibels: max(NightTimelineChart.decibelFloor, epoch.averageDecibels),
                    motion: epoch.motionIntensity,
                    isRestless: epoch.isRestless
                )
            }
    }

    /// Expects `events` in chronological order. A bar ends at max(end, start + 20 s)
    /// (`TimelineEvent.minimumVisibleDuration`), so a short event stays visible on a long axis.
    private static func timelineEvents(_ events: [SoundEvent]) -> [TimelineEvent] {
        events.map { event in
            TimelineEvent(
                id: event.id,
                type: event.type,
                start: event.startDate,
                end: max(event.endDate, event.startDate + TimelineEvent.minimumVisibleDuration)
            )
        }
    }

    /// A running night extends to now; a night under a minute still gets a 60 s axis, so
    /// the range is never empty.
    private static func timelineRange(of session: SleepSession) -> ClosedRange<Date> {
        let end = max(session.endDate ?? Date(), session.startDate + 60)
        return session.startDate ... end
    }

    /// A night without motion data (no sensor) shows "–", because all its epochs are calm
    /// and "0 % unruhig" would claim a measured calm night; otherwise "12 % unruhig, 4 Phasen".
    private static func restlessnessText(_ stats: NightStatistics, hasMotionData: Bool) -> String {
        guard hasMotionData else {
            return "–"
        }
        let phases = stats.restlessPhaseCount == 1 ? "1 Phase" : "\(stats.restlessPhaseCount) Phasen"
        return "\(Formatters.percent(stats.restlessPercentage)) unruhig, \(phases)"
    }
}
