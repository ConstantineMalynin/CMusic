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
                    Shelf(title: topPicks.title ?? "Top Picks for You", items: arranged(topPicks), tileWidth: Metrics.featureTileWidth) { item in
                        ShelfTile(item: item, feature: topPicks.reason ?? "Made for You") { player.play(item) }
                    }
                }

                Shelf(title: "Recently Played", items: music.recentlyPlayed) { item in
                    ShelfTile(item: item) { player.play(item) }
                }

                ForEach(otherRecommendations) { recommendation in
                    Shelf(title: recommendation.title ?? "For You", items: arranged(recommendation)) { item in
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
        .toolbar {
            Button {
                Task { await music.refreshHome() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(music.isRefreshingHome)
            .help("Refresh Home (⌘R)")
        }
    }

    /// Apple returns the same shelves in the same order for hours, so, like Music.app's Home tab, the order
    /// below Top Picks changes with every load. "Recently Played" duplicates the shelf above and is dropped.
    private var otherRecommendations: [MusicPersonalRecommendation] {
        var generator = SeededGenerator(seed: music.homeArrangementSeed)
        return music.recommendations.dropFirst()
            .filter { $0.title != "Recently Played" }
            .shuffled(using: &generator)
    }

    /// Apple sends more items per shelf than fit on screen; starting each shelf at a different item on each
    /// load shows a different slice first without losing anything.
    private func arranged(_ recommendation: MusicPersonalRecommendation) -> [MusicPersonalRecommendation.Item] {
        let items = Array(recommendation.items)
        guard items.count > 1 else { return items }
        var generator = SeededGenerator(seed: music.homeArrangementSeed ^ UInt64(truncatingIfNeeded: recommendation.id.hashValue))
        let offset = Int.random(in: 0 ..< items.count, using: &generator)
        return Array(items[offset...] + items[..<offset])
    }
}

/// SplitMix64: deterministic, so one seed gives the same arrangement for the lifetime of a load.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
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
