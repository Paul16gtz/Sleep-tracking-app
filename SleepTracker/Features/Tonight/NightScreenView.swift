import SwiftUI

/// Dimmed screen shown while a night is recorded: elapsed time, live level, counters
/// for snoring and speech and the stop button. Calm on purpose: no own animations.
struct NightScreenView: View {
    @EnvironmentObject private var controller: SleepSessionController

    /// Text color of everything except the clock, dimmed for the night.
    private static let dimmed = Color.white.opacity(0.6)
    /// The clock is a little brighter than the rest.
    private static let clockColor = Color.white.opacity(0.8)

    var body: some View {
        ZStack {
            Theme.nightDim
                .ignoresSafeArea()
            VStack(spacing: 40) {
                Spacer()
                clock
                levelView
                countersRow
                Spacer()
                stopButton
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    /// Live level mapped from -80...0 dBFS to 0...1 for the bar.
    private var normalizedLevel: Double {
        max(0, min(1, (controller.liveLevel + 80) / 80))
    }

    private var clock: some View {
        VStack(spacing: 8) {
            Text(Formatters.clock(controller.elapsed))
                .font(.system(size: 56, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NightScreenView.clockColor)
            if controller.isInFallAsleepDelay {
                Text("Einschlafverzögerung läuft")
                    .font(.footnote)
                    .foregroundStyle(NightScreenView.dimmed)
            }
        }
    }

    private var levelView: some View {
        VStack(spacing: 8) {
            ProgressView(value: normalizedLevel)
                .tint(Theme.accent)
            Text(Formatters.decibels(controller.liveLevel))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(NightScreenView.dimmed)
        }
    }

    private var countersRow: some View {
        HStack(spacing: 32) {
            EventCounter(type: .snoring, count: controller.eventCounts[.snoring] ?? 0, textColor: NightScreenView.dimmed)
            EventCounter(type: .speech, count: controller.eventCounts[.speech] ?? 0, textColor: NightScreenView.dimmed)
        }
    }

    private var stopButton: some View {
        Button {
            controller.stop()
        } label: {
            Text("Aufwachen / Beenden")
                .font(.title3.weight(.semibold))
                .foregroundStyle(NightScreenView.clockColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Theme.card)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Count of one event type with its icon and German name.
private struct EventCounter: View {
    let type: SoundEventType
    let count: Int
    let textColor: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: type.symbolName)
                .font(.title2)
                .foregroundStyle(Theme.color(for: type))
            Text(String(count))
                .font(.title2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(textColor)
            Text(type.germanName)
                .font(.caption)
                .foregroundStyle(textColor)
        }
        .frame(minWidth: 96)
        .accessibilityElement(children: .combine)
    }
}
