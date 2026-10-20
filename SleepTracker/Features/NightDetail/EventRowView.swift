import SwiftData
import SwiftUI

/// One event in the night detail: icon, type, time span, length and confidence and,
/// when a clip exists, a play/pause button. Swiping the row offers "Löschen".
struct EventRowView: View {
    let event: SoundEvent
    /// Deletes the event; run by the swipe action.
    let onDelete: () -> Void

    @EnvironmentObject private var clipPlayer: ClipPlayer
    @EnvironmentObject private var sessionController: SleepSessionController

    var body: some View {
        // The row observes the controller and the clip player on its own, so one of their
        // updates can rebuild it after its event was deleted; then it reads nothing of it.
        if event.isDeletedFromContext {
            EmptyView()
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            Image(systemName: event.type.symbolName)
                .font(.title3)
                .foregroundStyle(Theme.color(for: event.type))
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.type.germanName)
                    .font(.headline)
                Text(timeSpanText)
                    .font(.subheadline)
                    .monospacedDigit()
                Text(detailText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let path = event.clipRelativePath {
                playButton(path: path)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Löschen", role: .destructive, action: onDelete)
        }
    }

    /// "23:41 – 23:42".
    private var timeSpanText: String {
        "\(Formatters.time(event.startDate)) – \(Formatters.time(event.endDate))"
    }

    /// "45 s · Konfidenz 87 %".
    private var detailText: String {
        "\(durationText) · Konfidenz \(Formatters.percent(event.maxConfidence * 100))"
    }

    /// Most events are shorter than a minute; those show whole seconds ("45 s").
    private var durationText: String {
        let seconds = event.duration
        guard seconds.isFinite, seconds < 60 else {
            return Formatters.duration(seconds)
        }
        return "\(Int(max(0, seconds))) s"
    }

    /// Play/pause for the event's clip, disabled while a night runs (spec B1). The
    /// borderless style keeps a tap on the rest of the row from triggering it.
    private func playButton(path: String) -> some View {
        let isPlayingThis = clipPlayer.playingPath == path && clipPlayer.isPlaying
        let accessibilityText = isPlayingThis ? "Pause" : "Abspielen"
        return Button {
            clipPlayer.toggle(relativePath: path)
        } label: {
            Image(systemName: isPlayingThis ? "pause.circle.fill" : "play.circle.fill")
                .font(.title)
        }
        .buttonStyle(.borderless)
        .tint(Theme.accent)
        .disabled(sessionController.isRunning)
        .accessibilityLabel(Text(accessibilityText))
    }
}
