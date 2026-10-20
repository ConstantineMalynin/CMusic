//
//  SearchView.swift
//  CMusic
//

import MusicKit
import SwiftUI

/// Catalog search results: the top result beside its first songs, then more songs, artists, albums and playlists.
struct SearchView: View {
    var term: String
    /// `nil` while the search is running.
    var results: SearchResults?

    @Environment(PlayerModel.self) private var player

    var body: some View {
        ScrollView {
            if let results {
                LazyVStack(alignment: .leading, spacing: 32) {
                    if let top = results.topResults.first {
                        HStack(alignment: .top, spacing: 16) {
                            TopResultCard(item: top)
                                .frame(maxWidth: .infinity)
                            if !results.songs.isEmpty {
                                VStack(spacing: 2) {
                                    ForEach(results.songs.prefix(3)) { song in
                                        SongRow(song: song, isCurrent: song.id == player.currentItemID) {
                                            player.play(results.songs, startingAt: song)
                                        }
                                    }
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.horizontal, Metrics.margin)
                    }

                    SongList(title: "Songs", songs: results.songs, collapsedCount: 8) { song in
                        player.play(results.songs, startingAt: song)
                    }

                    Shelf(title: "Artists", items: results.artists) { artist in
                        ShelfTile(item: artist, isCircle: true)
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
        .navigationTitle("Search")
    }
}

/// The best match, with Play/Shuffle and a Mix button where a station exists. Clicking the artwork or
/// title opens the item's page when it has one.
private struct TopResultCard: View {
    var item: MusicCatalogSearchResponse.TopResult

    @Environment(MusicService.self) private var music
    @Environment(PlayerModel.self) private var player

    private var isArtist: Bool {
        if case .artist = item { true } else { false }
    }

    var body: some View {
        HStack(spacing: 20) {
            identity
                .modifier(DestinationLinkModifier(item: item))

            VStack(alignment: .leading, spacing: 10) {
                Text(item.tileTitle)
                    .font(.title.bold())
                    .lineLimit(2)
                Text(item.tileSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack {
                    if isArtist {
                        Button("Shuffle", systemImage: "shuffle", action: shuffleArtist)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Play", systemImage: "play.fill") { player.play(item) }
                            .buttonStyle(.borderedProminent)
                    }
                    if canMix {
                        Button("Mix", systemImage: "dot.radiowaves.left.and.right", action: mix)
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var identity: some View {
        ArtworkView(artwork: item.tileArtwork, cornerRadius: 8, isCircle: isArtist, shadowRadius: 8, side: 110)
    }

    private var canMix: Bool {
        switch item {
        case .artist, .song, .album: true
        default: false
        }
    }

    private func shuffleArtist() {
        guard case .artist(let artist) = item else { return }
        Task {
            let songs = await music.topSongs(for: artist)
            if !songs.isEmpty { player.play(songs.shuffled()) }
        }
    }

    private func mix() {
        Task {
            var station: Station?
            switch item {
            case .artist(let artist):
                station = await music.station(for: artist)
            case .song(let song):
                station = try? await song.with([.station]).station
            case .album(let album):
                if let artist = try? await album.with([.artists]).artists?.first {
                    station = await music.station(for: artist)
                }
            default:
                break
            }
            if let station { player.play(station) }
        }
    }
}

/// Wraps a view in a navigation link when the item has a page.
struct DestinationLinkModifier<Item: Hashable>: ViewModifier {
    var item: Item

    func body(content: Content) -> some View {
        if let destination = Destination(item) {
            NavigationLink(value: destination) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}
