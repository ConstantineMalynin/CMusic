//
//  SongList.swift
//  CMusic
//

import MusicKit
import SwiftUI

/// A titled list of song rows that starts collapsed, with a "Show All" toggle when there are more.
struct SongList: View {
    var title: String
    var songs: [Song]
    var collapsedCount = 5
    /// Called with the song that was chosen; the whole list is queued after it.
    var play: (Song) -> Void

    @Environment(PlayerModel.self) private var player
    @State private var showsAll = false

    var body: some View {
        if !songs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.title2.bold())
                    .padding(.horizontal, Metrics.margin)

                let shown = showsAll ? songs : Array(songs.prefix(collapsedCount))
                VStack(spacing: 2) {
                    ForEach(shown) { song in
                        SongRow(song: song, isCurrent: song.id == player.currentItemID) { play(song) }
                    }
                }
                .padding(.horizontal, Metrics.margin - 8)

                if songs.count > collapsedCount {
                    Button(showsAll ? "Show Less" : "Show All") { showsAll.toggle() }
                        .buttonStyle(.bordered)
                        .padding(.horizontal, Metrics.margin)
                }
            }
            .onChange(of: songs.first?.id) { showsAll = false }
        }
    }
}

/// One line per song with artwork, title, artist and duration. Double-click or the hover play button plays it.
struct SongRow: View {
    var song: Song
    var isCurrent: Bool
    var play: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(artwork: song.artwork, cornerRadius: 4, side: 40)
                .overlay {
                    if isHovering {
                        Button(action: play) {
                            Image(systemName: "play.fill")
                                .font(.body.bold())
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(song.title).fontWeight(isCurrent ? .semibold : .medium)
                    if song.contentRating == .explicit { ExplicitBadge() }
                }
                Text(song.albumTitle.map { "\(song.artistName) — \($0)" } ?? song.artistName)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .lineLimit(1)

            Spacer(minLength: 16)

            Text((song.duration ?? 0).formattedDuration)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: play)
        .contextMenu { Button("Play", action: play) }
    }
}
