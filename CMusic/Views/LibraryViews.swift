//
//  LibraryViews.swift
//  CMusic
//

import MusicKit
import SwiftUI

struct ItemGridView<Item: TileDisplayable & Hashable>: View {
    var title: String
    var items: [Item]
    var isCircle = false
    var play: (Item) -> Void

    @State private var tileWidth: CGFloat?
    @State private var prefetcher = ArtworkPrefetcher()

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Metrics.gridColumns, spacing: 26) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ShelfTile(item: item, isCircle: isCircle) { play(item) }
                        .onAppear { prefetcher.tileAppeared(at: index, in: items, points: tileWidth) }
                }
            }
            .padding(Metrics.margin)
        }
        // Measured once here instead of once per tile.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tileWidth = Metrics.gridTileWidth(fitting: $0) }
        .onChange(of: tileWidth) { prefetcher.reset() }
        .onChange(of: items.count) { prefetcher.reset() }
        .environment(\.tileWidth, tileWidth)
        .navigationTitle(title)
    }
}

extension View {
    /// Loads a library section when this view appears (and again after a refresh), with progress until it arrives.
    func librarySection(_ section: LibrarySection, isEmpty: Bool, item: SidebarItem) -> some View {
        modifier(LibrarySectionLoader(section: section, isEmpty: isEmpty, item: item))
    }
}

private struct LibrarySectionLoader: ViewModifier {
    var section: LibrarySection
    var isEmpty: Bool
    var item: SidebarItem
    @Environment(MusicService.self) private var music

    func body(content: Content) -> some View {
        content
            .overlay {
                if isEmpty, music.loadedSections.contains(section), music.errorMessage == nil {
                    ContentUnavailableView("No \(item.title)", systemImage: item.symbol)
                } else {
                    EmptyStateOverlay(isEmpty: isEmpty)
                }
            }
            .task(id: music.libraryGeneration) { await music.load(section) }
    }
}

struct ArtistsView: View {
    var artists: [Artist]
    @Environment(MusicService.self) private var music
    @Environment(PlayerModel.self) private var player
    @State private var selection: Artist.ID?
    @State private var albums: [Album] = []

    var body: some View {
        HSplitView {
            List(artists, selection: $selection) { artist in
                HStack(spacing: 10) {
                    ArtworkView(artwork: artist.artwork, isCircle: true, side: 32)
                    Text(artist.name)
                }
                .padding(.vertical, 2)
            }
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)

            Group {
                if let artist = artists.first(where: { $0.id == selection }) {
                    ItemGridView(title: artist.name, items: albums) { player.play($0) }
                } else {
                    ContentUnavailableView("Select an Artist", systemImage: "music.microphone")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Artists")
        // Artists load on demand, so they may arrive after this view appears.
        .onChange(of: artists.first?.id, initial: true) { selection = selection ?? artists.first?.id }
        .task(id: selection) {
            guard let artist = artists.first(where: { $0.id == selection }) else { return }
            albums = await music.albums(for: artist)
        }
    }
}

/// Sortable song list. Double-click plays from the clicked row.
struct TrackTable: View {
    var rows: [TrackRow]
    var play: (MusicItemID) -> Void
    @Environment(PlayerModel.self) private var player
    @State private var selection = Set<MusicItemID>()
    @State private var sortOrder: [KeyPathComparator<TrackRow>] = []
    /// Sorting thousands of rows with localized comparison is too slow to repeat on every body evaluation.
    @State private var sortedRows: [TrackRow] = []

    var body: some View {
        // Read once here, so a track change only re-renders the two cells whose `isCurrent` flips.
        let currentID = player.currentItemID
        Table(displayedRows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \.title) { row in
                TrackTitleCell(row: row, isCurrent: row.id == currentID)
            }
            .width(min: 180, ideal: 260)

            TableColumn("Artist", value: \.artist)
            TableColumn("Album", value: \.album)

            TableColumn("Time", value: \.duration) { row in
                Text(row.duration.formattedDuration)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(60)
        }
        .contextMenu(forSelectionType: MusicItemID.self) { ids in
            if let id = ids.first {
                Button("Play") { play(id) }
            }
        } primaryAction: { ids in
            if let id = ids.first { play(id) }
        }
        .onChange(of: sortOrder) { resort() }
        .onChange(of: rows) { resort() }
    }

    /// Falls back to the unsorted rows for the one frame between a sort change and its result.
    private var displayedRows: [TrackRow] {
        sortOrder.isEmpty || sortedRows.isEmpty ? rows : sortedRows
    }

    private func resort() {
        sortedRows = sortOrder.isEmpty ? [] : rows.sorted(using: sortOrder)
    }
}

private struct TrackTitleCell: View {
    var row: TrackRow
    var isCurrent: Bool

    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(artwork: row.artwork, cornerRadius: 3, side: 24)
            Text(row.title)
                .fontWeight(isCurrent ? .semibold : .regular)
            if row.isExplicit { ExplicitBadge() }
        }
    }
}

struct SongsView: View {
    var title: String
    var songs: [Song]
    @Environment(PlayerModel.self) private var player
    @State private var rows: [TrackRow]

    init(title: String = "Songs", songs: [Song]) {
        self.title = title
        self.songs = songs
        _rows = State(initialValue: songs.map { TrackRow($0) })
    }

    var body: some View {
        TrackTable(rows: rows) { id in
            player.play(songs, startingAt: songs.first { $0.id == id })
        }
        .onChange(of: songs.map(\.id)) { rows = songs.map { TrackRow($0) } }
        .navigationTitle(title)
        .navigationSubtitle("\(songs.count) songs")
    }
}

/// Album or playlist header with play/shuffle buttons and its tracklist.
struct CollectionDetailView: View {
    var title: String
    var subtitle: String
    var artwork: Artwork?
    var loadTracks: () async -> [Track]

    @Environment(PlayerModel.self) private var player
    @State private var tracks: [Track] = []
    @State private var rows: [TrackRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 20) {
                ArtworkView(artwork: artwork, cornerRadius: 10, side: 180)
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.largeTitle.bold()).lineLimit(2)
                    Text(subtitle).font(.title3).foregroundStyle(.secondary)
                    if !tracks.isEmpty {
                        Text("\(tracks.count) songs, \(totalMinutes) minutes")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Play", systemImage: "play.fill") { player.play(tracks) }
                            .buttonStyle(.borderedProminent)
                        Button("Shuffle", systemImage: "shuffle") {
                            player.play(tracks)
                            if !player.isShuffled { player.toggleShuffle() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                    .disabled(tracks.isEmpty)
                    .padding(.top, 8)
                }
            }
            .padding(Metrics.margin)

            TrackTable(rows: rows) { id in
                player.play(tracks, startingAt: tracks.first { $0.id == id })
            }
        }
        .navigationTitle(title)
        .task {
            tracks = await loadTracks()
            rows = tracks.map { TrackRow($0) }
        }
    }

    private var totalMinutes: Int {
        Int(tracks.reduce(0) { $0 + ($1.duration ?? 0) } / 60)
    }
}

extension CollectionDetailView {
    init(album: Album, music: MusicService) {
        self.init(title: album.title, subtitle: album.artistName, artwork: album.artwork) {
            await music.tracks(for: album)
        }
    }

    init(playlist: Playlist, music: MusicService) {
        self.init(title: playlist.name, subtitle: playlist.curatorName ?? "", artwork: playlist.artwork) {
            await music.tracks(for: playlist)
        }
    }
}
