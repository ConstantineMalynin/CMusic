//
//  BrowseViews.swift
//  CMusic
//

import MusicKit
import SwiftUI

struct HomeView: View {
    @Environment(MusicService.self) private var music
    @Environment(PlayerModel.self) private var player

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if let topPicks = music.recommendations.first {
                    Shelf(title: topPicks.title ?? "Top Picks for You", items: Array(topPicks.items), tileWidth: Metrics.featureTileWidth) { item in
                        ShelfTile(item: item, feature: topPicks.reason ?? "Made for You") { player.play(item) }
                    }
                }

                Shelf(title: "Recently Played", items: music.recentlyPlayed) { item in
                    ShelfTile(item: item) { player.play(item) }
                }

                ForEach(otherRecommendations) { recommendation in
                    Shelf(title: recommendation.title ?? "For You", items: Array(recommendation.items)) { item in
                        ShelfTile(item: item) { player.play(item) }
                    }
                }

                Shelf(title: "Top Songs", items: music.topSongs, tileWidth: Metrics.songTileWidth) { song in
                    ShelfTile(item: song) { player.play(music.topSongs, startingAt: song) }
                }
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { EmptyStateOverlay(isEmpty: music.recommendations.isEmpty && music.topSongs.isEmpty) }
        .navigationTitle("Home")
    }

    /// Apple also returns a "Recently Played" recommendation, which duplicates the shelf above.
    private var otherRecommendations: [MusicPersonalRecommendation] {
        music.recommendations.dropFirst().filter { $0.title != "Recently Played" }
    }
}

struct NewView: View {
    @Environment(MusicService.self) private var music
    @Environment(PlayerModel.self) private var player

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                Shelf(title: "Top Albums", items: music.topAlbums, tileWidth: Metrics.featureTileWidth) { album in
                    ShelfTile(item: album) { player.play(album) }
                }

                Shelf(title: "Top Songs", items: music.topSongs, tileWidth: Metrics.songTileWidth) { song in
                    ShelfTile(item: song) { player.play(music.topSongs, startingAt: song) }
                }

                Shelf(title: "Top Playlists", items: music.topPlaylists) { playlist in
                    ShelfTile(item: playlist) { player.play(playlist) }
                }
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { EmptyStateOverlay(isEmpty: music.topAlbums.isEmpty && music.topSongs.isEmpty) }
        .navigationTitle("New")
    }
}

struct RadioView: View {
    @Environment(MusicService.self) private var music
    @Environment(PlayerModel.self) private var player

    private var recentStations: [Station] {
        music.recentlyPlayed.compactMap {
            if case .station(let station) = $0 { station } else { nil }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                Shelf(title: "Stations for You", items: music.stations, tileWidth: Metrics.featureTileWidth) { station in
                    ShelfTile(item: station) { player.play(station) }
                }

                Shelf(title: "Recently Played", items: recentStations) { station in
                    ShelfTile(item: station) { player.play(station) }
                }
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if music.stations.isEmpty && recentStations.isEmpty {
                ContentUnavailableView(
                    "No Stations",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text("Personalized stations need an active Apple Music subscription.")
                )
            }
        }
        .navigationTitle("Radio")
    }
}

/// Shown while content is still loading or when the API returned nothing.
struct EmptyStateOverlay: View {
    var isEmpty: Bool
    @Environment(MusicService.self) private var music

    var body: some View {
        if isEmpty {
            if let error = music.errorMessage {
                ContentUnavailableView {
                    Label("Couldn't Load Apple Music", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await music.refreshAll() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
