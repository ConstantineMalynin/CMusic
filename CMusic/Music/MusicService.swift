//
//  MusicService.swift
//  CMusic
//

import Foundation
import MusicKit
import Observation
import os

private let logger = Logger(subsystem: "com.localStuff.CMusic", category: "MusicService")

/// Library content that is fetched on first visit to its sidebar item rather than at launch.
enum LibrarySection: Hashable {
    case songs, albums, artists, musicVideos, recentlyAdded
}

/// Loads catalog, library and personalized content from Apple Music via MusicKit.
@Observable
final class MusicService {
    private(set) var authorization = MusicAuthorization.currentStatus
    private(set) var canPlayCatalog = false
    private(set) var errorMessage: String?

    // Home / New / Radio
    private(set) var recommendations: [MusicPersonalRecommendation] = []
    private(set) var recentlyPlayed: [RecentlyPlayedMusicItem] = []
    private(set) var topSongs: [Song] = []
    private(set) var topAlbums: [Album] = []
    private(set) var topPlaylists: [Playlist] = []

    // Library. Everything but playlists loads on demand through `load(_:)`.
    private(set) var librarySongs: [Song] = []
    private(set) var libraryAlbums: [Album] = []
    private(set) var recentlyAdded: [Album] = []
    private(set) var libraryArtists: [Artist] = []
    private(set) var libraryPlaylists: [Playlist] = []
    private(set) var libraryMusicVideos: [MusicVideo] = []
    private(set) var loadedSections: Set<LibrarySection> = []
    /// Bumped by `refreshAll()`, so visible library views can key their `.task` on it and reload.
    private(set) var libraryGeneration = 0

    var stations: [Station] {
        recommendations.flatMap(\.stations)
    }

    var isAuthorized: Bool { authorization == .authorized }

    func requestAccess() async {
        authorization = await MusicAuthorization.request()
        if isAuthorized { await refreshAll() }
    }

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Kept after completion, so each section loads once per refresh and concurrent visits share one request.
    @ObservationIgnored private var sectionTasks: [LibrarySection: Task<Void, Never>] = [:]

    /// Every window calls this on appear, so concurrent calls share one refresh.
    func refreshAll() async {
        guard isAuthorized else { return }
        if let refreshTask { return await refreshTask.value }
        invalidateLibrary()
        let task = Task {
            errorMessage = nil
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.loadSubscription() }
                group.addTask { await self.loadPersonalized() }
                group.addTask { await self.loadCharts() }
                group.addTask { await self.loadLibraryPlaylists() }
            }
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    // MARK: - Loading

    private func loadSubscription() async {
        canPlayCatalog = await fetch("subscription") {
            try await MusicSubscription.current.canPlayCatalogContent
        } ?? false
    }

    private func loadPersonalized() async {
        async let recs = fetch("recommendations") {
            Array(try await MusicPersonalRecommendationsRequest().response().recommendations)
        }
        async let recent = fetch("recently played") {
            Array(try await MusicRecentlyPlayedContainerRequest().response().items)
        }
        recommendations = await recs ?? []
        recentlyPlayed = await recent ?? []

        let artwork = ArtworkLoader.shared
        if let topPicks = recommendations.first {
            artwork.prefetch(topPicks.items.prefix(8).map(\.tileArtwork), points: Metrics.featureTileWidth)
        }
        artwork.prefetch(recentlyPlayed.prefix(10).map(\.tileArtwork), points: Metrics.tileWidth)
    }

    /// One request per type: a decoding failure in one chart type shouldn't blank the others.
    private func loadCharts() async {
        async let songs = fetch("song charts") {
            try await Self.chart(Song.self).songCharts.first.map { Array($0.items) } ?? []
        }
        async let albums = fetch("album charts") {
            try await Self.chart(Album.self).albumCharts.first.map { Array($0.items) } ?? []
        }
        async let playlists = fetch("playlist charts") {
            try await Self.chart(Playlist.self).playlistCharts.first.map { Array($0.items) } ?? []
        }
        topSongs = await songs ?? []
        topAlbums = await albums ?? []
        topPlaylists = await playlists ?? []

        let artwork = ArtworkLoader.shared
        artwork.prefetch(topAlbums.prefix(8).map(\.artwork), points: Metrics.featureTileWidth)
        artwork.prefetch(topSongs.prefix(12).map(\.artwork), points: Metrics.songTileWidth)
        artwork.prefetch(topPlaylists.prefix(10).map(\.artwork), points: Metrics.tileWidth)
    }

    private static func chart(_ type: any MusicCatalogChartRequestable.Type) async throws -> MusicCatalogChartsResponse {
        var request = MusicCatalogChartsRequest(kinds: [.mostPlayed], types: [type])
        request.limit = 25
        return try await request.response()
    }

    /// Loaded with the first wave because the sidebar lists them.
    private func loadLibraryPlaylists() async {
        libraryPlaylists = await fetch("library playlists") {
            Array(try await MusicLibraryRequest<Playlist>().response().items)
        } ?? []
    }

    /// Loads a library section the first time it is shown; later calls return at once, or join the running load.
    func load(_ section: LibrarySection) async {
        guard isAuthorized else { return }
        if let task = sectionTasks[section] { return await task.value }
        let generation = libraryGeneration
        let task = Task {
            await fetchSection(section, generation: generation)
            guard generation == libraryGeneration else { return }
            loadedSections.insert(section)
        }
        sectionTasks[section] = task
        await task.value
    }

    /// Previously loaded content stays visible until its section is visited and reloaded.
    private func invalidateLibrary() {
        for task in sectionTasks.values { task.cancel() }
        sectionTasks = [:]
        loadedSections = []
        libraryGeneration += 1
    }

    /// Results are dropped if a refresh happened meanwhile, so a stale load never overwrites a newer one.
    private func fetchSection(_ section: LibrarySection, generation: Int) async {
        func isCurrent() -> Bool { generation == libraryGeneration && !Task.isCancelled }
        switch section {
        case .songs:
            await loadLibrarySongs(isCurrent: isCurrent)
        case .albums:
            let albums = await fetch("library albums") { Array(try await MusicLibraryRequest<Album>().response().items) }
            if isCurrent() { libraryAlbums = albums ?? [] }
        case .artists:
            let artists = await fetch("library artists") { Array(try await MusicLibraryRequest<Artist>().response().items) }
            if isCurrent() { libraryArtists = artists ?? [] }
        case .musicVideos:
            let videos = await fetch("library videos") { Array(try await MusicLibraryRequest<MusicVideo>().response().items) }
            if isCurrent() { libraryMusicVideos = videos ?? [] }
        case .recentlyAdded:
            let added = await fetch("recently added") {
                var request = MusicLibraryRequest<Album>()
                request.sort(by: \.libraryAddedDate, ascending: false)
                request.limit = 50
                return Array(try await request.response().items)
            }
            if isCurrent() { recentlyAdded = added ?? [] }
        }
    }

    /// Paged, so the Songs table fills with the first page while the rest of a large library streams in.
    private func loadLibrarySongs(isCurrent: () -> Bool) async {
        var songs: [Song] = []
        var pageSize = 200
        while true {
            let offset = songs.count
            let limit = pageSize
            guard let page = await fetch("library songs", {
                var request = MusicLibraryRequest<Song>()
                request.limit = limit
                request.offset = offset
                return Array(try await request.response().items)
            }) else { break }
            guard isCurrent() else { return }
            songs += page
            librarySongs = songs
            if page.count < limit { break }
            pageSize = 2000
        }
        if isCurrent() { librarySongs = songs }
    }

    /// Runs one request, logging and recording its failure without affecting the others.
    private func fetch<T>(_ label: String, _ operation: () async throws -> T) async -> T? {
        do {
            return try await operation()
        } catch where error is CancellationError || Task.isCancelled {
            // A refresh superseded this load; that isn't a failure worth showing.
            return nil
        } catch {
            logger.error("\(label, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            #if DEBUG
            errorMessage = "\(label.capitalized): \(error)"
            #else
            errorMessage = "\(label.capitalized): \(error.localizedDescription)"
            #endif
            return nil
        }
    }

    // MARK: - Detail & search

    /// Fetches tracks for an album or playlist so it can be listed.
    func tracks(for album: Album) async -> [Track] {
        (try? await album.with([.tracks]).tracks).map(Array.init) ?? []
    }

    func tracks(for playlist: Playlist) async -> [Track] {
        (try? await playlist.with([.tracks]).tracks).map(Array.init) ?? []
    }

    func albums(for artist: Artist) async -> [Album] {
        (try? await artist.with([.albums]).albums).map(Array.init) ?? []
    }

    /// The artist of the song that is playing, for navigating to their page. Library songs resolve to their library artist.
    func artist(for song: Song) async -> Artist? {
        do {
            return try await song.with([.artists]).artists?.first
        } catch {
            report(error)
            return nil
        }
    }

    /// Everything the artist page shows. A library artist is matched to its catalog counterpart,
    /// since top songs, stations and similar artists only exist in the catalog.
    func details(for artist: Artist) async -> ArtistDetails {
        let relationships: [PartialMusicAsyncProperty<Artist>] = [.topSongs, .albums, .singles, .station, .similarArtists]
        var detailed = try? await artist.with(relationships)
        if detailed?.topSongs?.isEmpty ?? true, let catalog = await catalogArtist(named: artist.name) {
            detailed = (try? await catalog.with(relationships)) ?? catalog
        }
        guard let detailed else { return ArtistDetails(artist: artist) }
        let details = ArtistDetails(
            artist: detailed,
            topSongs: detailed.topSongs.map(Array.init) ?? [],
            albums: detailed.albums.map(Array.init) ?? [],
            singles: detailed.singles.map(Array.init) ?? [],
            station: detailed.station,
            similarArtists: detailed.similarArtists.map(Array.init) ?? [],
            bio: (detailed.editorialNotes?.standard ?? detailed.editorialNotes?.short)?.strippingHTML
        )
        let artwork = ArtworkLoader.shared
        artwork.prefetch(details.topSongs.prefix(5).map(\.artwork), points: 40)
        artwork.prefetch(details.albums.prefix(8).map(\.artwork), points: Metrics.tileWidth)
        return details
    }

    private func catalogArtist(named name: String) async -> Artist? {
        var request = MusicCatalogSearchRequest(term: name, types: [Artist.self])
        request.limit = 5
        let artists = (try? await request.response().artists) ?? []
        return artists.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame } ?? artists.first
    }

    /// The station for a top result's artist, album or playlist, fetched on demand for the "Mix" button.
    func station(for artist: Artist) async -> Station? {
        try? await artist.with([.station]).station
    }

    func topSongs(for artist: Artist) async -> [Song] {
        (try? await artist.with([.topSongs]).topSongs).map(Array.init) ?? []
    }

    /// Searches the catalog across every kind of item at once, like Music.app's search page.
    func search(_ term: String) async -> SearchResults {
        guard !term.isEmpty else { return SearchResults() }
        var request = MusicCatalogSearchRequest(term: term, types: [Artist.self, Album.self, Song.self, Playlist.self])
        request.includeTopResults = true
        request.limit = 25
        do {
            let response = try await request.response()
            let results = SearchResults(
                topResults: Array(response.topResults.prefix(10)),
                artists: Array(response.artists),
                albums: Array(response.albums),
                songs: Array(response.songs),
                playlists: Array(response.playlists)
            )
            let artwork = ArtworkLoader.shared
            artwork.prefetch(results.topResults.prefix(6).map(\.tileArtwork), points: Metrics.featureTileWidth)
            artwork.prefetch(results.artists.prefix(8).map(\.tileArtwork), points: Metrics.tileWidth)
            return results
        } catch {
            report(error)
            return SearchResults()
        }
    }

    private func report(_ error: Error) {
        logger.error("search failed: \(String(describing: error), privacy: .public)")
        errorMessage = error.localizedDescription
    }
}

/// One catalog search, split by item type.
struct SearchResults: Equatable {
    var topResults: [MusicCatalogSearchResponse.TopResult] = []
    var artists: [Artist] = []
    var albums: [Album] = []
    var songs: [Song] = []
    var playlists: [Playlist] = []

    var isEmpty: Bool {
        topResults.isEmpty && artists.isEmpty && albums.isEmpty && songs.isEmpty && playlists.isEmpty
    }
}

struct ArtistDetails: Equatable {
    var artist: Artist
    var topSongs: [Song] = []
    var albums: [Album] = []
    var singles: [Album] = []
    var station: Station?
    var similarArtists: [Artist] = []
    var bio: String?
}

private extension String {
    /// Editorial notes arrive as HTML snippets; the page shows them as plain text.
    var strippingHTML: String {
        replacingOccurrences(of: "<br */?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
