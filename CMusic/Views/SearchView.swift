//
//  SearchView.swift
//  CMusic
//

import MusicKit
import SwiftUI

/// Catalog search results grouped by kind: top results, artists, songs, albums and playlists.
struct SearchView: View {
    var term: String
    /// `nil` while the search is running.
    var results: SearchResults?

    @Environment(PlayerModel.self) private var player
    @State private var showsAllSongs = false

    private static let collapsedSongCount = 8

    var body: some View {
        ScrollView {
            if let results {
                LazyVStack(alignment: .leading, spacing: 32) {
                    Shelf(title: "Top Results", items: results.topResults, tileWidth: Metrics.featureTileWidth) { item in
                        ShelfTile(item: item) { player.play(item) }
                    }

                    Shelf(title: "Artists", items: results.artists) { artist in
                        ShelfTile(item: artist, isCircle: true)
                    }

                    if !results.songs.isEmpty {
                        songs(results.songs)
                    }

                    Shelf(title: "Albums", items: results.albums) { album in
                        ShelfTile(item: album) { player.play(album) }
                    }

                    Shelf(title: "Playlists", items: results.playlists) { playlist in
                        ShelfTile(item: playlist) { player.play(playlist) }
                    }
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if results == nil {
                ProgressView()
            } else if results?.isEmpty == true {
                ContentUnavailableView.search(text: term)
            }
        }
        .onChange(of: term) { showsAllSongs = false }
        .navigationTitle("Search")
    }

    private func songs(_ songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Songs").font(.title2.bold())
                Spacer()
                if songs.count > Self.collapsedSongCount {
                    Button(showsAllSongs ? "Show Less" : "Show All") { showsAllSongs.toggle() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Metrics.margin)

            let shown = showsAllSongs ? songs : Array(songs.prefix(Self.collapsedSongCount))
            VStack(spacing: 2) {
                ForEach(shown) { song in
                    SongRow(song: song, isCurrent: song.id == player.currentItemID) {
                        player.play(songs, startingAt: song)
                    }
                }
            }
            .padding(.horizontal, Metrics.margin - 8)
        }
    }
}

/// One line per song with artwork, title, artist and duration. Double-click or the hover play button plays it.
private struct SongRow: View {
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
