//
//  Shelf.swift
//  CMusic
//

import MusicKit
import SwiftUI

enum Metrics {
    static let margin: CGFloat = 28

    static let gridMinimum: CGFloat = 160
    static let gridMaximum: CGFloat = 220
    static let gridSpacing: CGFloat = 22
    static let gridColumns = [GridItem(.adaptive(minimum: gridMinimum, maximum: gridMaximum), spacing: gridSpacing)]

    /// The column width `gridColumns` produces for a container of this width, so tiles can skip measuring.
    static func gridTileWidth(fitting containerWidth: CGFloat) -> CGFloat? {
        let available = containerWidth - margin * 2
        guard available >= gridMinimum else { return nil }
        let columns = Int((available + gridSpacing) / (gridMinimum + gridSpacing))
        let width = min(gridMaximum, (available - CGFloat(columns - 1) * gridSpacing) / CGFloat(columns))
        return floor(width * 2) / 2
    }

    // Shared with artwork prefetching, so prefetched sizes match what the shelves request.
    static let tileWidth: CGFloat = 170
    static let featureTileWidth: CGFloat = 220
    static let songTileWidth: CGFloat = 140
}

extension EnvironmentValues {
    /// The width tiles are laid out at, when the container knows it, so artwork can skip measuring itself.
    @Entry var tileWidth: CGFloat? = nil
}

/// Warms artwork for the tiles just past the one that appeared, so scrolling reveals loaded art, not placeholders.
///
/// A plain class held in `@State`: advancing the cursor must not invalidate the shelf or grid that owns it.
final class ArtworkPrefetcher {
    private static let lookahead = 10
    /// Exclusive end of the range already handed to `ArtworkLoader`.
    private var end = 0

    func tileAppeared<Item: TileDisplayable>(at index: Int, in items: [Item], points: CGFloat?) {
        guard let points else { return }
        let upper = min(index + 1 + Self.lookahead, items.count)
        let lower = max(end, index + 1)
        guard lower < upper else { return }
        ArtworkLoader.shared.prefetch(items[lower..<upper].lazy.map(\.tileArtwork), points: points)
        end = upper
    }

    func reset() {
        end = 0
    }
}

/// A titled, horizontally scrolling row of items, as used on Home, New and Radio.
struct Shelf<Item: TileDisplayable, Tile: View>: View {
    var title: String
    var items: [Item]
    var tileWidth: CGFloat = Metrics.tileWidth
    @ViewBuilder var tile: (Item) -> Tile

    @State private var prefetcher = ArtworkPrefetcher()

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Text(title).font(.title2.bold())
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Metrics.margin)

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            tile(item)
                                .frame(width: tileWidth)
                                .onAppear { prefetcher.tileAppeared(at: index, in: items, points: tileWidth) }
                        }
                    }
                    .padding(.horizontal, Metrics.margin)
                }
                .scrollIndicators(.never)
                .environment(\.tileWidth, tileWidth)
                .onChange(of: items.count) { prefetcher.reset() }
            }
        }
    }
}

/// Square artwork with a title and subtitle underneath. Hover reveals a play button.
struct MediaTile<Item: TileDisplayable>: View {
    var item: Item
    var isCircle = false
    var play: (() -> Void)?

    @Environment(\.tileWidth) private var tileWidth
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: isCircle ? .center : .leading, spacing: 6) {
            ArtworkView(artwork: item.tileArtwork, cornerRadius: 8, isCircle: isCircle, shadowRadius: 6, side: tileWidth)
                .overlay(alignment: .bottomLeading) {
                    if isHovering, let play {
                        Button(action: play) {
                            Image(systemName: "play.fill")
                                .font(.body.bold())
                                .frame(width: 32, height: 32)
                                .background(.regularMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .transition(.opacity)
                    }
                }

            VStack(alignment: isCircle ? .center : .leading, spacing: 1) {
                Text(item.tileTitle).font(.callout.weight(.medium))
                if !item.tileSubtitle.isEmpty {
                    Text(item.tileSubtitle).font(.callout).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}

/// The tall "Top Picks" card with a caption above and a tinted footer.
struct FeatureCard<Item: TileDisplayable>: View {
    var eyebrow: String
    var item: Item

    @Environment(\.tileWidth) private var tileWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            VStack(spacing: 0) {
                ArtworkView(artwork: item.tileArtwork, cornerRadius: 0, side: tileWidth)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.tileTitle).font(.headline)
                    Text(item.tileSubtitle).font(.caption).opacity(0.8)
                }
                .lineLimit(2)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                .padding(12)
                .background(footerColor)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background { TileShadow(cornerRadius: 10, radius: 8, opacity: 0.18) }
        }
        .contentShape(Rectangle())
    }

    private var footerColor: Color {
        item.tileArtwork?.backgroundColor.map { Color(cgColor: $0).opacity(0.9) } ?? .gray
    }
}

/// Wraps albums and playlists in a navigation link, and plays everything else on double-click.
/// Items that can't be played, like artists, pass no `play` and get no play button.
struct ShelfTile<Item: TileDisplayable & Hashable>: View {
    var item: Item
    var isCircle = false
    var feature: String?
    var play: (() -> Void)? = nil

    var body: some View {
        Group {
            if let feature {
                FeatureCard(eyebrow: feature, item: item)
            } else {
                MediaTile(item: item, isCircle: isCircle, play: play)
            }
        }
        .modifier(DestinationLink(item: item))
        .simultaneousGesture(TapGesture(count: 2).onEnded { play?() })
    }
}

/// Navigates to album/playlist details; other item types are left as-is.
private struct DestinationLink<Item: Hashable>: ViewModifier {
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

enum Destination: Hashable {
    case album(Album)
    case playlist(Playlist)
    case artist(Artist)

    init?(_ item: some Hashable) {
        switch item {
        case let album as Album: self = .album(album)
        case let playlist as Playlist: self = .playlist(playlist)
        case let artist as Artist: self = .artist(artist)
        case let recent as RecentlyPlayedMusicItem:
            switch recent {
            case .album(let album): self = .album(album)
            case .playlist(let playlist): self = .playlist(playlist)
            default: return nil
            }
        case let rec as MusicPersonalRecommendation.Item:
            switch rec {
            case .album(let album): self = .album(album)
            case .playlist(let playlist): self = .playlist(playlist)
            default: return nil
            }
        case let top as MusicCatalogSearchResponse.TopResult:
            switch top {
            case .album(let album): self = .album(album)
            case .playlist(let playlist): self = .playlist(playlist)
            case .artist(let artist): self = .artist(artist)
            default: return nil
            }
        default: return nil
        }
    }
}
