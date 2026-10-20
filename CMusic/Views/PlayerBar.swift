//
//  PlayerBar.swift
//  CMusic
//

import MusicKit
import SwiftUI

/// The bar along the bottom of the window: now playing, and transport controls over a scrubber.
/// Volume follows the system output, since `ApplicationMusicPlayer` exposes no volume control.
struct PlayerBar: View {
    var player: PlayerModel
    /// Called when the artist name is clicked.
    var openArtist: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            NowPlaying(player: player, openArtist: openArtist)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                TransportControls(player: player)
                if player.hasCurrentEntry, player.duration > 0 {
                    ScrubberRow(player: player)
                }
            }
            .frame(minWidth: 360, idealWidth: 520, maxWidth: 600)

            // Mirrors the now-playing column's width so the transport controls stay centered.
            Button("Autoplay", systemImage: "infinity") { player.autoplay.toggle() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.title3)
                .foregroundStyle(player.autoplay ? Color.accentColor : Color.secondary)
                .help(player.autoplay ? "Autoplay On: a similar station plays when the queue ends" : "Autoplay Off")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 72)
        .background(.bar)
    }
}

private struct NowPlaying: View {
    var player: PlayerModel
    var openArtist: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(artwork: player.artwork, cornerRadius: 4, side: 48)

            if let title = player.title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.medium)
                    if let subtitle = player.subtitle {
                        if player.currentSong != nil {
                            LinkText(subtitle, action: openArtist)
                                .help("Go to Artist")
                        } else {
                            Text(subtitle).foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.callout)
                .lineLimit(1)
            }
        }
    }
}

/// Secondary text that underlines on hover and acts as a button, for the artist name.
private struct LinkText: View {
    var text: String
    var action: () -> Void
    @State private var isHovering = false

    init(_ text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(text)
                .foregroundStyle(isHovering ? .primary : .secondary)
                .underline(isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct TransportControls: View {
    var player: PlayerModel

    var body: some View {
        HStack(spacing: 22) {
            Button("Shuffle", systemImage: "shuffle", action: player.toggleShuffle)
                .foregroundStyle(player.isShuffled ? Color.accentColor : Color.secondary)
                .help("Shuffle")

            Button("Previous", systemImage: "backward.fill", action: player.previous)
                .help("Previous")

            Button(
                player.isPlaying ? "Pause" : "Play",
                systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                action: player.togglePlayPause
            )
            .font(.title)
            .contentTransition(.symbolEffect(.replace))
            .help(player.isPlaying ? "Pause" : "Play")

            Button("Next", systemImage: "forward.fill", action: player.next)
                .help("Next")

            Button("Repeat", systemImage: player.repeatMode == .one ? "repeat.1" : "repeat", action: player.cycleRepeat)
                .foregroundStyle(player.repeatMode == .none ? Color.secondary : Color.accentColor)
                .help("Repeat")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.title3)
    }
}

/// Split out so the twice-a-second `elapsed` updates only re-render this row, not the whole bar.
private struct ScrubberRow: View {
    var player: PlayerModel

    var body: some View {
        HStack(spacing: 8) {
            Text(player.elapsed.formattedDuration)
                .frame(width: 40, alignment: .trailing)
            ProgressScrubber(elapsed: player.elapsed, duration: player.duration, seek: player.seek)
            Text((player.duration - player.elapsed).formattedDuration)
                .frame(width: 40, alignment: .leading)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

/// A thin track with a tall invisible hit area. Dragging previews the position and seeks on release.
private struct ProgressScrubber: View {
    var elapsed: TimeInterval
    var duration: TimeInterval
    var seek: (TimeInterval) -> Void

    @State private var dragFraction: Double?
    @State private var isHovering = false

    var body: some View {
        GeometryReader { proxy in
            let fraction = dragFraction ?? min(elapsed / duration, 1)
            let isActive = isHovering || dragFraction != nil
            let trackHeight: CGFloat = isActive ? 7 : 5

            ZStack(alignment: .leading) {
                Capsule().fill(.tertiary)
                Capsule().fill(isActive ? Color.accentColor : Color.secondary)
                    .frame(width: proxy.size.width * fraction)
            }
            .frame(height: trackHeight)
            .overlay(alignment: .leading) {
                if isActive {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1.5)
                        .frame(width: 13, height: 13)
                        .offset(x: proxy.size.width * fraction - 6.5)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragFraction = min(max(value.location.x / proxy.size.width, 0), 1)
                    }
                    .onEnded { value in
                        let x = min(max(value.location.x / proxy.size.width, 0), 1)
                        seek(x * duration)
                        dragFraction = nil
                    }
            )
        }
        .frame(height: 18)
    }
}

struct ExplicitBadge: View {
    var body: some View {
        Image(systemName: "e.square.fill")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Explicit")
    }
}
