//
//  ArtistDetailView.swift
//  CMusic
//

import MusicKit
import SwiftUI

/// An artist's page: a banner with Shuffle and Mix, their top songs, albums, singles and similar artists.
struct ArtistDetailView: View {
    var artist: Artist

    @Environment(MusicService.self) private var music
    @Environment(PlayerModel.self) private var player
    @State private var details: ArtistDetails?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                ArtistBanner(
                    artist: details?.artist ?? artist,
                    bio: details?.bio,
                    canShuffle: !(details?.topSongs.isEmpty ?? true),
                    canMix: details?.station != nil,
                    shuffle: shuffle,
                    mix: mix
                )

                if let details {
                    SongList(title: "Top Songs", songs: details.topSongs) { song in
                        player.play(details.topSongs, startingAt: song)
                    }

                    Shelf(title: "Albums", items: details.albums) { album in
                        ShelfTile(item: album) { player.play(album) }
                    }

                    Shelf(title: "Singles & EPs", items: details.singles) { album in
                        ShelfTile(item: album) { player.play(album) }
                    }

                    Shelf(title: "Similar Artists", items: details.similarArtists) { artist in
                        ShelfTile(item: artist, isCircle: true)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(artist.name)
        .task { details = await music.details(for: artist) }
    }

    private func shuffle() {
        guard let songs = details?.topSongs, !songs.isEmpty else { return }
        player.play(songs.shuffled())
    }

    private func mix() {
        if let station = details?.station { player.play(station) }
    }
}

/// The artist's artwork blurred across the top of the page, with the name and actions over it.
private struct ArtistBanner: View {
    var artist: Artist
    var bio: String?
    var canShuffle: Bool
    var canMix: Bool
    var shuffle: () -> Void
    var mix: () -> Void

    @State private var showsFullBio = false

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            ArtworkView(artwork: artist.artwork, isCircle: true, shadowRadius: 10, side: 160)

            VStack(alignment: .leading, spacing: 10) {
                Text(artist.name)
                    .font(.system(size: 40, weight: .bold))
                    .lineLimit(2)

                if let bio, !bio.isEmpty {
                    Text(bio)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(showsFullBio ? nil : 2)
                    Button(showsFullBio ? "Less" : "More") { showsFullBio.toggle() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Shuffle", systemImage: "shuffle", action: shuffle)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canShuffle)
                    Button("Mix", systemImage: "dot.radiowaves.left.and.right", action: mix)
                        .buttonStyle(.bordered)
                        .disabled(!canMix)
                        .help("Play a station based on this artist")
                }
                .controlSize(.large)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Metrics.margin)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BannerBackdrop(artwork: artist.artwork)
        }
    }
}

/// The artwork stretched and blurred behind the banner, faded into the page at the bottom.
private struct BannerBackdrop: View {
    var artwork: Artwork?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let artwork {
                    ArtworkView(artwork: artwork, cornerRadius: 0, side: max(proxy.size.width, proxy.size.height))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: 60)
                        .saturation(1.2)
                        .opacity(0.55)
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .overlay {
                LinearGradient(
                    colors: [.clear, Color(nsColor: .windowBackgroundColor).opacity(0.9)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
    }
}
